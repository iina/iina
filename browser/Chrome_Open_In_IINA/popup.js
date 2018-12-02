import { openInIINA } from "./common.js";

Array.prototype.forEach.call(document.getElementsByClassName("menu-item"), (item) => {
    const mode = item.id.split("-")[1];
    item.addEventListener("click", () => {
        chrome.tabs.query({ currentWindow: true, active: true }, (tabs) => {
            if (tabs.length === 0) { return; }
            const tab = tabs[0];
            if (tab.id === chrome.tabs.TAB_ID_NONE) { return; }
            console.log(mode)
            openInIINA(tab.id, tab.url, {
                mode,
                newWindow: mode === "newWindow",
            });
        });
    });
});
