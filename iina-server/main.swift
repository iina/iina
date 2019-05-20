//
//  main.swift
//  iina-server
//
//  Created by Collider LI on 19/2/2019.
//  Copyright © 2019 lhc. All rights reserved.
//

import Foundation
import Socket

fileprivate let Path = "/private/tmp/.webdavUDS.iina"

let controller = SimpleMPVController()
controller.start()
 
var renderSemaphore = DispatchSemaphore(value: 0)
var currentConnection: Socket?

let mainQueue = DispatchQueue(label: "com.colliderli.iina.server")
var ticket = 0

do {
  let socket = try Socket.create(family: .unix, type: .stream, proto: .unix)
  try socket.listen(on: Path)

  while true {
    let newConnection = try socket.acceptClientConnection()

    ticket += 1
    let myTicket = ticket
    print("get new connection \(myTicket)")

    currentConnection = newConnection
    if let path = try currentConnection?.readString() {
      mainQueue.async {
        print("handle new connection \(myTicket), currTicket=\(ticket)")
        guard ticket == myTicket else {
          print("not me")
          return
        }
        controller.filePath = path
        controller.startSocket()
        renderSemaphore.wait()
        print("released \(myTicket)")
      }
    }
  }

  socket.close()

} catch let error {
  print(error)
}
