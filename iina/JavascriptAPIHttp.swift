//
//  JavascriptAPIHttp.swift
//  iina
//
//  Created by Collider LI on 12/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore
import Just

fileprivate typealias JustRequestFunc = (URLComponentsConvertible, [String : Any], [String : Any]) -> HTTPResult

@objc protocol JavascriptAPIHttpExportable: JSExport {
  func get(_ url: String, _ options: [String: Any]?) -> JSValue?
  func post(_ url: String, _ options: [String: Any]?) -> JSValue?
  func put(_ url: String, _ options: [String: Any]?) -> JSValue?
  func patch(_ url: String, _ options: [String: Any]?) -> JSValue?
  func delete(_ url: String, _ options: [String: Any]?) -> JSValue?
  func xmlrpc(_ location: String) -> JavascriptAPIXmlrpc?
}

class JavascriptAPIHttp: JavascriptAPI, JavascriptAPIHttpExportable {

  @objc func get(_ url: String, _ options: [String: Any]?) -> JSValue? {
    return request(.get, url: url, options: options)
  }

  @objc func post(_ url: String, _ options: [String: Any]?) -> JSValue? {
    return request(.post, url: url, options: options)
  }

  @objc func put(_ url: String, _ options: [String: Any]?) -> JSValue? {
    return request(.put, url: url, options: options)
  }

  @objc func patch(_ url: String, _ options: [String: Any]?) -> JSValue? {
    return request(.patch, url: url, options: options)
  }

  @objc func delete(_ url: String, _ options: [String: Any]?) -> JSValue? {
    return request(.delete, url: url, options: options)
  }

  @objc func xmlrpc(_ location: String) -> JavascriptAPIXmlrpc? {
    guard hostIsValid(location) else {
      return nil
    }
    return JavascriptAPIXmlrpc(context: context, pluginInstance: pluginInstance, location: location)
  }

  private func request(_ method: HTTPMethod, url: String, options: [String: Any]?) -> JSValue? {
    return whenPermitted(to: .networkRequest) {
      // check host
      guard hostIsValid(url) else {
        return JSValue(undefinedIn: context)
      }
      // request
      let params = options?["params"] as? [String: String]
      let headers = options?["headers"] as? [String: String]
      let data = options?["data"] as? [String: Any]
      return createPromise { resolve, reject in
        Just.request(method, url: url, params: params ?? [:], data: data ?? [:], headers: headers ?? [:]) { response in
          (response.ok ? resolve : reject).call(withArguments: [response.toDict()])
        }
      }
    }
  }

  private func hostIsValid(_ url: String) -> Bool {
    guard let host = NSURLComponents(string: url.addingPercentEncoding(withAllowedCharacters: .urlAllowed) ?? url)?.host else {
      throwError(withMessage: "URL \(url) is invalid.")
      return false
    }
    guard pluginInstance.plugin.domainList.contains(where: { domain -> Bool in
      if domain == "*" {
        return true
      } else if domain.hasPrefix("*.") {
        return host.hasSuffix(domain.dropFirst())
      } else {
        return domain == host
      }
    }) else {
      throwError(withMessage: "URL \(url) is not whitelisted.")
      return false
    }
    return true
  }

  private func createPromise(_ block: @escaping @convention(block) (JSValue, JSValue) -> Void) -> JSValue {
    return context.objectForKeyedSubscript("Promise")!.construct(withArguments: [JSValue(object: block, in: context)])
  }
}

@objc protocol JavascriptAPIXmlrpcExportable: JSExport {
  func call(_ method: String, _ args: [Any]) -> JSValue?
}

class JavascriptAPIXmlrpc: JavascriptAPI, JavascriptAPIXmlrpcExportable {
  private let xmlrpc: JustXMLRPC

  init(context: JSContext, pluginInstance: JavascriptPluginInstance, location: String) {
    self.xmlrpc = JustXMLRPC(location)
    super.init(context: context, pluginInstance: pluginInstance)
  }

  @objc func call(_ method: String, _ args: [Any]) -> JSValue? {
    return createPromise { resolve, reject in
      self.xmlrpc.call(method, args) { response in
        switch response {
        case .ok(let returnValue):
          resolve.call(withArguments: [returnValue])
        case .failure:
          reject.call(withArguments: [])
        case .error(let err):
          reject.call(withArguments: [[
            "httpCode": err.httpCode,
            "reason": err.reason,
            "description": err.readableDescription,
          ]])
        }
      }
    }
  }

  private func createPromise(_ block: @escaping @convention(block) (JSValue, JSValue) -> Void) -> JSValue {
    return context.objectForKeyedSubscript("Promise")!.construct(withArguments: [JSValue(object: block, in: context)])
  }
}

fileprivate extension HTTPResult {
  func toDict() -> [String: Any?] {
    return [
      "statusCode": statusCode,
      "reason": reason,
      "data": json,
      "text": text
    ]
  }
}
