//
//  WebSocket.swift
//  iina
//
//  Created by Collider LI on 18/1/2019.
//  Copyright © 2019 lhc. All rights reserved.
//

import Foundation
import Swifter

class LocalHostSocket {
  enum State {
    case unready
    case initialized
    case running
  }

  var controller: SimpleMPVController!

  var server = HttpServer()
  var session: WebSocketSession?

  var state = State.unready

  var buffer: [UInt8] = []
  var dataBuffer: Data? {
    didSet {
      if state == .initialized {
        session?.writeText("ready")
        state = .running
      }
    }
  }

  func run() {
    server["/"] = websocket(text: { session, text in
      let s = text.split(separator: ":")
      guard let command = s.first else {
        fatalError("Unknown command: \(text)")
      }
      switch command {
      case "size":
        guard s.count == 2 else {
          fatalError("Size \(text) is not valid")
        }
        let args = s[1].split(separator: ",")
        guard let width = Int(args[0]), let height = Int(args[1]) else {
          fatalError("size \(text) is not valid")
        }
        self.controller.prepareContext(size: .init(width: width, height: height))
        self.controller.mpvInitRendering()
        self.controller.loadFile()
        self.state = .initialized
      case "draw":
        if text == "draw", let db = self.dataBuffer {
          session.writeFrame(ArraySlice(db), .binary)
        }
      default: break
      }
    }, binary: { session, binary in
      // do nothing
    }, connected: { session in
      self.session = session
      print("Websocket connected")
    }, disconnected: { session in
      print("Websocket disconnected")
      self.controller.cleanup()
    })
    try! server.start(23339)
  }

  func stop() {
    server.stop()
  }
}

