import { updateBrowserAction, openInIINA } from "./common.js";

updateBrowserAction();

[["page", "url"], ["link", "linkUrl"], ["video", "srcUrl"], ["audio", "srcUrl"]].forEach(([item, linkType]) => {
    chrome.contextMenus.create({
        title: `Open this ${item} in IINA`,
        id: `open${item}iniina`,
        contexts: [item],
        onclick: (info, tab) => {
            openInIINA(tab.id, info[linkType]);
        },
    });
});
