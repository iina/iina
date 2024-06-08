//
//  JavascriptAPIWebSocket.swift
//  iina
//
//  Created by Hechen Li on 8/8/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore
import Network

@objc protocol JavascriptAPIWebSocketControllerExportable: JSExport {
  func createServer(_ options: [String: Any])
  func startServer()
  func onStateUpdate(_ handler: JSValue)
  func onMessage(_ handler: JSValue)
  func onNewConnection(_ handler: JSValue)
  func onConnectionStateUpdate(_ handler: JSValue)
  func sendText( _ conn: String, _ string: String) -> JSValue
}

class JavascriptAPIWebSocketController: JavascriptAPI, JavascriptAPIWebSocketControllerExportable {
  var server: WebSocketServer?
  var stateHandler: JSManagedValue?
  var messageHandler: JSManagedValue?
  var newConnHandler: JSManagedValue?
  var connStateHandler: JSManagedValue?

  func createServer(_ options: [String : Any]) {
    if let previousServer = server {
      previousServer.listener.cancel()
      self.server = nil
    }
    guard let port = options["port"] as? UInt16 else {
      throwError(withMessage: "ws.createServer: port not specified")
      return
    }
    server = WebSocketServer(port: port, label: "\(pluginInstance.plugin.identifier).ws")
    // The server should be created without any issue at this step,
    // but errors may occur if we add TLS support in the future.
    if server == nil {
      throwError(withMessage: "ws.createServer: server cannot be created.")
      return
    }
    server?.delegate = self
    return
  }

  func startServer() {
    guard let server = server else {
      throwError(withMessage: "ws.startServer: server not created")
      return
    }
    guard server.listener.state == .setup else {
      throwError(withMessage: "ws.startServer: server is not in ready state")
      return
    }
    server.start()
  }

  func onMessage(_ handler: JSValue) {
    setHandler(handler, field: \Self.messageHandler)
  }

  func onStateUpdate(_ handler: JSValue) {
    setHandler(handler, field: \Self.stateHandler)
  }

  func onNewConnection(_ handler: JSValue) {
    setHandler(handler, field: \Self.newConnHandler)
  }

  func onConnectionStateUpdate(_ handler: JSValue) {
    setHandler(handler, field: \Self.connStateHandler)
  }

  private func setHandler(_ handler: JSValue, field: ReferenceWritableKeyPath<JavascriptAPIWebSocketController, JSManagedValue?>) {
    func removePreviousHandler() {
      self[keyPath: field] = nil
      JSContext.current()!.virtualMachine.removeManagedReference(self[keyPath: field], withOwner: self)
    }
    if handler.isNull || handler.isUndefined || self[keyPath: field] != nil {
      removePreviousHandler()
      return
    }
    guard handler.isObject else {
      throwError(withMessage: "ws.on: the handler is not an object")
      return
    }
    self[keyPath: field] = JSManagedValue(value: handler)
    JSContext.current()!.virtualMachine.addManagedReference(self[keyPath: field], withOwner: self)
  }

  func sendText(_ conn: String, _ string: String) -> JSValue {
    let data = string.data(using: .utf8)!

    return createPromise { [unowned self] resolve, reject in
      guard let server = self.server else {
        reject.call(withArguments: ["server does not exist"])
        return
      }
      guard let connEntry = server.connections[conn] else {
        // not throwing an error hereif there's no such connection ID.
        // because it's not the server's fault and we just want to "ignore the request"
        resolve.call(withArguments: ["no_connection"])
        return
      }
      do {
        try server.send(data: data, to: connEntry, callback: { error in
          if let error = error {
            reject.call(withArguments: [error.toDict()])
          } else {
            resolve.call(withArguments: ["success"])
          }
        })
      } catch (let error) {
        reject.call(withArguments: [error.localizedDescription])
      }
    }
  }
}


extension JavascriptAPIWebSocketController: WebSocketServerDelegate {
  func stateUpdated(_ state: NWListener.State) {
    guard let handler = stateHandler?.value else { return }

    switch state {
    case .setup:
      handler.call(withArguments: ["setup"])
    case .waiting(let nWError):
      handler.call(withArguments: ["waiting", nWError.toDict()])
    case .ready:
      handler.call(withArguments: ["ready"])
    case .failed(let nWError):
      handler.call(withArguments: ["failed", nWError.toDict()])
    case .cancelled:
      handler.call(withArguments: ["cancelled"])
    @unknown default:
      handler.call(withArguments: ["\(state)"])
    }
  }

  func newConnection(_ conn: NWConnection, connID: String) {
    guard let handler = newConnHandler?.value else { return }
    handler.call(withArguments: [
      connID,
      // may add more useful information in the future
      [
        "path": conn.currentPath?.remoteEndpoint?.debugDescription
      ] as [String: Any?]
    ])
  }

  func connection(_ conn: String, stateUpdated state: NWConnection.State) {
    guard let handler = connStateHandler?.value else { return }

    switch state {
    case .setup:
      handler.call(withArguments: [conn, "setup"])
    case .waiting(let nWError):
      handler.call(withArguments: [conn, "waiting", nWError.toDict()])
    case .preparing:
      handler.call(withArguments: [conn, "preparing"])
    case .ready:
      handler.call(withArguments: [conn, "ready"])
    case .failed(let nWError):
      handler.call(withArguments: [conn, "failed", nWError.toDict()])
    case .cancelled:
      handler.call(withArguments: [conn, "cancelled"])
    @unknown default:
      handler.call(withArguments: [conn, "\(state)"])
    }
  }

  func connection(_ conn: String, receivedData data: Data, context: NWConnection.ContentContext) {
    guard let handler = self.messageHandler?.value else { return }

    let wsMessage = WSMessage(data: data)
    handler.call(withArguments: [conn, wsMessage])
  }
}


@objc fileprivate protocol WSMessageExportable: JSExport {
  func text() -> String?
  func data() -> JSValue?
}


/// Represents a WebSocket message, passed to JavaScript environment. Do not decode the message right away
/// since we don't know whether the JavaScript code need text or binary data, and creating UInt8Array can be expensive
@objc fileprivate class WSMessage: NSObject, WSMessageExportable {
  let dataObject: Data

  init(data: Data) {
    self.dataObject = data
  }

  func text() -> String? {
    return String(data: dataObject, encoding: .utf8)
  }

  func data() -> JSValue? {
    return createUInt8Array(fromData: dataObject)
  }
}

fileprivate extension Error where Self : CustomDebugStringConvertible {
  func toDict() -> [String: Any] {
    return [
      "description": self.debugDescription,
      "message": self.localizedDescription,
    ]
  }
}
