var lifecycleTicks = 0;
var lifecycleTimer = setInterval(function () {
  lifecycleTicks += 1;
  iina.preferences.get("probe");
}, 25);
