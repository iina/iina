//
//  ReadWriteLock.swift
//  iina
//
//  Created by low-batt on 7/8/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation

final class ReadWriteLock {
  private var rwlock = pthread_rwlock_t()

  init() {
    pthread_rwlock_init(&rwlock, nil)
  }

  deinit {
    pthread_rwlock_destroy(&rwlock)
  }

  func read<T>(_ body: () throws -> T) rethrows -> T {
    pthread_rwlock_rdlock(&rwlock)
    defer { pthread_rwlock_unlock(&rwlock) }
    return try body()
  }

  func write<T>(_ body: () throws -> T) rethrows -> T {
    pthread_rwlock_wrlock(&rwlock)
    defer { pthread_rwlock_unlock(&rwlock) }
    return try body()
  }
}
