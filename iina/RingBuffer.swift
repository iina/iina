//
//  RingBuffer.swift
//  iina
//
//  Created by Matt Svoboda on 2022.05.17.
//  Copyright © 2022 lhc. All rights reserved.
//

/*
 Fixed-capacity ring buffer, backed by an data, which can append and pop from both the head and the tail.
 If already at full capacity:
 - Appending an element to the head will overwrite the element at the tail
 - Appending elements to the tail will overwrite the elements at the head
 */
public struct RingBuffer<T>: CustomStringConvertible, Sequence {
  private var data: [T?]
  private var tailIndex = 0
  private var headIndex = 0
  private var elementCount = 0

  public var count: Int {
    get {
      return elementCount
    }
  }

  public init(capacity: Int) {
    data = [T?](repeating: nil, count: capacity)
    resetCounters()
  }

  /*
   Gets the element at the head, without removing it or changing state in any way.
   */
  public var head: T? {
    get {
      return data[headIndex]
    }
  }

  /*
   Gets the element at the tail, without removing it or changing state in any way.
   */
  public var tail: T? {
    get {
      return data[tailIndex]
    }
  }

  public var isEmpty: Bool {
    return elementCount == 0
  }

  public var isFull: Bool {
    return elementCount == data.count
  }

  /*
   Sets all elements to zero & clears all internal variables to their initial state, except for `capacity`
   */
  public mutating func clear() {
    for i in 0..<data.count {
      data[i] = nil
    }
    resetCounters()
  }

  private mutating func resetCounters() {
    headIndex = 0
    tailIndex = 0
    elementCount = 0
  }

  /*
   Adds the given element to the head and increments the pointer. If already full, then the tail is overwritten.
   Returns true if the tail was overwritten; false if not.
   */
  @discardableResult
  public mutating func insertHead(_ element: T) -> Bool {
    let overwrite = isFull
    if overwrite {
      headIndex = (headIndex + 1) %% data.count
      tailIndex = (tailIndex + 1) %% data.count  // also advance tail since it is being overwritten
    } else {
      if data[headIndex] != nil {
        // was empty, but then insertTail happened. move over and use the next available space:
        headIndex = (headIndex + 1) %% data.count
      }
      elementCount = elementCount + 1
    }
    data[headIndex] = element
    return overwrite
  }

  /*
   Adds the given element to the tail and advances the tail pointer.
   If already full, then the head is overwritten and the head pointer retreats.
   Returns true if the head was overwritten; false if not.
   */
  @discardableResult
  public mutating func insertTail(_ element: T) -> Bool {
    let overwrite = isFull
    if overwrite {
      tailIndex = (tailIndex - 1) %% data.count
      headIndex = (headIndex - 1) %% data.count  // also retreat tail since it is being overwritten
    } else {
      if data[tailIndex] != nil {
        // was empty, but then insertHead happened. move over and use the next available space:
        tailIndex = (tailIndex - 1) %% data.count
      }
      elementCount = elementCount + 1
    }
    data[tailIndex] = element
    return overwrite
  }

  /*
   Pops and returns the element at the head, retreating the pointer to the head.
   Returns nil if already empty.
   */
  @discardableResult
  public mutating func removeHead() -> T? {
    guard !isEmpty else {
      return nil
    }
    defer {
      data[headIndex] = nil
      headIndex = (headIndex - 1) %% data.count
      elementCount = elementCount - 1
    }
    return data[headIndex]
  }

  /*
   Pops and returns the element at the tail, advancing the pointer to the tail.
   Returns nil if already empty.
   */
  @discardableResult
  public mutating func removeTail() -> T? {
    guard !isEmpty else {
      return nil
    }
    defer {
      data[tailIndex] = nil
      tailIndex = (tailIndex + 1) %% data.count
      elementCount = elementCount - 1
    }
    return data[tailIndex]
  }

  public var description: String {
    get {
      var string = ""
      for elem in self {
        if string.isEmpty {
          string = "\(elem)"
        } else {
          string.append(", \(elem)")
        }
      }
      return "[\(string)]"
    }
  }

  /*
   Returns an iterator which yields elements one at a time, in order of tail -> head
   */
  public func makeIterator() -> AnyIterator<T> {
    var index = tailIndex
    let endIndex = index + elementCount
    return AnyIterator {
      guard index < endIndex else { return nil }
      defer {
        index = index + 1
      }
      return data[index %% data.count]
    }
  }
}
