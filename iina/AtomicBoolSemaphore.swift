//
//  AtomicBoolSemaphore.swift
//  iina
//
//  Created by low-batt on 9/21/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/// An atomic boolean combined with a semaphore to allow waiting for the boolean to be set to `true`.
///
/// This class is expected to be used as follows:
/// - This boolean is set to `false`, recreating the semaphore
/// - A single thread waits for this boolean to be set to `true`
/// - Another thread sets this boolean to `true`
/// - The waiting thread is allowed to proceed
///
/// As a semaphore is used the thread can start waiting after the thread has been set to `true` and it will
/// immediately be allowed to proceed. However if this boolean is set to `false` while a tread is waiting,
/// that thread will never be allowed to proceed.
@propertyWrapper
class AtomicBoolSemaphore {

  var projectedValue = DispatchSemaphore(value: 0)

  @AtomicBool private var value: Bool
  var wrappedValue: Bool {
    get { value }
    set {
      value = newValue
      guard newValue else {
        projectedValue = DispatchSemaphore(value: 0)
        return
      }
      projectedValue.signal()
    }
  }
}
