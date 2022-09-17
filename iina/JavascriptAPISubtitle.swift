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
  func item(_ data: JSValue, _ desc: JSValue?) -> JavascriptPluginSubtitleItem
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

  func item(_ data: JSValue, _ desc: JSValue?) -> JavascriptPluginSubtitleItem {
    return JavascriptPluginSubtitleItem(data: data, desc: desc, withOwner: self)
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
  function createDownloadCallback(sub) {
    return (complete, fail) => {
      provider.download(sub).then(
        (urls) => {
          if (!Array.isArray(urls)) {
            fail(`provider.download should return an array of strings.`);
            return;
          }
          complete(urls);
        },
        (err) => {
          fail(err.toString());
        }
      );
    };
  }
  provider.search().then(
    (subs) => {
      if (!Array.isArray(subs)) {
        fail(`provider.search should return an array of subtitle items.`);
        return;
      }
      const hasDescFunction = typeof provider.description === "function";
      for (const sub of subs) {
        if (hasDescFunction && !sub.desc) sub.desc = provider.description(sub);
        sub.__setDownlaodCallback(createDownloadCallback(sub));
      }
      complete(subs);
    },
    (err) => {
      fail(err.toString());
    }
  );
};

iina.subtitle.__providers = {};

iina.subtitle.registerProvider = (id, provider) => {
  if (typeof id !== "string") throw new Error("A subtitle provider should have an id.");
  iina.subtitle.__providers[id] = provider;
};
"""
