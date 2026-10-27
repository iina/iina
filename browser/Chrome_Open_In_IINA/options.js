import { restoreOptions, saveOptions, updateBrowserAction } from "./common.js";

document.addEventListener("DOMContentLoaded", restoreOptions);

Array.prototype.forEach.call(document.getElementsByTagName("input"), (el) => {
    el.addEventListener("change", () => {
        saveOptions();
        updateBrowserAction();
    });
});
