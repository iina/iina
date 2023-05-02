class Option {
    constructor(name, type, defaultValue) {
        this.name = name;
        this.type = type;
        this.defaultValue = defaultValue;
    }

    setValue(value) {
        switch (this.type) {
            case "radio":
                Array.prototype.forEach.call(document.getElementsByName(this.name), (el) => {
                    el.checked = el.value === value;
                });
                break;
            case "checkbox":
                break;
        }
    }

    getValue() {
        switch (this.type) {
            case "radio":
                return document.querySelector(`input[name="${this.name}"]:checked`).value;
            case "checkbox":
                break;
        }
    }
}

const options = [
    new Option("iconAction", "radio", "clickOnly"),
    new Option("iconActionOption", "radio", "direct"),
];

export function getOptions(callback) {
    const getDict = {};
    options.forEach((item) => {
        getDict[item.name] = item.defaultValue;
    })
    chrome.storage.sync.get(getDict, callback);
}

export function saveOptions() {
    const saveDict = {};
    options.forEach((item) => {
        saveDict[item.name] = item.getValue();
    })
    chrome.storage.sync.set(saveDict);
}

export function restoreOptions() {
    getOptions((items) => {
        options.forEach((option) => {
            option.setValue(items[option.name]);
        });
    });
}

export function openInIINA(tabId, url, options = {}) {
    const baseURL = `iina://open?`;
    const params = [`url=${encodeURIComponent(url).replace(/'/g, '%27')}`];
    switch (options.mode) {
        case "fullScreen":
            params.push("full_screen=1"); break;
        case "pip":
            params.push("pip=1"); break;
        case "enqueue":
            params.push("enqueue=1"); break;
    }
    if (options.newWindow) {
        params.push("new_window=1");
    }

  chrome.scripting.executeScript({
    args: [baseURL, params],
    target: { tabId: tabId },
    func: openIINA,
  });
}

const openIINA = (baseURL, params) => {
  var link = document.createElement("a");
  link.href = `${baseURL}${params.join("&")}`;
  document.body.appendChild(link);
  link.click();
};

export function updateBrowserAction() {
  getOptions((options) => {
    if (options.iconAction === "clickOnly") {
      chrome.action.setPopup({ popup: "" });
    } else {
      chrome.action.setPopup({ popup: "popup.html" });
    }
  });
}
