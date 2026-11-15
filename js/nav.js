// Shows "My plugins" instead of "Sign in" when a Supabase session is stored.
(function () {
  try {
    for (var i = 0; i < localStorage.length; i++) {
      var k = localStorage.key(i);
      if (/^sb-.*-auth-token$/.test(k)) {
        var a = document.getElementById("acct-link");
        if (a) a.textContent = "My plugins";
        return;
      }
    }
  } catch (e) {}
})();
