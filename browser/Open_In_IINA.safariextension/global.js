const command_menu = "open_in_iina_menu_cmd"
const command_btn = "open_in_iina_toolbar_btn_cmd" 

var eventHandler = function(event) {
  if (event.command == command_menu || event.command == command_btn) {
    var tab = safari.application.activeBrowserWindow.activeTab
    var active_url = tab.url
    if (active_url) {
      var url = "iina://weblink?url=" + encodeURIComponent(active_url)
      tab.url = url
    } else {
      window.alert("Cannot get current URL!")
    }
  }
}

safari.application.addEventListener("command", eventHandler, false)