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

    chrome.contextMenus.create({
        title: `Open this ${item} in fullscreen`,
        id: `open${item}infullscreen`,
        contexts: [item],
        onclick: (info, tab) => {
            openInIINA(tab.id, info[linkType], { mode: "fullScreen" });
        },
    });

    chrome.contextMenus.create({
        title: `Add this ${item} and enter picture-in-picture`,
        id: `open${item}inpip`,
        contexts: [item],
        onclick: (info, tab) => {
            openInIINA(tab.id, info[linkType], { mode: "pip" });
        },
    });

    chrome.contextMenus.create({
        title: `Open this ${item} in new IINA window`,
        id: `open${item}innewwindow`,
        contexts: [item],
        onclick: (info, tab) => {
            openInIINA(tab.id, info[linkType], { newWindow: true });
        },
    });

    chrome.contextMenus.create({
        title: `Add this ${item} to playlist`,
        id: `add${item}toiinaplaylist`,
        contexts: [item],
        onclick: (info, tab) => {
            openInIINA(tab.id, info[linkType], { mode: "enqueue" });
        },
    });
});
