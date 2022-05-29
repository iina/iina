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
      if response.ok, let content = response.content, let responseDoc = try? XMLDocument(data: content) {
        let rootElement = responseDoc.rootElement()
        if let _ = rootElement?.child("fault") {
          callback(.failure)
        } else if let params = rootElement?.child("params")?.child("param")?.children,
          params.count == 1 {
          callback(.ok(JustXMLRPC.value(fromValueElement: params[0] as! XMLElement)))
        } else {
          // unexpected return value
          callback(.error(XMLRPCError(method: method, httpCode: response.statusCode ?? 0, reason: "Bad response")))
        }
      } else {
        // http error
        callback(.error(XMLRPCError(method: method, httpCode: response.statusCode ?? 0, reason: response.reason, underlyingError: response.error)))
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

  private static func value(fromValueElement element: XMLElement) -> Any {
    let valueElement = element.child(at: 0)! as! XMLElement
    let s = valueElement.stringValue ?? ""
    switch valueElement.name {
    case "boolean":
      return Bool(s) as Any
    case "int", "i4":
      return Int(s) as Any
    case "double":
      return Double(s) as Any
    case "string":
      return s as Any
    case "dateTime.iso8601":
      return iso8601DateFormatter.date(from: s)!
    case "base64":
      return Data(base64Encoded: s) ?? Data()
    case "array":
      var resultArray: [Any] = []
      for child in valueElement.child("data")?.findChildren("value") ?? [] {
        resultArray.append(JustXMLRPC.value(fromValueElement: child))
      }
      return resultArray
    case "struct":
      var resultDict: [String: Any] = [:]
      for child in valueElement.findChildren("member") ?? [] {
        let key = child.child("name")!.stringValue!
        let value = JustXMLRPC.value(fromValueElement: child.child("value")!)
        resultDict[key] = value
      }
      return resultDict
    default:
      Logger.log("XMLRPC: Unexpected value type: \(valueElement.name ?? "")", level: .error)
      return 0
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
