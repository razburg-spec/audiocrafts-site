# Raz Burg AudioCrafts website

Static site for https://audiocrafts.razburg.com, deployed by Netlify on every push to `main`.

- `index.html`: landing page (Lumen, Chroma, Convert)
- `lumen/manual/`, `chroma/manual/`: web user guides (generated in the plugin repos)
- `img/`: screenshots and logo

## Accounts
Sign up / sign in and the My plugins library live at `/account/` (Supabase auth,
static page). Setup steps: `supabase/SETUP.md`. Schema: `supabase/schema.sql`.

## Design
Shared styles live in `css/site.css` (self-hosted Inter / Inter Tight in `fonts/`).
Home `index.html` and product pages `lumen/`, `chroma/`, `convert/` share the same
top bar and footer markup; keep them in sync when adding a product. The plugin
"Buy"/info button points to `/#lumen`, so keep the `#lumen` anchor on the home page.

## Version manifest
`/versions.json` lists the latest version of each product for in-plugin update
checks (`products.<slug>.latest`, `download_url`, `notes`). Bump it with every
release. Served with CORS `*` and a 5-minute cache (`_headers`).
