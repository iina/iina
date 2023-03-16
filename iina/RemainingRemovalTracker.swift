/*
 From: https://stackoverflow.com/a/63281265/1347529
 Created by Giles Hammond on 03/08/2020.
 Copyright © 2020 Explore and Create Limited. All rights reserved.

 This extension generates an array of steps that can be applied sequentially to an interface, or
 associated collection, to remove, insert AND move items. Apart from the first and last steps, all
 step indexes are transient and do not relate directly to the start or end collections.

 The standard Changes are ordered: removals high->low, insertions low->high. RemainingRemovalTracker
 is used to track the position of items left in the collection, but that are assumed absent in the
 offsets provided for later insertions.
 */

typealias RemainingRemovalTracker = [Int:Int]

extension RemainingRemovalTracker {

  mutating func addSkippedRemoval(atOffset offset: Int) {
    self[offset] = offset }

  mutating func useSkippedRemoval(withOriginalOffset originalOffset: Int) -> Int {
    let currentOffset = removeValue(forKey: originalOffset)!
    removalMade(at: currentOffset)
    return currentOffset }

  mutating func removalMade(at offset: Int) {
    forEach({ key, value in
      if value > offset {
        self[key] = value - 1 } })
  }

  mutating func insertionMade(at offset: Int) {
    forEach { key, value in
      if value >= offset {
        self[key] = value + 1 } }
  }

  func adjustedInsertion(withOriginalOffset originalOffset: Int) -> Int {
    var adjustedOffset = originalOffset

    values.sorted().forEach { offset in
      if offset <= adjustedOffset {
        adjustedOffset += 1 } }

    return adjustedOffset
  }
}

@available(macOS 10.15, *)
extension CollectionDifference where ChangeElement: Hashable
{
  public typealias Steps = Array<CollectionDifference<ChangeElement>.ChangeStep>

  public enum ChangeStep {
    case insert(_ element: ChangeElement, at: Int)
    case remove(_ element: ChangeElement, at: Int)
    case move(_ element: ChangeElement, from: Int, to: Int)
  }

  var maxOffset: Int { Swift.max(removals.last?.offset ?? 0, insertions.last?.offset ?? 0) }

  public var steps: Steps {
    guard !isEmpty else { return [] }

    var steps = Steps()
    var offsetTracker = RemainingRemovalTracker()

    inferringMoves().forEach { change in
      switch change {
        case let .remove(offset, element, associatedWith):
          if associatedWith != nil {
            offsetTracker.addSkippedRemoval(atOffset: offset)
          } else {
            steps.append(.remove(element, at: offset))
            offsetTracker.removalMade(at: offset)
          }

        case let.insert(offset, element, associatedWith):
          if let associatedWith = associatedWith {
            let from = offsetTracker.useSkippedRemoval(withOriginalOffset: associatedWith)
            let to = offsetTracker.adjustedInsertion(withOriginalOffset: offset)
            steps.append(.move(element, from: from, to: to))
            offsetTracker.insertionMade(at: to)
          } else {
            let to = offsetTracker.adjustedInsertion(withOriginalOffset: offset)
            steps.append(.insert(element, at: to))
            offsetTracker.insertionMade(at: to)
          }
      }
    }

    return steps
  }
}

@available(macOS 10.15, *)
extension CollectionDifference.Change
{
  var offset: Int {
    switch self {
      case let .insert(offset, _, _): return offset
      case let .remove(offset, _, _): return offset
    }
  }
}
