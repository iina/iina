//
//  JavascriptAPIThumbnails.swift
//  iina
//
//  Public, read-only JavaScript access to IINA-owned timeline thumbnails.
//

import Foundation
import JavaScriptCore

@objc protocol JavascriptAPIThumbnailsExportable: JSExport {
  func subscribe(_ callback: JSValue) -> String?
  func unsubscribe(_ id: String)
}

private final class JavascriptTimelineThumbnailSubscription {
  let id: String
  weak var owner: JavascriptAPIThumbnails?
  private let callback: JSManagedValue
  private let virtualMachine: JSVirtualMachine
  private let pendingLock = NSLock()
  private var pending: TimelineThumbnailUpdate?
  private var deliveryScheduled = false
  private var active = true

  init(id: String, callback: JSValue, owner: JavascriptAPIThumbnails, virtualMachine: JSVirtualMachine) {
    self.id = id
    self.owner = owner
    self.callback = JSManagedValue(value: callback)
    self.virtualMachine = virtualMachine
    self.virtualMachine.addManagedReference(self.callback, withOwner: self)
  }

  deinit {
    virtualMachine.removeManagedReference(callback, withOwner: self)
  }

  func enqueue(_ update: TimelineThumbnailUpdate) {
    pendingLock.lock()
    guard active else {
      pendingLock.unlock()
      return
    }
    pending = update
    let shouldSchedule = !deliveryScheduled
    deliveryScheduled = true
    pendingLock.unlock()

    guard shouldSchedule else { return }
    DispatchQueue.main.async { [weak self] in
      self?.deliverPending()
    }
  }

  func cancel() {
    pendingLock.lock()
    active = false
    pending = nil
    deliveryScheduled = false
    pendingLock.unlock()
  }

  private func deliverPending() {
    pendingLock.lock()
    guard active else {
      pending = nil
      deliveryScheduled = false
      pendingLock.unlock()
      return
    }
    let update = pending
    pending = nil
    deliveryScheduled = false
    pendingLock.unlock()

    guard let update, let owner, owner.isActive else { return }
    owner.deliver(update, to: self)
  }

  func callbackValue() -> JSValue? {
    pendingLock.lock()
    let isActive = active
    pendingLock.unlock()
    return isActive ? callback.value : nil
  }
}

final class JavascriptAPIThumbnails: JavascriptAPI, JavascriptAPIThumbnailsExportable {
  private var subscriptions: [String: JavascriptTimelineThumbnailSubscription] = [:]
  fileprivate private(set) var isActive = true

  @objc func subscribe(_ callback: JSValue) -> String? {
    guard isActive else { return nil }
    guard let player, let context else {
      throwError(withMessage: "thumbnails.subscribe: player is unavailable")
      return nil
    }
    guard callback.isObject,
          JSObjectIsFunction(context.jsGlobalContextRef, callback.jsValueRef) else {
      throwError(withMessage: "thumbnails.subscribe: callback must be a function")
      return nil
    }

    player.validateTimelineThumbnailSession()
    let subscription = JavascriptTimelineThumbnailSubscription(
      id: UUID().uuidString,
      callback: callback,
      owner: self,
      virtualMachine: context.virtualMachine
    )
    let brokerID = player.timelineThumbnailBroker.subscribe { [weak subscription] update in
      subscription?.enqueue(update)
    }
    subscriptions[brokerID] = subscription
    return brokerID
  }

  @objc func unsubscribe(_ id: String) {
    guard let player else { return }
    player.timelineThumbnailBroker.unsubscribe(id)
    subscriptions.removeValue(forKey: id)?.cancel()
  }

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    isActive = false
    guard let player else {
      subscriptions.values.forEach { $0.cancel() }
      subscriptions.removeAll()
      return
    }
    let current = subscriptions
    subscriptions.removeAll()
    current.forEach { id, subscription in
      player.timelineThumbnailBroker.unsubscribe(id)
      subscription.cancel()
    }
  }

  fileprivate func deliver(_ update: TimelineThumbnailUpdate, to subscription: JavascriptTimelineThumbnailSubscription) {
    guard isActive,
          let callback = subscription.callbackValue(),
          let context,
          let payload = makePayload(update, in: context) else { return }
    callback.call(withArguments: [payload])
  }

  private func makePayload(_ update: TimelineThumbnailUpdate, in context: JSContext) -> JSValue? {
    let thumbnails = update.thumbnails.map {
      JavascriptTimelineThumbnail(value: $0, context: context)
    }
    let payload: [String: Any] = [
      "state": update.state.rawValue,
      "progress": update.progress,
      "media": update.media?.dictionary ?? NSNull(),
      "thumbnails": thumbnails,
      "reason": update.reason ?? NSNull()
    ]
    return JSValue(object: payload, in: context)
  }
}
