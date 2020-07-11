//
//  JavascriptAPISubtitle.swift
//  iina
//
//  Created by Collider LI on 16/3/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol JavascriptAPISubtitleExportable: JSExport {
  func item(_ data: JSValue) -> JavascriptPluginSubtitleItem
}

class JavascriptAPISubtitle: JavascriptAPI, JavascriptAPISubtitleExportable {
  override func extraSetup() {
    context.evaluateScript(extraSetupScript)
  }

  func invokeProvider(id: String,
                      completed: @convention(block) @escaping ([JavascriptPluginSubtitleItem]) -> Void,
                      failed: @convention(block) @escaping (String) -> Void) {
    let searchFunc = context.evaluateScript("iina.subtitle.__invokeSearch")!
    let c = JSValue(object: completed, in: context)!
    let f = JSValue(object: failed, in: context)!
    searchFunc.call(withArguments: [id, c, f])
  }

  func item(_ data: JSValue) -> JavascriptPluginSubtitleItem {
    return JavascriptPluginSubtitleItem(data: data)
  }
}

fileprivate let extraSetupScript = """
iina.subtitle.__invokeSearch = (id, complete, fail) => {
  const provider = iina.subtitle.__providers[id];
  if (typeof provider !== "object") {
    fail(`The provider with id "${id}" is not registered.`);
    return;
  }
  function checkAsync(name) {
    const func = provider[name];
    if (func && func.constructor.name === "AsyncFunction") return true;
    fail(`provider.${name} doesn't exist or is not an async function.`);
    return false;
  }
  for (name of ["search", "download"]) {
    if (!checkAsync(name)) return;
  }
  provider.search().then((subs) => {
    const valid = Array.isArray(subs) && subs.every(s => s.__iinsSubItem);
    if (!valid) {
      fail(`provider.search should return an array of subtitle items.`);
      return;
    }
    complete(subs);
  }, (err) => {
    fail(err.toString());
  });
};

iina.subtitle.__providers = {};

iina.subtitle.registerProvider = (id, provider) => {
  if (typeof id !== "string")
    throw new Error("A subtitle provider should have an id.");
  iina.subtitle.__providers[id] = provider;
};
"""
