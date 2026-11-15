# Raz Burg AudioCrafts website

Static site for https://audiocrafts.razburg.com, deployed by Netlify on every push to `main`.

- `index.html`: landing page (Lumen, Chroma, Convert)
- `lumen/manual/`, `chroma/manual/`: web user guides (generated in the plugin repos)
- `img/`: screenshots and logo

## Accounts
Sign up / sign in and the My plugins library live at `/account/` (Supabase auth,
static page). Setup steps: `supabase/SETUP.md`. Schema: `supabase/schema.sql`.
