//
//  AtomicBool.swift
//  iina
//
//  Created by low-batt on 9/21/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Atomics
import Foundation

/// An atomic `Bool` with sequentially consistent loading and storing.
@propertyWrapper
class AtomicBool {

  private var value = ManagedAtomic<Bool>(false)

  var wrappedValue: Bool {
    get { value.load(ordering: .sequentiallyConsistent) }
    set { value.store(newValue, ordering: .sequentiallyConsistent)}
  }
}
