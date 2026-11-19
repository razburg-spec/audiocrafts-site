// Cloudflare Pages version of netlify/edge-functions/gate.js.
// Gate for /files/<product_slug>/<file>: only signed-in users who added that
// product in My plugins can download. The account page sets a short-lived
// "rba_at" cookie (Supabase access token, Path=/files) right before the download.
// Same public values as js/config.js (publishable key is public; RLS enforces access).
const SUPABASE_URL = "https://cmolzvodpvktkjgrfrtt.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_2AvUWy3rpblb4qEOgNutVw_4Gfx197l";

// Old installer paths -> current ones (same list as _redirects, which Cloudflare
// does not apply to paths handled by a Function).
const MOVED = {
  "/files/convert/Convert_0.1.0_aarch64.dmg": "/files/convert/Convert_0.1.1_aarch64.dmg",
  "/files/convert/Convert_0.1.0_x64-setup.exe": "/files/convert/Convert_0.1.1_x64-setup.exe",
  "/files/lumen/Lumen-0.3.1-Windows-Setup.exe": "/files/lumen/Lumen-0.4.0-Windows-Setup.exe",
  "/files/chroma/Chroma-0.1.3-Windows-Setup.exe": "/files/chroma/Chroma-0.1.4-Windows-Setup.exe",
};

// Files over Cloudflare Pages' 25 MiB limit are left out of the build
// (scripts/cf-build.sh) and served from the public GitHub repo instead.
const RAW = "https://raw.githubusercontent.com/razburg-spec/audiocrafts-site/main";
const LARGE = new Set([
  "/files/convert/Convert_0.1.1_x64-setup.exe",
]);

export async function onRequest(context) {
  const { request } = context;
  const url = new URL(request.url);
  if (MOVED[url.pathname]) return Response.redirect(new URL(MOVED[url.pathname], url).toString(), 301);
  const slug = url.pathname.split("/")[2] || "";
  const deny = () => Response.redirect(new URL("/account/#claim=" + encodeURIComponent(slug), url).toString(), 302);
  if (!slug) return deny();

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

  if (LARGE.has(url.pathname)) {
    return new Response(null, { status: 302, headers: { Location: RAW + url.pathname, "Cache-Control": "private, no-store" } });
  }

  const res = await context.next();
  const out = new Response(res.body, res);
  out.headers.set("Cache-Control", "private, no-store");
  return out;
}
