-- Raz Burg AudioCrafts accounts: products, installer downloads, claims, plugin activations.
-- Run once in the Supabase SQL editor (Project > SQL Editor > New query > paste > Run).
-- Safe to re-run: every statement is idempotent.

-- ── Tables ───────────────────────────────────────────────────────────────

create table if not exists public.products (
  slug        text primary key,
  name        text not null,
  tagline     text,
  needs_ilok  boolean not null default false,  -- unused since 2026-11-18 (iLok dropped); kept so old rows load
  available   boolean not null default true,   -- false hides it from My plugins
  sort        int not null default 0
);

create table if not exists public.downloads (
  id            bigint generated always as identity primary key,
  product_slug  text not null references public.products(slug) on delete cascade,
  platform      text not null check (platform in ('mac', 'windows')),
  formats       text not null,                 -- e.g. 'AAX · VST3 · AU'
  version       text not null,
  min_os        text,                          -- e.g. 'macOS 11+ · Apple Silicon & Intel'
  storage_path  text,                          -- path in the private 'installers' bucket: '<product_slug>/<file>'
  public_url    text,                          -- site path served through the /files/* gate, e.g. '/files/convert/x.dmg'
  note          text,                          -- short note shown under the download
  size_bytes    bigint,
  published     boolean not null default true,
  created_at    timestamptz not null default now(),
  check (storage_path is not null or public_url is not null)
);

-- A user's plugins. One row per user per product.
create table if not exists public.claims (
  user_id          uuid not null references auth.users(id) on delete cascade,
  product_slug     text not null references public.products(slug),
  claimed_at       timestamptz not null default now(),
  primary key (user_id, product_slug)
);

-- iLok was dropped on 2026-11-18 in favour of our own activation (below).
alter table public.claims drop column if exists license_code_id;
drop table if exists public.license_codes;

-- Plugins that need activation: the plugin opens /account/#activate=..., the user
-- approves it while signed in, and the plugin collects a token for that computer.
alter table public.products add column if not exists needs_activation boolean not null default false;

-- One row per activated computer. At most 2 per user per plugin (see activation_approve).
create table if not exists public.activations (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  product_slug  text not null references public.products(slug),
  machine_id    text not null,                 -- hashed device id sent by the plugin (never the raw id)
  machine_name  text not null default '',      -- e.g. 'Studio Mac', shown in My plugins
  token         text not null unique,          -- secret the plugin keeps; never readable through the API
  created_at    timestamptz not null default now(),
  last_seen     timestamptz not null default now(),
  unique (user_id, product_slug, machine_id)
);

-- Short-lived hand-over from the browser to the plugin, keyed by a random nonce
-- that only the plugin (and the URL it opened) knows. Never readable directly.
create table if not exists public.activation_requests (
  nonce          text primary key,
  activation_id  bigint not null references public.activations(id) on delete cascade,
  created_at     timestamptz not null default now()
);

-- ── Row level security ───────────────────────────────────────────────────

alter table public.products      enable row level security;
alter table public.downloads     enable row level security;
alter table public.claims        enable row level security;
alter table public.activations   enable row level security;
alter table public.activation_requests enable row level security;  -- no policies: no direct access

drop policy if exists products_read on public.products;
create policy products_read on public.products
  for select to anon, authenticated using (true);

drop policy if exists downloads_read on public.downloads;
create policy downloads_read on public.downloads
  for select to authenticated using (published);

drop policy if exists claims_read_own on public.claims;
create policy claims_read_own on public.claims
  for select to authenticated using (user_id = auth.uid());

-- Users see and remove their own activated computers (token column is not granted).
drop policy if exists activations_read_own on public.activations;
create policy activations_read_own on public.activations
  for select to authenticated using (user_id = auth.uid());
drop policy if exists activations_delete_own on public.activations;
create policy activations_delete_own on public.activations
  for delete to authenticated using (user_id = auth.uid());
revoke all on public.activations from anon, authenticated;
grant select (id, product_slug, machine_name, created_at, last_seen) on public.activations to authenticated;
grant delete on public.activations to authenticated;
revoke all on public.activation_requests from anon, authenticated;

-- ── Functions called by the site ─────────────────────────────────────────

-- Add a plugin to the signed-in user's account (idempotent).
create or replace function public.claim_plugin(p_slug text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if not exists (select 1 from products where slug = p_slug and available) then
    raise exception 'unknown_product';
  end if;
  insert into claims (user_id, product_slug) values (auth.uid(), p_slug)
  on conflict do nothing;
end $$;

-- List the signed-in user's plugins.
drop function if exists public.my_plugins();
create or replace function public.my_plugins()
returns table (product_slug text, claimed_at timestamptz)
language sql security definer set search_path = public
as $$
  select c.product_slug, c.claimed_at from claims c where c.user_id = auth.uid();
$$;

-- ── Plugin activation ────────────────────────────────────────────────────
-- Called by /account/ (signed in) after the user clicks "Activate" for a computer.
-- Adds the plugin to the library if needed. Re-activating the same computer reuses its slot.
create or replace function public.activation_approve(p_nonce text, p_slug text, p_machine text, p_name text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_id    bigint;
  v_count int;
  v_max   constant int := 2;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if p_nonce is null or p_nonce !~ '^[A-Za-z0-9]{32,128}$'
     or p_machine is null or p_machine !~ '^[A-Za-z0-9]{16,128}$' then
    raise exception 'bad_request';
  end if;
  if not exists (select 1 from products where slug = p_slug and available and needs_activation) then
    raise exception 'unknown_product';
  end if;

  insert into claims (user_id, product_slug) values (auth.uid(), p_slug) on conflict do nothing;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text || '/' || p_slug));

  select id into v_id from activations
  where user_id = auth.uid() and product_slug = p_slug and machine_id = p_machine;

  if v_id is null then
    select count(*) into v_count from activations where user_id = auth.uid() and product_slug = p_slug;
    if v_count >= v_max then raise exception 'limit_reached'; end if;
    insert into activations (user_id, product_slug, machine_id, machine_name, token)
    values (auth.uid(), p_slug, p_machine, left(coalesce(p_name, ''), 80),
            replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
    returning id into v_id;
  else
    update activations
    set machine_name = left(coalesce(nullif(p_name, ''), machine_name), 80), last_seen = now()
    where id = v_id;
  end if;

  delete from activation_requests where created_at < now() - interval '1 hour';
  insert into activation_requests (nonce, activation_id) values (p_nonce, v_id)
  on conflict (nonce) do update set activation_id = excluded.activation_id, created_at = now();
  return jsonb_build_object('ok', true);
end $$;

-- Called by the plugin (anon) every few seconds after it opened the browser.
-- Returns null until the user approved, then the token once.
create or replace function public.activation_poll(p_nonce text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_token text;
  v_email text;
begin
  select a.token, u.email into v_token, v_email
  from activation_requests r
  join activations a on a.id = r.activation_id
  join auth.users u on u.id = a.user_id
  where r.nonce = p_nonce and r.created_at > now() - interval '1 hour';
  if v_token is null then return null; end if;
  delete from activation_requests where nonce = p_nonce;
  return jsonb_build_object('token', v_token, 'email', v_email);
end $$;

-- Called by the plugin now and then: is this computer still activated?
-- false once the user removed it in My plugins or deleted the account.
create or replace function public.activation_check(p_token text, p_machine text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
begin
  update activations set last_seen = now() where token = p_token and machine_id = p_machine;
  return jsonb_build_object('ok', found);
end $$;

-- Called by the plugin's "Deactivate this computer" button.
create or replace function public.activation_release(p_token text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
begin
  delete from activations where token = p_token;
  return jsonb_build_object('ok', true);
end $$;

-- Let a user delete their own account (claims and activations are removed).
create or replace function public.delete_my_account()
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  delete from auth.users where id = auth.uid();
end $$;

revoke all on function public.claim_plugin(text)   from public, anon;
revoke all on function public.my_plugins()          from public, anon;
revoke all on function public.delete_my_account()   from public, anon;
grant execute on function public.claim_plugin(text) to authenticated;
grant execute on function public.my_plugins()        to authenticated;
grant execute on function public.delete_my_account() to authenticated;
revoke all on function public.activation_approve(text, text, text, text) from public, anon;
revoke all on function public.activation_poll(text)          from public;
revoke all on function public.activation_check(text, text)   from public;
revoke all on function public.activation_release(text)       from public;
grant execute on function public.activation_approve(text, text, text, text) to authenticated;
grant execute on function public.activation_poll(text)        to anon, authenticated;
grant execute on function public.activation_check(text, text) to anon, authenticated;
grant execute on function public.activation_release(text)     to anon, authenticated;

-- ── Private installer storage ────────────────────────────────────────────
-- Upload files as installers/<product_slug>/<file>. Only users who added that
-- plugin can create a (short-lived) download link.

insert into storage.buckets (id, name, public)
values ('installers', 'installers', false)
on conflict (id) do nothing;

drop policy if exists "claimed users read installers" on storage.objects;
create policy "claimed users read installers" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'installers'
    and exists (
      select 1 from public.claims c
      where c.user_id = auth.uid()
        and c.product_slug = (storage.foldername(name))[1]
    )
  );

-- ── Seed data ────────────────────────────────────────────────────────────

insert into public.products (slug, name, tagline, needs_ilok, needs_activation, sort) values
  ('chroma',  'Chroma',  'Multi-character compressor',        false, true,  1),
  ('lumen',   'Lumen',   'Reverb · Delay · Shimmer',          false, true,  3),
  ('convert', 'Convert', 'Media converter · no licence needed', false, false, 4)
on conflict (slug) do update
  set name = excluded.name, tagline = excluded.tagline, needs_ilok = excluded.needs_ilok,
      needs_activation = excluded.needs_activation, sort = excluded.sort;

insert into public.downloads (product_slug, platform, formats, version, min_os, public_url, size_bytes, note)
select * from (values
  ('convert', 'mac',     'App', '0.1.1', 'macOS 11+ · Apple Silicon', '/files/convert/Convert_0.1.1_aarch64.dmg',   25616334::bigint, 'Signed and notarized by Apple.'),
  ('convert', 'windows', 'App', '0.1.1', 'Windows 10/11 · x64',       '/files/convert/Convert_0.1.1_x64-setup.exe', 89639510::bigint, 'If Windows warns on first launch, click More info, then Run anyway.')
) v(product_slug, platform, formats, version, min_os, public_url, size_bytes, note)
where not exists (select 1 from public.downloads d where d.product_slug = 'convert');

-- Plugin installers served through the /files/* gate (one row per file).
insert into public.downloads (product_slug, platform, formats, version, min_os, public_url, size_bytes, note)
select * from (values
  ('lumen',  'windows', 'VST3', '0.4.1', 'Windows 10/11 · 64-bit', '/files/lumen/Lumen-0.4.1-Windows-Setup.exe',   4107090::bigint, 'Not signed yet: if Windows shows "Windows protected your PC", click More info, then Run anyway. AAX for Pro Tools on Windows coming soon.'),
  ('lumen',  'mac',     'AAX · VST3 · AU', '0.4.1', 'macOS 11+ · Apple Silicon & Intel', '/files/lumen/Lumen-0.4.1-mac.pkg',   10863651::bigint, 'Signed and notarized by Apple. Installs AAX (Pro Tools), VST3 and AU.'),
  ('chroma', 'mac',     'AAX · VST3 · AU', '0.1.5', 'macOS 11+ · Apple Silicon & Intel', '/files/chroma/Chroma-0.1.5-mac.pkg', 10400206::bigint, 'Signed and notarized by Apple. Installs AAX (Pro Tools), VST3 and AU.'),
  ('chroma', 'windows', 'VST3', '0.1.5', 'Windows 10/11 · 64-bit', '/files/chroma/Chroma-0.1.5-Windows-Setup.exe', 4068645::bigint, 'Not signed yet: if Windows shows "Windows protected your PC", click More info, then Run anyway. AAX for Pro Tools on Windows coming soon.')
) v(product_slug, platform, formats, version, min_os, public_url, size_bytes, note)
where not exists (select 1 from public.downloads d where d.product_slug = v.product_slug and d.platform = v.platform);
