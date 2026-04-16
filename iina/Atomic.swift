//
//  Atomic.swift
//  iina
//
//  Created by low-batt on 11/27/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

@propertyWrapper class Atomic<Value> {

  private let lock = Lock()

  var projectedValue: Atomic<Value> {
      return self
  }

  private var value: Value

  var wrappedValue: Value {
    get { lock.withLock { value } }
    set { lock.withLock { value = newValue } }
  }

  init(wrappedValue: Value) {
    self.value = wrappedValue
  }

  func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
    return try lock.withLock {
      return try body(&value)
    }
  }
}
