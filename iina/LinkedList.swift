/*
 Copyright (c) 2016 Matthijs Hollemans and contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.

 From Swift Algorithm Club (https://github.com/raywenderlich/swift-algorithm-club)
 (modified heavily for better efficiency & usability)
 */
public enum LinkedListError: Error {
  case listIsEmpty
  case indexInvalid(_ msg: String)
  case indexOutOfBounds(_ msg: String)
}

public final class LinkedList<T> {

  public class LinkedListNode<T> {
    var value: T
    var next: LinkedListNode?
    weak var prev: LinkedListNode?

    public init(value: T) {
      self.value = value
    }
  }

  /// Typealiasing the node class to increase readability of code
  public typealias Node = LinkedListNode<T>

  /// The first element of the LinkedList
  public var firstNode: Node?

  /// The last element of the LinkedList
  public var lastNode: Node?

  /// Computed property to check if the linked list is empty
  public var isEmpty: Bool {
    return count == 0
  }

  public private(set) var count: Int = 0

  public var first: T? {
    get {
      firstNode?.value
    }
  }

  public var last: T? {
    get {
      lastNode?.value
    }
  }

  /// Default initializer
  public init() {}


  /// Subscript function to return the node at a specific index
  ///
  /// - Parameter index: Integer value of the requested value's index
  public subscript(index: Int) -> T?  {
    return self.item(at: index)
  }

  /// Function to return the item at a specific index. Throws exception if index is out of bounds (0...self.count)
  /// - Parameter index: Integer value of the node's index to be returned
  /// - Returns: Node
  public func item(at index: Int) -> T? {
    return node(at: index)?.value
  }

  public func node(at index: Int) -> Node? {
    if firstNode == nil || index < 0 || index >= count {
      return nil
    }

    if index == 0 {
      return firstNode
    } else if index == count - 1 {
      return lastNode
    } else {
      var node = firstNode!.next
      for _ in 1..<index {
        node = node?.next
        assert (node != nil)
      }

      return node
    }
  }

  /// Function to return the node at a specific index. Throws exception if index is out of bounds (0...self.count)
  /// - Parameter whereCondition: Closure
  /// - Returns: T
  public func item(_ whereCondition: (T) -> Bool) -> T? {
    var node = firstNode

    while node != nil {
      if whereCondition(node!.value) {
        return node!.value
      } else {
        node = node!.next
      }
    }
    return nil
  }

  /// Insert a value to the beginning of the list
  /// - Parameter value: The data value to be pre-pended
  public func prepend(_ value: T) {
    let newNode = Node(value: value)
    try! insert(newNode, at: 0)
  }

  /// Append a value to the end of the list
  /// - Parameter value: The data value to be appended
  public func append(_ value: T) {
    let newNode = Node(value: value)
    try! insert(newNode, at: count)
  }

  /// Append a copy of a LinkedList to the end of the list.
  /// - Parameter list: The list to be copied and appended.
  public func appendAll(_ list: LinkedList) {
    var nodeToCopy = list.firstNode
    while let node = nodeToCopy {
      append(node.value)
      nodeToCopy = node.next
    }
  }

  /// Insert a value at a specific index. Crashes if index is out of bounds (0...self.count)
  ///
  /// - Parameters:
  ///   - value: The data value to be inserted
  ///   - index: Integer value of the index to be insterted at
  public func insert(_ value: T, at index: Int) throws {
    let newNode = Node(value: value)
    try insert(newNode, at: index)
  }

  /// Insert a copy of a node at a specific index. Crashes if index is out of bounds (0...self.count)
  ///
  /// - Parameters:
  ///   - node: The node containing the value to be inserted
  ///   - index: Integer value of the index to be inserted at
  private func insert(_ newNode: Node, at index: Int) throws {
    if index == 0 {
      if let firstNode = firstNode {
        newNode.next = firstNode
        firstNode.prev = newNode
      } else {
        lastNode = newNode
      }
      firstNode = newNode
    } else {
      guard let prev = node(at: index - 1) else {
        throw LinkedListError.indexOutOfBounds("Requested index is longer than this list: \(index)")
      }
      let next = prev.next
      newNode.prev = prev
      if let next = next {
        newNode.next = next
        next.prev = newNode
      } else {
        lastNode = newNode
      }
      prev.next = newNode
    }

    count += 1
  }

  /// Insert a copy of a LinkedList at a specific index. Crashes if index is out of bounds (0...self.count)
  ///
  /// - Parameters:
  ///   - list: The LinkedList to be copied and inserted
  ///   - index: Integer value of the index to be inserted at
  public func insertAll(_ list: LinkedList, at index: Int) throws {
    guard !list.isEmpty else { return }

    let insertCount = list.count

    if index == 0 {
      list.lastNode?.next = firstNode
      firstNode = list.firstNode
    } else {
      guard let prev = node(at: index - 1) else {
        throw LinkedListError.indexOutOfBounds("Invalid index: \(index)")
      }
      let next = prev.next

      prev.next = list.firstNode
      list.firstNode?.prev = prev

      if let next = next {
        list.lastNode?.next = next
        next.prev = list.lastNode
      } else {
        if list.lastNode != nil {
          lastNode = list.lastNode
        }
      }
    }

    count += insertCount
  }

  /*
   Removes all nodes/values from this list.
   This is an O(n) operation because all links are set to nil in each node.
   */
  public func removeAll() {
    var node = lastNode
    while let nodeToRemove = node {
      node = nodeToRemove.prev
      nodeToRemove.prev = nil
      nodeToRemove.next = nil
      count -= 1
    }

    lastNode = nil
    firstNode = nil
  }

  /*
   Removes all nodes/values from this list.
   This is an O(n) operation because all links are set to nil in each node.
   */
  public func clear() {
    removeAll()
  }

  @discardableResult
  public func remove(_ whereCondition: (T) -> Bool) -> T? {
    var node = firstNode

    while node != nil {
      if whereCondition(node!.value) {
        return remove(node: node!)
      } else {
        node = node!.next
      }
    }
    return nil
  }


  // Function to remove a specific node.
  // - Parameter node: The node to be deleted
  // - Returns: The data value contained in the deleted node.
  @discardableResult
  public func remove(node: Node) -> T {
    let prev = node.prev
    let next = node.next

    if let prev = prev {
      prev.next = next
    } else {
      firstNode = next
    }
    if let next = next {
      next.prev = prev
    } else {
      lastNode = prev
    }

    node.prev = nil
    node.next = nil

    count -= 1
    return node.value
  }

  /// Function to remove the last node/value in the list. Returns nil if the list is empty
  /// - Returns: The data value contained in the deleted node.
  @discardableResult
  public func removeLast() -> T? {
    guard !isEmpty else {
      return nil
    }
    return remove(node: lastNode!)
  }

  /// Function to remove a node/value at a specific index. Returns nil if index is out of bounds (0...self.count)
  /// - Parameter index: Integer value of the index of the node to be removed
  /// - Returns: The data value contained in the deleted node
  @discardableResult
  public func remove(at index: Int) -> T? {
    guard let node = self.node(at: index) else {
      return nil
    }
    return remove(node: node)
  }

  public func makeIterator() -> AnyIterator<T> {
    var node = firstNode
    return AnyIterator {
      if let thisExistingNode = node {
        node = thisExistingNode.next
        return thisExistingNode.value
      }
      return nil
    }
  }
}

//: End of the base class declarations & beginning of extensions' declarations:

// MARK: - Extension to enable the standard conversion of a list to String
extension LinkedList: CustomStringConvertible {
  public var description: String {
    var s = "["
    var node = firstNode
    while let nd = node {
      s += "\(nd.value)"
      node = nd.next
      if node != nil { s += ", " }
    }
    return s + "]"
  }
}

// MARK: - Extension to add a 'reverse' function to the list
extension LinkedList {
  public func reverse() {
    var node = firstNode
    while let currentNode = node {
      node = currentNode.next
      swap(&currentNode.next, &currentNode.prev)
      firstNode = currentNode
    }
  }
}

// MARK: - An extension with an implementation of 'map' & 'filter' functions
extension LinkedList {
  public func map<U>(transform: (T) -> U) -> LinkedList<U> {
    let result = LinkedList<U>()
    var node = firstNode
    while let nd = node {
      result.append(transform(nd.value))
      node = nd.next
    }
    return result
  }

  public func filter(predicate: (T) -> Bool) -> LinkedList<T> {
    let result = LinkedList<T>()
    var node = firstNode
    while let nd = node {
      if predicate(nd.value) {
        result.append(nd.value)
      }
      node = nd.next
    }
    return result
  }
}

// MARK: - Extension to enable initialization from an Array
extension LinkedList {
  convenience init(array: Array<T>) {
    self.init()

    array.forEach { append($0) }
  }
}

// MARK: - Extension to enable initialization from an Array Literal
extension LinkedList: ExpressibleByArrayLiteral {
  public convenience init(arrayLiteral elements: T...) {
    self.init()

    elements.forEach { append($0) }
  }
}

// MARK: - Collection
extension LinkedList: Collection {

  public typealias Index = LinkedListIndex<T>

  /// The position of the first element in a nonempty collection.
  /// If the collection is empty, `startIndex` is equal to `endIndex`.
  /// - Complexity: O(1)
  public var startIndex: Index {
    get {
      return LinkedListIndex<T>(node: firstNode, tag: 0)
    }
  }

  /// The collection's "past the end" position---that is, the position one greater than the last valid subscript argument.
  /// - Complexity: O(n), where n is the number of elements in the list. This can be improved by keeping a reference
  ///   to the last node in the collection.
  public var endIndex: Index {
    get {
      if let h = self.firstNode {
        return LinkedListIndex<T>(node: h, tag: count)
      } else {
        return LinkedListIndex<T>(node: nil, tag: startIndex.tag)
      }
    }
  }

  public subscript(position: Index) -> T {
    get {
      return position.node!.value
    }
  }

  public func index(after idx: Index) -> Index {
    return LinkedListIndex<T>(node: idx.node?.next, tag: idx.tag + 1)
  }
}

// MARK: - Collection Index
/// Custom index type that contains a reference to the node at index 'tag'
public struct LinkedListIndex<T>: Comparable {
  fileprivate let node: LinkedList<T>.LinkedListNode<T>?
  fileprivate let tag: Int

  public static func==<T>(lhs: LinkedListIndex<T>, rhs: LinkedListIndex<T>) -> Bool {
    return (lhs.tag == rhs.tag)
  }

  public static func< <T>(lhs: LinkedListIndex<T>, rhs: LinkedListIndex<T>) -> Bool {
    return (lhs.tag < rhs.tag)
  }
}
