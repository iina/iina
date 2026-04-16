//
//  ReadWriteAtomic.swift
//  iina
//
//  Created by low-batt on 7/8/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

@propertyWrapper class ReadWriteAtomic<Value> {
  private let lock = ReadWriteLock()

  var projectedValue: ReadWriteAtomic<Value> {
      return self
  }

  private var value: Value

  var wrappedValue: Value {
    get { lock.read { value } }
    set { lock.write { value = newValue } }
  }

  init(wrappedValue: Value) {
    self.value = wrappedValue
  }

  func withReadLock<R>(_ body: (Value) throws -> R) rethrows -> R {
    return try lock.read {
      return try body(value)
    }
  }

  func withWriteLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
    return try lock.write {
      return try body(&value)
    }
  }
}
