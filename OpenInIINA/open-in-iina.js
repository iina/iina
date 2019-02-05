function handleContextMenu(event) {
  var target = event.target;
  while (target != null && target.nodeType == Node.ELEMENT_NODE && target.nodeName.toLowerCase() != "a") {
    target = target.parentNode;
  }
  safari.extension.setContextMenuEventUserInfo(event, { "url": target.href });
}

function handleClick(event) {
  const url = event.target.src;
  if(url !== "") {
    if (url !== undefined && event.target.nodeName === "VIDEO") {
      extension = url.split('.').pop().toLowerCase();
      if (extension.substring(0,4) === "webm") {
        safari.extension.dispatchMessage("OpenWebmInIINA", { url: url });
      }
    }
  } else {
    if (event.target.nodeName === "VIDEO"){
      let sourceCount = 0;
      let url;
      for (i = 0; i < event.target.childNodes.length; i++) {
        if (event.target.childNodes[i].nodeName === "SOURCE") {
          sourceCount += 1;
          extension = event.target.childNodes[i].src.split('.').pop().toLowerCase();
          if (extension.substring(0,4) === "webm") {
            url = event.target.childNodes[i].src;
          }
        }
      }
      if (url !== undefined && sourceCount === 1) {
        safari.extension.dispatchMessage("OpenWebmInIINA", { url: url });
      }
    }
  }
}

document.addEventListener("contextmenu", handleContextMenu, false);
document.addEventListener("click", handleClick, false);
