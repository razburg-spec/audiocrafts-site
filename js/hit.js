// Cookieless visit counter: one small request per page view, no cookies or storage.
(function () {
  try {
    if (navigator.webdriver || location.pathname.indexOf("/admin") === 0) return;
    var d = JSON.stringify({ p: location.pathname, r: document.referrer || "" });
    if (!(navigator.sendBeacon && navigator.sendBeacon("/api/hit", new Blob([d], { type: "text/plain" })))) {
      fetch("/api/hit", { method: "POST", body: d, keepalive: true });
    }
  } catch (e) {}
})();
