import { updateBrowserAction, openInIINA, getOptions } from "./common.js";

updateBrowserAction();

const dict = {
  page: "pageUrl",
  link: "linkUrl",
  video: "srcUrl",
  audio: "srcUrl",
};

Object.keys(dict).forEach((item) => {
  chrome.contextMenus.create({
    title: `Open this ${item} in IINA`,
    id: `openiniina_${item}`,
    contexts: [item],
  });
});

chrome.contextMenus.onClicked.addListener(function (info, tab) {
  if (info.menuItemId.startsWith("openiniina")) {
    const key = info.menuItemId.split("_")[1];
    const url = info[dict[key]];
    if (url) {
      openInIINA(tab.id, url);
    }
  }
});

chrome.action.onClicked.addListener(() => {
  // get active window
  chrome.tabs.query({ currentWindow: true, active: true }, (tabs) => {
    if (tabs.length === 0) {
      return;
    }
    // TODO: filter url
    const tab = tabs[0];
    if (tab.id === chrome.tabs.TAB_ID_NONE) {
      return;
    }
    getOptions((options) => {
      openInIINA(tab.id, tab.url, {
        mode: options.iconActionOption,
      });
    });
  });
});
