-- Raz Burg AudioCrafts accounts: products, installer downloads, iLok code pool, claims.
-- Run once in the Supabase SQL editor (Project > SQL Editor > New query > paste > Run).
-- Safe to re-run: every statement is idempotent.

-- ── Tables ───────────────────────────────────────────────────────────────

create table if not exists public.products (
  slug        text primary key,
  name        text not null,
  tagline     text,
  needs_ilok  boolean not null default true,   -- false = free app, no licence (still needs an account to download)
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

-- One row per iLok activation code generated in PACE. Never readable by users directly.
create table if not exists public.license_codes (
  id            bigint generated always as identity primary key,
  product_slug  text not null references public.products(slug),
  code          text not null unique,
  assigned_to   uuid,                          -- no FK on purpose: a code stays used after its user deletes the account
  assigned_at   timestamptz,
  created_at    timestamptz not null default now()
);
alter table public.downloads add column if not exists note text;
alter table public.license_codes drop constraint if exists license_codes_assigned_to_fkey;
create index if not exists license_codes_free_idx
  on public.license_codes (product_slug, id) where assigned_to is null;

-- A user's plugins. One row per user per product = one iLok code per user per product.
create table if not exists public.claims (
  user_id          uuid not null references auth.users(id) on delete cascade,
  product_slug     text not null references public.products(slug),
  license_code_id  bigint references public.license_codes(id),
  claimed_at       timestamptz not null default now(),
  primary key (user_id, product_slug)
);

-- ── Row level security ───────────────────────────────────────────────────

alter table public.products      enable row level security;
alter table public.downloads     enable row level security;
alter table public.license_codes enable row level security;  -- no policies: no direct access
alter table public.claims        enable row level security;

drop policy if exists products_read on public.products;
create policy products_read on public.products
  for select to anon, authenticated using (true);

drop policy if exists downloads_read on public.downloads;
create policy downloads_read on public.downloads
  for select to authenticated using (published);

drop policy if exists claims_read_own on public.claims;
create policy claims_read_own on public.claims
  for select to authenticated using (user_id = auth.uid());

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

-- List the signed-in user's plugins with their iLok codes.
-- Claims made while a code pool was empty get a code as soon as codes are added.
create or replace function public.my_plugins()
returns table (product_slug text, claimed_at timestamptz, license_code text)
language plpgsql security definer set search_path = public
as $$
#variable_conflict use_column
declare
  r record;
  v_code_id bigint;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;

  for r in
    select c.product_slug as slug
    from claims c join products p on p.slug = c.product_slug
    where c.user_id = auth.uid() and c.license_code_id is null and p.needs_ilok
  loop
    select lc.id into v_code_id
    from license_codes lc
    where lc.product_slug = r.slug and lc.assigned_to is null
    order by lc.id
    limit 1
    for update skip locked;

    if v_code_id is not null then
      update license_codes set assigned_to = auth.uid(), assigned_at = now() where id = v_code_id;
      update claims set license_code_id = v_code_id
        where user_id = auth.uid() and claims.product_slug = r.slug;
    end if;
  end loop;

  return query
    select c.product_slug, c.claimed_at, lc.code
    from claims c left join license_codes lc on lc.id = c.license_code_id
    where c.user_id = auth.uid();
end $$;

-- Let a user delete their own account (claims are removed; used codes stay used).
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

insert into public.products (slug, name, tagline, needs_ilok, sort) values
  ('lumen',   'Lumen',   'Reverb · Delay · Shimmer',          true,  1),
  ('chroma',  'Chroma',  'Multi-character compressor',        true,  2),
  ('convert', 'Convert', 'Media converter · no licence needed', false, 3)
on conflict (slug) do update
  set name = excluded.name, tagline = excluded.tagline,
      needs_ilok = excluded.needs_ilok, sort = excluded.sort;

insert into public.downloads (product_slug, platform, formats, version, min_os, public_url, size_bytes, note)
select * from (values
  ('convert', 'mac',     'App', '0.1.0', 'macOS 11+ · Apple Silicon', '/files/convert/Convert_0.1.0_aarch64.dmg',   26036048::bigint, 'Signed and notarized by Apple.'),
  ('convert', 'windows', 'App', '0.1.0', 'Windows 10/11 · x64',       '/files/convert/Convert_0.1.0_x64-setup.exe', 88489556::bigint, 'If Windows warns on first launch, click More info, then Run anyway.')
) v(product_slug, platform, formats, version, min_os, public_url, size_bytes, note)
where not exists (select 1 from public.downloads d where d.product_slug = 'convert');

-- Plugin installers served through the /files/* gate (one row per file).
insert into public.downloads (product_slug, platform, formats, version, min_os, public_url, size_bytes, note)
select * from (values
  ('lumen',  'windows', 'VST3', '0.3.1', 'Windows 10/11 · 64-bit', '/files/lumen/Lumen-0.3.1-Windows-Setup.exe',   4091386::bigint, 'Not signed yet: if Windows shows "Windows protected your PC", click More info, then Run anyway. AAX for Pro Tools on Windows coming soon.'),
  ('lumen',  'mac',     'AAX · VST3 · AU', '0.3.1', 'macOS 11+ · Apple Silicon & Intel', '/files/lumen/Lumen-0.3.1-mac.pkg',   10513960::bigint, 'Signed and notarized by Apple. Installs AAX (Pro Tools), VST3 and AU.'),
  ('chroma', 'mac',     'AAX · VST3 · AU', '0.1.3', 'macOS 11+ · Apple Silicon & Intel', '/files/chroma/Chroma-0.1.3-mac.pkg', 10107547::bigint, 'Signed and notarized by Apple. Installs AAX (Pro Tools), VST3 and AU.'),
  ('chroma', 'windows', 'VST3', '0.1.3', 'Windows 10/11 · 64-bit', '/files/chroma/Chroma-0.1.3-Windows-Setup.exe', 4057247::bigint, 'Not signed yet: if Windows shows "Windows protected your PC", click More info, then Run anyway. AAX for Pro Tools on Windows coming soon.')
) v(product_slug, platform, formats, version, min_os, public_url, size_bytes, note)
where not exists (select 1 from public.downloads d where d.public_url = v.public_url);
