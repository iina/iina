//
//  WebSocketServer.swift
//  iina
//
//  Created by Hechen Li on 8/8/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation
import Network


protocol WebSocketServerDelegate: AnyObject {
  func stateUpdated(_ state: NWListener.State)
  func newConnection(_ conn: NWConnection, connID: String)
  func connection(_ conn: String, stateUpdated state: NWConnection.State)
  func connection(_ conn: String, receivedData data: Data, context: NWConnection.ContentContext)
}


class WebSocketServer {
  let label: String
  weak var delegate: WebSocketServerDelegate?

  var listener: NWListener
  var connections: [String: NWConnection] = [:]
  var timer: Timer?
  private var stopped = false

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
    listener.newConnectionHandler = { [weak self] connection in
      guard let self else { connection.cancel(); return }
      self.handleNewConnection(connection)
    }
    listener.stateUpdateHandler = { [weak self] state in self?.handleStateUpdate(state) }
    // No error will be thrown here. If the port is in use, the server will fail immediately
    listener.start(queue: serverQueue)
  }

  func stop() {
    serverQueue.async { [self] in
      stopped = true
      delegate = nil
      listener.newConnectionHandler = nil
      listener.stateUpdateHandler = nil
      listener.cancel()
      connections.values.forEach {
        $0.stateUpdateHandler = nil
        $0.cancel()
      }
      connections.removeAll()
    }
  }

  private func handleNewConnection(_ connection: NWConnection) {
    guard !stopped else { connection.cancel(); return }
    // Create a UUID to identify each connection
    let connID = UUID().uuidString
    Logger.log("New connection: \(connID)", level: .debug, subsystem: subsystem)
    Logger.log(connection.debugDescription, level: .debug, subsystem: subsystem)
    connections[connID] = connection
    delegate?.newConnection(connection, connID: connID)

    connection.stateUpdateHandler = { [weak self, weak connection] state in
      guard let self, let connection else { return }
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

    receive(connection, connID: connID)
  }

  private func receive(_ connection: NWConnection, connID: String) {
    connection.receiveMessage { [weak self, weak connection] data, context, _, error in
      guard let self, let connection, self.connections[connID] != nil else { return }
      if let data, let context {
        if let metadata = context.protocolMetadata as? [NWProtocolWebSocket.Metadata],
           metadata.first?.opcode == .ping {
          let pong = NWConnection.ContentContext(identifier: "pong",
            metadata: [NWProtocolWebSocket.Metadata(opcode: .pong)])
          connection.send(content: data, contentContext: pong, completion: .idempotent)
        } else {
          self.delegate?.connection(connID, receivedData: data, context: context)
        }
      }
      if error == nil { self.receive(connection, connID: connID) }
    }
  }

  private func handleStateUpdate(_ state: NWListener.State) {
    Logger.log("Server \(state)", subsystem: subsystem)
    delegate?.stateUpdated(state)
  }

  func send(data: Data, to identifier: String, callback: @escaping (NWError?, Bool) -> Void) {
    serverQueue.async { [self] in
      guard !stopped, let connection = connections[identifier] else {
        callback(nil, false)
        return
      }
      let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
      let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
      connection.send(content: data, contentContext: context, isComplete: true,
                      completion: .contentProcessed { callback($0, true) })
    }
  }
}
