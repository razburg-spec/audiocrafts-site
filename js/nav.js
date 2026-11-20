// Site navigation: account link label, mobile menu, scroll reveal.
(function () {
  // Show "My plugins" instead of "Sign in" when a Supabase session is stored.
  var session = null;
  try {
    for (var i = 0; i < localStorage.length; i++) {
      var k = localStorage.key(i);
      if (/^sb-.*-auth-token$/.test(k)) {
        var a = document.getElementById("acct-link");
        if (a) a.textContent = "My plugins";
        try { session = JSON.parse(localStorage.getItem(k)); } catch (e2) {}
        break;
      }
    }
  } catch (e) {}

  // "Admin" link, only for accounts the database says are admins (public.is_admin()).
  // The check runs on the server with the signed-in user's token; the dashboard's data
  // is protected separately, so this link only controls what is shown.
  (function () {
    var acct = document.getElementById("acct-link");
    if (!acct || !session || !session.access_token || !session.user) return;
    function addLink() {
      if (document.getElementById("admin-link")) return;
      var l = document.createElement("a");
      l.href = "/admin/"; l.id = "admin-link"; l.className = "admin"; l.textContent = "Admin";
      if (location.pathname.indexOf("/admin") === 0) l.setAttribute("aria-current", "page");
      acct.parentNode.insertBefore(l, acct);
    }
    var key = "rba-admin", uid = session.user.id, cached = null;
    try { cached = JSON.parse(sessionStorage.getItem(key) || "null"); } catch (e) {}
    if (cached && cached.uid === uid) { if (cached.admin) addLink(); return; }
    if (session.expires_at && session.expires_at * 1000 < Date.now()) return;
    fetch("https://cmolzvodpvktkjgrfrtt.supabase.co/rest/v1/rpc/is_admin", {
      method: "POST",
      headers: { apikey: "sb_publishable_2AvUWy3rpblb4qEOgNutVw_4Gfx197l", Authorization: "Bearer " + session.access_token, "Content-Type": "application/json" },
      body: "{}"
    }).then(function (r) { return r.ok ? r.json() : false; }).then(function (isAdmin) {
      try { sessionStorage.setItem(key, JSON.stringify({ uid: uid, admin: isAdmin === true })); } catch (e) {}
      if (isAdmin === true) addLink();
    }).catch(function () {});
  })();

  var burger = document.querySelector(".burger");
  var menu = document.querySelector(".menu");
  if (burger && menu) {
    burger.addEventListener("click", function () {
      var open = menu.classList.toggle("open");
      burger.setAttribute("aria-expanded", open ? "true" : "false");
    });
    menu.addEventListener("click", function (e) {
      if (e.target.tagName === "A") { menu.classList.remove("open"); burger.setAttribute("aria-expanded", "false"); }
    });
  }

  var items = document.querySelectorAll(".rv");
  if (!("IntersectionObserver" in window)) {
    for (var j = 0; j < items.length; j++) items[j].classList.add("in");
    return;
  }
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (en) {
      if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
    });
  }, { rootMargin: "0px 0px -8% 0px" });
  for (var n = 0; n < items.length; n++) io.observe(items[n]);
})();
