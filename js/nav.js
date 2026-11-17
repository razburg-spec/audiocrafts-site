// Site navigation: account link label, mobile menu, scroll reveal.
(function () {
  // Show "My plugins" instead of "Sign in" when a Supabase session is stored.
  try {
    for (var i = 0; i < localStorage.length; i++) {
      var k = localStorage.key(i);
      if (/^sb-.*-auth-token$/.test(k)) {
        var a = document.getElementById("acct-link");
        if (a) a.textContent = "My plugins";
        break;
      }
    }
  } catch (e) {}

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
