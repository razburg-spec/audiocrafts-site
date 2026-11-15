# Accounts setup (Supabase)

The site stays static. Accounts, the plugin library, iLok code pool and private
installer storage live in a Supabase project. Until `js/config.js` has the
project URL and anon key, `/account/` shows "Accounts are opening soon".

## 1. Project
1. Create a Supabase project (free tier, region close to users, e.g. Frankfurt).
2. SQL Editor → paste `supabase/schema.sql` → Run. It is idempotent.
3. Project Settings → API: copy the Project URL and the anon (publishable) key
   into `js/config.js`. Both are public by design; access is enforced by RLS.

## 2. Auth settings
- Authentication → Providers → Email: enabled, "Confirm email" ON.
- Authentication → URL Configuration:
  - Site URL: `https://audiocrafts.razburg.com/account/`
  - Redirect URLs: `https://audiocrafts.razburg.com/account/`,
    `https://deploy-preview-*--rbaudiocrafts.netlify.app/account/`
- Authentication → SMTP: set a custom SMTP sender (e.g. Resend). Supabase's
  built-in mailer only delivers to project team members, so sign-up emails to
  the public need custom SMTP.
- Optional: email templates with the AudioCrafts name.

## 3. iLok activation codes
Generate a batch of activation codes per plugin in PACE Central (licence
template: perpetual, 2 activations). Import them with the Table editor
(`license_codes`, columns `product_slug`, `code`) or SQL:

```sql
insert into public.license_codes (product_slug, code)
select 'lumen', unnest(array['CODE-1', 'CODE-2'])
on conflict (code) do nothing;
```

Users who claimed while the pool was empty get a code automatically the next
time they open My plugins.

Pool status:

```sql
select product_slug,
       count(*) filter (where assigned_to is null) as free,
       count(*) as total
from public.license_codes group by product_slug;
```

## 4. Installers
Upload to Storage bucket `installers` as `<product_slug>/<file>`, e.g.
`lumen/Lumen-0.4.0-mac.pkg`, then add a row:

```sql
insert into public.downloads (product_slug, platform, formats, version, min_os, storage_path, size_bytes)
values ('lumen', 'mac', 'AAX · VST3 · AU', '0.4.0', 'macOS 11+', 'lumen/Lumen-0.4.0-mac.pkg', 31000000);
```

Only signed-in users who added that plugin can create a 5-minute download
link. Convert stays a public download (`/download/convert-*`), no account.
Free-tier storage allows files up to 50 MB.
