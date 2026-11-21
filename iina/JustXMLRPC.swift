//
//  JustXMLRPC.swift
//  iina
//
//  Created by lhc on 11/3/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa
import Just

fileprivate let ISO8601FormatString = "yyyyMMdd'T'HH:mm:ss"


class JustXMLRPC {

  struct XMLRPCError: Error {
    var method: String
    var httpCode: Int
    var reason: String
    var readableDescription: String {
      return "\(method): [\(httpCode)] \(reason)"
    }
    var underlyingError: Error?
  }

  enum Result {
    case ok(Any)
    case failure
    case error(XMLRPCError)
  }

  /** (success, result) */
  typealias CallBack = (Result) -> Void

  private static let iso8601DateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = ISO8601FormatString
    return formatter
  }()

  var location: String

  init(_ loc: String) {
    self.location = loc
  }

  /**
   *  Call a XMLRPC method.
   */
  func call(_ method: String, _ parameters: [Any] = [], callback: @escaping CallBack) {
    let params = XMLElement(name: "params")
    for parameter in parameters {
      let param = XMLElement(name: "param")
      param.addChild(JustXMLRPC.toValueElement(parameter))
      params.addChild(param)
    }
    let methodName = XMLElement(name: "methodName", stringValue: method)
    let methodCall = XMLElement(name: "methodCall")
    methodCall.addChild(methodName)
    methodCall.addChild(params)
    let reqXML = XMLDocument(rootElement: methodCall)
    // Request
    Just.post(location, requestBody: reqXML.xmlData, asyncCompletionHandler: { response in
      guard response.ok else {
        callback(.error(XMLRPCError(method: method, httpCode: response.statusCode ?? 0,
                                   reason: response.reason, underlyingError: response.error)))
        return
      }
      // Don't load external entities, which can include local files.
      if let content = response.content,
         let responseDoc = try? XMLDocument(data: content, options: [.nodeLoadExternalEntitiesNever]),
         let rootElement = responseDoc.rootElement(), rootElement.name == "methodResponse" {
        if let _ = rootElement.child("fault") {
          callback(.failure)
        } else if let params = rootElement.child("params")?.findChildren("param"), params.count == 1,
                  let values = params[0].findChildren("value"), values.count == 1,
                  let value = JustXMLRPC.value(fromValueElement: values[0]) {
          callback(.ok(value))
        } else {
          // unexpected return value
          callback(.error(XMLRPCError(method: method, httpCode: response.statusCode ?? 0, reason: "Bad response")))
        }
      } else {
        callback(.error(XMLRPCError(method: method, httpCode: response.statusCode ?? 0, reason: "Bad response")))
      }
    })
  }

  private static func toValueElement(_ value: Any) -> XMLElement {
    let valueElement = XMLElement(name: "value")
    switch value {
    case is Bool:
      valueElement.addChild(XMLElement(name: "boolean", stringValue: (value as! Bool) ? "1" : "0"))
    case is Int, is Int8, is Int16, is UInt, is UInt8, is UInt16:
      valueElement.addChild(XMLElement(name: "int", stringValue: "\(value)"))
    case is Float, is Double:
      valueElement.addChild(XMLElement(name: "double", stringValue: "\(value)"))
    case is String:
      valueElement.addChild(XMLElement(name: "string", stringValue: (value as! String)))
    case is Date:
      let stringDate = iso8601DateFormatter.string(from: value as! Date)
      valueElement.addChild(XMLElement(name: "dateTime.iso8601", stringValue: stringDate))
    case is Data:
      let stringData = (value as! Data).base64EncodedString()
      valueElement.addChild(XMLElement(name: "base64", stringValue: stringData))
    case is [Any]:
      let arrayElement = XMLElement(name: "array")
      let dataElement = XMLElement(name: "data")
      for e in (value as! [Any]) {
        dataElement.addChild(JustXMLRPC.toValueElement(e))
      }
      arrayElement.addChild(dataElement)
      valueElement.addChild(arrayElement)
    case is [String: Any]:
      let structElement = XMLElement(name: "struct")
      for (k, v) in (value as! [String: Any]) {
        let entryElement = XMLElement(name: "member")
        entryElement.addChild(XMLElement(name: "name", stringValue: k))
        entryElement.addChild(JustXMLRPC.toValueElement(v))
        structElement.addChild(entryElement)
      }
      valueElement.addChild(structElement)
    default:
      Logger.log("XMLRPC: Value type not supported", level: .warning)
    }
    return valueElement
  }

  private static func value(fromValueElement element: XMLElement) -> Any? {
    let children = element.children?.compactMap { $0 as? XMLElement } ?? []
    guard !children.isEmpty else {
      // XML-RPC values without a type element are strings
      return element.stringValue ?? ""
    }
    guard children.count == 1 else { return nil }

    let valueElement = children[0]
    let s = valueElement.stringValue ?? ""
    switch valueElement.name {
    case "boolean":
      switch s {
      case "0": return false
      case "1": return true
      default: return nil
      }
    case "int", "i4":
      return Int(s)
    case "double":
      return Double(s)
    case "string":
      return s as Any
    case "dateTime.iso8601":
      return iso8601DateFormatter.date(from: s)
    case "base64":
      return Data(base64Encoded: s)
    case "array":
      guard let data = valueElement.child("data") else { return nil }
      var resultArray: [Any] = []
      for child in data.findChildren("value") ?? [] {
        guard let value = JustXMLRPC.value(fromValueElement: child) else { return nil }
        resultArray.append(value)
      }
      return resultArray
    case "struct":
      var resultDict: [String: Any] = [:]
      for child in valueElement.findChildren("member") ?? [] {
        guard let key = child.child("name")?.stringValue,
              let element = child.child("value"),
              let value = JustXMLRPC.value(fromValueElement: element) else { return nil }
        resultDict[key] = value
      }
      return resultDict
    default:
      Logger.log("XMLRPC: Unexpected value type: \(valueElement.name ?? "")", level: .error)
      return nil
    }
  }

}

extension XMLNode {
  func findChildren(_ name: String) -> [XMLElement]? {
    return self.children?.filter { $0.name == name } as? [XMLElement]
  }

  func child(_ name: String) -> XMLElement? {
    return self.findChildren(name)?.first
  }
}
