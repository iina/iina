//
//  WebSocketServer.swift
//  iina
//
//  Created by Hechen Li on 8/8/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation
import Network


protocol WebSocketServerDelegate {
  func stateUpdated(_ state: NWListener.State)
  func newConnection(_ conn: NWConnection, connID: String)
  func connection(_ conn: String, stateUpdated state: NWConnection.State)
  func connection(_ conn: String, receivedData data: Data, context: NWConnection.ContentContext)
}


class WebSocketServer {
  let label: String
  var delegate: WebSocketServerDelegate?

  var listener: NWListener
  var connections: [String: NWConnection] = [:]
  var timer: Timer?

  lazy var serverQueue = DispatchQueue(label: "IINAWebSocketServer.\(self.label)")
  let subsystem: Logger.Subsystem

  init?(port: UInt16, label: String, logger: Logger.Subsystem? = nil) {
    self.label = label
    self.subsystem = logger ?? Logger.makeSubsystem("ws-server")
    // TODO: Support TLS
    let parameters = NWParameters(tls: nil)
    parameters.allowLocalEndpointReuse = true
    parameters.includePeerToPeer = true

    let wsOptions = NWProtocolWebSocket.Options()
    wsOptions.autoReplyPing = true
    parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

    do {
      if let port = NWEndpoint.Port(rawValue: port) {
        listener = try NWListener(using: parameters, on: port)
      } else {
        Logger.log("Cannot start WebSocket server on port \(port)", level: .error, subsystem: subsystem)
        return nil
      }
    } catch {
      Logger.log(error.localizedDescription, level: .error, subsystem: subsystem)
      return nil
    }
  }

  func start() {
    listener.newConnectionHandler = handleNewConnection(_:)
    listener.stateUpdateHandler = handleStateUpdate(_:)
    // No error will be thrown here. If the port is in use, the server will fail immediately
    listener.start(queue: serverQueue)
  }

  func stop() {
    listener.cancel()
  }

  private func handleNewConnection(_ connection: NWConnection) {
    // Create a UUID to identify each connection
    let connID = UUID().uuidString
    Logger.log("New connection: \(connID)", level: .debug, subsystem: subsystem)
    Logger.log(connection.debugDescription, level: .debug, subsystem: subsystem)
    connections[connID] = connection
    delegate?.newConnection(connection, connID: connID)

    connection.stateUpdateHandler = { [unowned self] state in
      Logger.log("Connection \(state) (\(connID))", subsystem: subsystem)
      self.delegate?.connection(connID, stateUpdated: state)
      switch state {
      case .failed(_):
        connection.cancel()  // do we need to cancel here?
        fallthrough
      case .cancelled:
        connections[connID] = nil
      default:
        break
      }
    }

    connection.start(queue: serverQueue)

    func receive() {
       connection.receiveMessage { [unowned self] (data, context, isComplete, error) in
        if let data = data, let context = context {
          // handle ping frames
          if let metadata = context.protocolMetadata as? [NWProtocolWebSocket.Metadata],
             metadata[0].opcode == .ping {
            Logger.log("Ping (\(connID))", subsystem: subsystem)
            let pongContext = NWConnection.ContentContext(
              identifier: "pong",
              metadata: [NWProtocolWebSocket.Metadata(opcode: .pong)]
            )
            connection.send(content: data, contentContext: pongContext, completion: .idempotent)
          } else {
            // normal data
            Logger.log("Data (\(connID))", subsystem: subsystem)
            self.delegate?.connection(connID, receivedData: data, context: context)
          }
          receive()
        }
      }
    }

    receive()
  }

  private func handleStateUpdate(_ state: NWListener.State) {
    Logger.log("Server \(state)", subsystem: subsystem)
    delegate?.stateUpdated(state)
  }

  func send(data: Data, to connection: NWConnection, callback: ((NWError?) -> Void)?) throws {
    // do we need a separate send(text:to:) method to send text frames?
    let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
    let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
    connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed({ error in
      callback?(error)
    }))
  }
}

