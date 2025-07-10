//
//  JavascriptPluginInputListener.swift
//  iina
//
//  Created by Hechen Li on 6/7/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation
import JavaScriptCore

class PluginInputManager: NSObject {
  struct Input {
    static let mouse = "*mouse"
    static let rightMouse = "*rightMouse"
    static let otherMouse = "*otherMouse"
  }
  
  enum Event: Int {
    case keyDown = 0
    case keyUp
    case mouseDown
    case mouseUp
    case mouseDrag
  }
  
  struct Priority: RawRepresentable, Comparable {
    typealias RawValue = Int
    var rawValue: RawValue
    
    init(rawValue: Int) {
      self.rawValue = rawValue
    }
    
    static let low = Priority(rawValue: 100)
    static let high = Priority(rawValue: 200)
    
    static func < (lhs: PluginInputManager.Priority, rhs: PluginInputManager.Priority) -> Bool {
      return lhs.rawValue < rhs.rawValue
    }
  }
  
  struct Listener {
    let callback: JSManagedValue?
    let priority: Priority
    
    func call(withArgs args: [Any]) -> JSValue? {
      return callback?.value.call(withArguments: args)
    }
  }
  
  // { input: { event: listener } }
  var listeners: [String: [Event: Listener]] = [:]
  
  func listener(forInput input: String, event: Event) -> Listener? {
    return listeners[input]?[event]
  }
  
  func addListener(forInput input: String, event: Event, callback: JSValue?, priority: Int, owner: Any) {
    if listeners[input] == nil {
      listeners[input] = [:]
    }
    if let previousCallback = listeners[input]![event] {
      JSContext.current()!.virtualMachine.removeManagedReference(previousCallback, withOwner: owner)
    }
    if let callback = callback, callback.isObject {
      let managed = JSManagedValue(value: callback)!
      listeners[input]![event] = Listener(callback: managed,
                                          priority: Priority(rawValue: priority))
      JSContext.current()!.virtualMachine.addManagedReference(managed, withOwner: owner)
    }
  }
  
  func callListener(forInput input: String, event: Event, withArgs args: [Any]) {
    listeners[input]?[event]?.callback?.value.call(withArguments: args)
  }
  
  /// Handle an input event including calling user-installed listeners.
  /// Listenrs with priority >= high will be called before the `handler`.
  /// - Parameters:
  ///   - input: the input name (keycode / mouse button)
  ///   - event: the event name (keydown etc)
  ///   - player: the PlayerCore instance
  ///   - arguments: arguments to be passed to user-installed listeners
  ///   - handler: the normal handler for this event in IINA
  ///   - defaultHandler: the fallback handler for this event if it's not handled by the normal handler
  static func handle(input: String, event: PluginInputManager.Event, player: PlayerCore, arguments: [Any], handler: (() -> Bool)? = nil, defaultHandler: (() -> Void)? = nil) {
    let listeners = player.plugins.compactMap {
      $0.input.listener(forInput: input, event: event)
    }.sorted(by: { $0.priority > $1.priority })
    
    // call listeners with high priority
    for listener in listeners.filter({ $0.priority >= .high }) {
      let stopPropagation = listener.call(withArgs: arguments)
      if stopPropagation?.toBool() ?? false {
        return
      }
    }
    
    // call the normal handler
    let eventHandled = handler?() ?? false
    
    // call listeners with low priority
    for listener in listeners.filter({ $0.priority < .high }) {
      let stopPropagation = listener.call(withArgs: arguments)
      if stopPropagation?.toBool() ?? false {
        return
      }
    }
    
    if !eventHandled {
      defaultHandler?()
    }
  }
  
}
