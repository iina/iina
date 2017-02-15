var activeWindowQuery = { currentWindow: true, active: true }

chrome.browserAction.onClicked.addListener(function(tab) { 
  // get active window
  chrome.tabs.query(activeWindowQuery, function(tabs) {
    if (tabs.length == 0)
      return
    // TODO: filter url
    var url = "iina://weblink?url=" + encodeURIComponent(tabs[0].url)
    var code = "var link = document.createElement('a');" +
      "link.href='" + url + "';" +
      "document.body.appendChild(link);" +
      "link.click();";
    chrome.tabs.executeScript(tabs[0].id, { code: code })
  })
})
