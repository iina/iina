function handleContextMenu(event) {
  var target = event.target;
  while (target != null && target.nodeType == Node.ELEMENT_NODE && target.nodeName.toLowerCase() != "a") {
    target = target.parentNode;
  }
  safari.extension.setContextMenuEventUserInfo(event, { "url": target.href });
}

document.addEventListener("contextmenu", handleContextMenu, false);
