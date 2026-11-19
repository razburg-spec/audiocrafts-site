// Cookieless page-view counter. js/hit.js posts {p: path, r: referrer} here once per
// page load; this forwards it to Supabase public.log_visit. The IP and user agent are
// only passed through to be hashed with a salt that changes daily; neither is stored.
const SUPABASE_URL = "https://cmolzvodpvktkjgrfrtt.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_2AvUWy3rpblb4qEOgNutVw_4Gfx197l";
const BOTS = /bot|crawl|spider|slurp|preview|headless|lighthouse|facebookexternalhit|curl|wget|python|monitor/i;

export async function onRequestPost(context) {
  const { request } = context;
  const done = new Response(null, { status: 204, headers: { "Cache-Control": "no-store" } });
  const ua = request.headers.get("user-agent") || "";
  const url = new URL(request.url);
  const origin = request.headers.get("origin") || "";
  if (BOTS.test(ua) || (origin && new URL(origin).host !== url.host)) return done;

  let body = {};
  try { body = JSON.parse(await request.text()); } catch (e) { return done; }
  let path = String(body.p || "/").split("?")[0].split("#")[0].slice(0, 120);
  if (path.startsWith("/admin")) return done;
  let ref = "";
  try {
    const h = new URL(String(body.r || "")).host.toLowerCase().replace(/^www\./, "");
    if (h && h !== url.host) ref = h;
  } catch (e) {}

  const args = {
    p_path: path,
    p_ref: ref,
    p_country: (request.cf && request.cf.country) || "",
    p_device: /Mobi|Android|iPhone|iPad/i.test(ua) ? "mobile" : "desktop",
    p_client: (request.headers.get("cf-connecting-ip") || "") + "|" + ua,
  };
  context.waitUntil(fetch(SUPABASE_URL + "/rest/v1/rpc/log_visit", {
    method: "POST",
    headers: { apikey: SUPABASE_ANON_KEY, Authorization: "Bearer " + SUPABASE_ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify(args),
  }).catch(() => {}));
  return done;
}
