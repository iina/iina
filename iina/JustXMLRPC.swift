//
//  JustXMLRPC.swift
//  iina
//
//  Created by lhc on 11/3/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa
import Just
import AEXML

fileprivate let ISO8601FormatString = "yyyyMMdd'T'HH:mm:ss"


class JustXMLRPC {

  struct XMLRPCError: Error {
    var method: String
    var httpCode: Int
    var reason: String
    var readableDescription: String {
      return "\(method): [\(httpCode)] \(reason)"
    }
  }

  enum Result {
    case ok(Any)
    case failure(Any)
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
    // Construct request XML
    let reqXML = AEXMLDocument()
    //  - method call
    let eMethodCall = reqXML.addChild(name: "methodCall")
    //  - method name
    eMethodCall.addChild(name: "methodName", value: method)
    //  - params
    let eParams = eMethodCall.addChild(name: "params")
    for param in parameters {
      eParams.addChild(name: "param").addChild(JustXMLRPC.toValueNode(param))
    }
    // Request
    Just.post(location, requestBody: reqXML.xml.data(using: .utf8)) { response in
      if response.ok, let content = response.content, let responseDoc = try? AEXMLDocument(xml: content) {
        let eParam = responseDoc.root["params"]["param"]
        let eFault = responseDoc.root["fault"]
        if eParam.count == 1 {
          // if success
          callback(.ok(JustXMLRPC.value(fromValueNode: eParam["value"])))
        } else if eFault.count == 1 {
          // if fault
          callback(.failure(JustXMLRPC.value(fromValueNode: eParam["value"])))
        } else {
          // unexpected return value
          callback(.error(XMLRPCError(method: method, httpCode: response.statusCode ?? 0, reason: "Bad response")))
        }
      } else {
        // http error
        callback(.error(XMLRPCError(method: method, httpCode: response.statusCode ?? 0, reason: response.reason)))
      }
    }
  }

  private static func toValueNode(_ value: Any) -> AEXMLElement {
    let eValue = AEXMLElement(name: "value")
    switch value {
    case is Bool:
      let vBool = value as! Bool
      eValue.addChild(name: "boolean", value: vBool ? "1" : "0")
    case is Int, is Int8, is Int16, is UInt, is UInt8, is UInt16:
      eValue.addChild(name: "int", value: "\(value)")
    case is Float, is Double:
      eValue.addChild(name: "double", value: "\(value)")
    case is String:
      let vString = value as! String
      eValue.addChild(name: "string", value: vString)
    case is Date:
      let vDate = value as! Date
      eValue.addChild(name: "dateTime.iso8601", value: iso8601DateFormatter.string(from: vDate))
    case is Data:
      let vData = value as! Data
      eValue.addChild(name: "base64", value: vData.base64EncodedString())
    case is [Any]:
      let vArray = value as! [Any]
      let eArrayData = eValue.addChild(name: "array").addChild(name: "data")
      for e in vArray {
        eArrayData.addChild(JustXMLRPC.toValueNode(e))
      }
    case is [String: Any]:
      let vDic = value as! [String: Any]
      let eStruct = eValue.addChild(name: "struct")
      for (k, v) in vDic {
        let eMember = eStruct.addChild(name: "member")
        eMember.addChild(name: "name", value: k)
        eMember.addChild(JustXMLRPC.toValueNode(v))
      }
    default:
      Utility.log("XMLRPC: Value type not supported")
    }
    return eValue
  }

  private static func value(fromValueNode node: AEXMLElement) -> Any {
    let eNode = node.children.first!
    switch eNode.name {
    case "boolean":
      return eNode.bool as Any
    case "int", "i4":
      return eNode.int as Any
    case "double":
      return eNode.double as Any
    case "string":
      return eNode.value ?? ""
    case "dateTime.iso8601":
      return iso8601DateFormatter.date(from: eNode.value!)!
    case "base64":
      return Data(base64Encoded: eNode.value!) ?? Data()
    case "array":
      var resultArray: [Any] = []
      for n in eNode["data"]["value"].all ?? [] {
        resultArray.append(JustXMLRPC.value(fromValueNode: n))
      }
      return resultArray
    case "struct":
      var resultDict: [String: Any] = [:]
      for m in eNode["member"].all ?? [] {
        let key = m["name"].value!
        let value = JustXMLRPC.value(fromValueNode: m["value"])
        resultDict[key] = value
      }
      return resultDict
    default:
      Utility.log("XMLRPC: Unexpected value type: \(eNode.name)")
      return 0
    }
  }

}
