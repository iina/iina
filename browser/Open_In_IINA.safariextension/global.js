const command_menu = "open_in_iina_menu_cmd";
const command_btn = "open_in_iina_toolbar_btn_cmd";
const command_link_menu = "open_link_in_iina_menu_cmd";

var eventHandler = function(event) {
    var tab = safari.application.activeBrowserWindow.activeTab;
    var url = "iina://weblink?url=";

    if (event.command == command_menu || event.command == command_btn) {
        var active_url = tab.url;
        if (active_url) {
            url += encodeURIComponent(active_url);
            tab.url = url;
        } else {
            window.alert("Cannot get current URL!");
        }
    } else if (event.command === command_link_menu) {
        var link = event.userInfo;
        if (link) {
            url += encodeURIComponent(link);
            tab.url = url;
        } else {
            window.alert("Unable to find URL.");
        }
    }
};

function validateItem(event) {
    if (event.command === command_link_menu) {
        var linkFound = typeof(event.userInfo) === 'undefined';
        event.target.disabled = linkFound;
    }
}

safari.application.addEventListener("command", eventHandler, false);
safari.application.addEventListener("validate", validateItem, false);