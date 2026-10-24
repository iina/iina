//
//  JavascriptAPIAppearance.swift
//  iina
//

import Cocoa
import JavaScriptCore

@objc protocol JavascriptAPIAppearanceExportable: JSExport {
  func getTheme() -> [String: Any]
  func onChange(_ callback: JSValue) -> String?
  func offChange(_ id: String)
}

/// Read-only, permission-free tokens for normal and global plugin contexts.
class JavascriptAPIAppearance: JavascriptAPI, JavascriptAPIAppearanceExportable {
  private let listenersLock = NSLock()
  private var listeners: [String: JSManagedValue] = [:]
  private var observation: PluginAppearanceObservation?
  private var disposed = false

  deinit { dispose() }

  func getTheme() -> [String: Any] {
    PluginAppearance.snapshot()
  }

  func onChange(_ callback: JSValue) -> String? {
    guard callback.isObject,
          let object = JSValueToObject(callback.context.jsGlobalContextRef, callback.jsValueRef, nil),
          JSObjectIsFunction(callback.context.jsGlobalContextRef, object) else {
      throwError(withMessage: "appearance.onChange requires a function")
      return nil
    }
    let id = UUID().uuidString
    let managed = JSManagedValue(value: callback)!
    let machine = callback.context.virtualMachine!
    machine.addManagedReference(managed, withOwner: self)
    listenersLock.lock()
    guard !disposed else {
      listenersLock.unlock()
      machine.removeManagedReference(managed, withOwner: self)
      return nil
    }
    listeners[id] = managed
    if observation == nil {
      observation = PluginAppearanceObservation { [weak self] snapshot in
        self?.deliver(snapshot)
      }
    }
    listenersLock.unlock()
    return id
  }

  func offChange(_ id: String) {
    listenersLock.lock()
    let managed = listeners.removeValue(forKey: id)
    let previousObservation = listeners.isEmpty ? observation : nil
    if listeners.isEmpty { observation = nil }
    listenersLock.unlock()
    previousObservation?.invalidate()
    if let managed { context?.virtualMachine.removeManagedReference(managed, withOwner: self) }
  }

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    dispose()
  }

  private func dispose() {
    listenersLock.lock()
    disposed = true
    let previousObservation = observation
    observation = nil
    let previous = Array(listeners.values)
    listeners.removeAll()
    listenersLock.unlock()
    previousObservation?.invalidate()
    if let machine = context?.virtualMachine {
      previous.forEach { machine.removeManagedReference($0, withOwner: self) }
    }
  }

  private func deliver(_ snapshot: [String: Any]) {
    listenersLock.lock()
    let ids = Array(listeners.keys)
    listenersLock.unlock()
    for id in ids {
      listenersLock.lock()
      let managed = disposed ? nil : listeners[id]
      listenersLock.unlock()
      managed?.value?.call(withArguments: [snapshot])
    }
  }
}
