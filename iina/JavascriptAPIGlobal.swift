//
//  JavascriptAPIGlobal.swift
//  iina
//
//  Created by Collider LI on 20/10/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol JavascriptAPIGlobalControllerExportable: JSExport {
  func createPlayerInstance(_ options: [String: Any]) -> Any
  func postMessage(_ target: JSValue, _ name: String, _ data: JSValue)
  func onMessage(_ name: String, _ callback: JSValue)
}

@objc protocol JavascriptAPIGlobalChildExportable: JSExport {
  func postMessage(_ name: String, _ data: JSValue)
  func onMessage(_ name: String, _ callback: JSValue)
}

class JavascriptAPIGlobalController: JavascriptAPI, JavascriptAPIGlobalControllerExportable {
  var instances: [Int: PlayerCore] = [:]
  var childAPIs: [Int: JavascriptAPIGlobalChild] = [:]
  lazy var messageHub = JavascriptMessageHub(reference: self)
  private var instanceCounter = 0

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    instances.values.forEach {
      $0.mainWindow.close()
      $0.terminateMPV()
    }
    instances.removeAll()
    childAPIs.removeAll()
  }

  func createPlayerInstance(_ options: [String: Any]) -> Any {
    instanceCounter += 1
    // create the `PlayerCore` manually since it's managed directly by the plugin
    let pc = PlayerCore()
    pc.label = "\(instanceCounter)-\(pluginInstance.plugin.identifier)"
    pc.isManagedByPlugin = true
    pc.startMPV()
    if (options["disableWindowAnimation"] as? Bool == true) {
      pc.disableWindowAnimation = true
    }
    if (options["disableUI"] as? Bool == true) {
      pc.disableUI = true
    }
    if (options["enablePlugins"] as? Bool == true) {
      pc.loadPlugins()
    } else {
      // load the current plugin only.
      // `reloadPlugin` will create a plugin instance if it's not loaded.
      pc.reloadPlugin(pluginInstance.plugin)
    }
    // accociate child plugin
    let childPluginInstance = pc.plugins.first { $0.plugin == pluginInstance.plugin }!
    let childAPI = childPluginInstance.apis["global"] as! JavascriptAPIGlobalChild
    childAPI.parentAPI = self
    instances[instanceCounter] = pc
    childAPIs[instanceCounter] = childAPI
    return instanceCounter
  }

  func postMessage(_ target: JSValue, _ name: String, _ data: JSValue) {
    if target.isNull {
      childAPIs.values.forEach {
        $0.messageHub.callListener(forEvent: name, withDataObject: data.toObject())
      }
    } else if target.isNumber {
      let id = target.toNumber()!.intValue
      childAPIs[id]?.messageHub.callListener(forEvent: name, withDataObject: data.toObject())
    }
  }

  func onMessage(_ name: String, _ callback: JSValue) {
    messageHub.addListener(forEvent: name, callback: callback)
  }
}


class JavascriptAPIGlobalChild: JavascriptAPI, JavascriptAPIGlobalChildExportable {
  var parentAPI: JavascriptAPIGlobalController!
  lazy var messageHub = JavascriptMessageHub(reference: self)

  func postMessage(_ name: String, _ data: JSValue) {
    parentAPI.messageHub.callListener(forEvent: name, withDataObject: data.toObject())
  }

  func onMessage(_ name: String, _ callback: JSValue) {
    messageHub.addListener(forEvent: name, callback: callback)
  }
}
