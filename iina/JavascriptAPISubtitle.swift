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
}

class JavascriptAPISubtitle: JavascriptAPI, JavascriptAPISubtitleExportable {
  override func extraSetup() {
    context.evaluateScript("""
    iina.subtitle.__providers = {};
    iina.subtitle.registerProvider = (id, provider) => {
      if (typeof id !== "string") throw new Error("A subtitle provider should have an id.");
      iina.subtitle.__providers[id] = provider;
    }
    """)
  }

  func invokeProvider(id: String, callback: () -> Void) {
    guard let provider = context.evaluateScript("iina.subtitle.__providers['\(id)']"),
      provider.isObject else {
        throwError(withMessage: "")
        return
    }
    
  }
}
