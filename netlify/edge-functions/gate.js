// Gate for /files/<product_slug>/<file>: only signed-in users who added that
// product in My plugins can download. The account page sets a short-lived
// "rba_at" cookie (Supabase access token, Path=/files) right before the download.
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "./site-config.js";

export default async (request, context) => {
  const url = new URL(request.url);
  const slug = url.pathname.split("/")[2] || "";
  const deny = () => Response.redirect(new URL("/account/#claim=" + encodeURIComponent(slug), url), 302);
  if (!slug || !SUPABASE_URL || !SUPABASE_ANON_KEY) return deny();

  const m = (request.headers.get("cookie") || "").match(/(?:^|;\s*)rba_at=([^;]+)/);
  if (!m) return deny();

  let rows = [];
  try {
    const r = await fetch(
      SUPABASE_URL + "/rest/v1/claims?select=product_slug&product_slug=eq." + encodeURIComponent(slug),
      { headers: { apikey: SUPABASE_ANON_KEY, Authorization: "Bearer " + decodeURIComponent(m[1]) } }
    );
    if (!r.ok) return deny();
    rows = await r.json();
  } catch (e) {
    return deny();
  }
  if (!Array.isArray(rows) || rows.length === 0) return deny();

  const res = await context.next();
  const out = new Response(res.body, res);
  out.headers.set("Cache-Control", "private, no-store");
  return out;
};

export const config = { path: "/files/*" };
