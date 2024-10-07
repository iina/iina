//
//  MPVNode.swift
//  iina
//
//  Created by lhc on 21/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

class MPVNode {

  static func parse(_ node: mpv_node) throws -> Any? {
    switch node.format {
    case MPV_FORMAT_FLAG:
      return node.u.flag != 0

    case MPV_FORMAT_STRING:
      return String(cString: node.u.string!)

    case MPV_FORMAT_INT64:
      return node.u.int64

    case MPV_FORMAT_DOUBLE:
      return node.u.double_

    case MPV_FORMAT_NODE_ARRAY:
      let list = node.u.list!.pointee
      var arr: [Any?] = []
      if list.num == 0 { return arr }
      var ptr = list.values!
      for _ in 0 ..< list.num {
        try arr.append(parse(ptr.pointee))
        ptr = ptr.successor()
      }
      return arr

    case MPV_FORMAT_NODE_MAP:
      let map = node.u.list!.pointee
      // node map can be empty. return nil for this case.
      if map.num == 0 { return nil }
      var dic: [String: Any?] = [:]
      var kptr = map.keys!
      var vptr = map.values!
      for _ in 0 ..< map.num {
        let k = String(cString: kptr.pointee!)
        let v = try parse(vptr.pointee)
        dic[k] = v
        kptr = kptr.successor()
        vptr = vptr.successor()
      }
      return dic

    case MPV_FORMAT_BYTE_ARRAY:
      let array = node.u.ba!.pointee
      let data = array.data!
      let size = array.size
      var byteArray: [UInt8] = []
      for i in 0 ..< size {
        byteArray.append(data.load(fromByteOffset: i, as: UInt8.self))
      }
      return byteArray

    case MPV_FORMAT_NONE:
      return nil

    default:
      throw IINAError.unsupportedMPVNodeFormat(node.format.rawValue)
    }
  }


  /** Create a mpv node from any object. */
  static func create(_ obj: Any?) throws -> mpv_node {
    var node = mpv_node()

    if obj == nil {
      node.format = MPV_FORMAT_NONE
      return node
    }

    switch obj! {

    case is Int:
      node.format = MPV_FORMAT_INT64
      node.u.int64 = Int64(obj as! Int)

    case is Double:
      node.format = MPV_FORMAT_DOUBLE
      node.u.double_ = obj as! Double

    case is Bool:
      node.format = MPV_FORMAT_FLAG
      node.u.flag = (obj as! Bool) ? 1 : 0

    case is String:
      node.format = MPV_FORMAT_STRING
      node.u.string = allocString(obj as! String)

    // Array
    case is [Any?]:
      node.format = MPV_FORMAT_NODE_ARRAY
      // actual array
      let objArray = obj as! [Any?]
      // create node ptr
      let nodePtr = UnsafeMutablePointer<mpv_node>.allocate(capacity: objArray.count)
      var nodeiPtr = nodePtr
      // assign each node ptr
      try objArray.forEach { element in
        try nodeiPtr.pointee = create(element)
        nodeiPtr = nodeiPtr.successor()
      }
      // create list
      var list = mpv_node_list()
      list.num = Int32(objArray.count)
      list.values = nodePtr
      // crate list ptr
      let listPtr = UnsafeMutablePointer<mpv_node_list>.allocate(capacity: 1)
      listPtr.pointee = list
      // assign list ptr
      node.u.list = listPtr

    // Dictionary
    case is [String: Any?]:
      node.format = MPV_FORMAT_NODE_MAP
      // actual dic
      let objDic = obj as! [String: Any?]
      // create key and value ptr
      let valuePtr = UnsafeMutablePointer<mpv_node>.allocate(capacity: objDic.count)
      let keyPtr = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: objDic.count)
      var valueiPtr = valuePtr
      var keyiPtr = keyPtr
      // assign each key and value ptr
      try objDic.forEach { (k, v) in
        try valueiPtr.pointee = create(v)
        keyiPtr.pointee = allocString(k)
        valueiPtr = valueiPtr.successor()
        keyiPtr = keyiPtr.successor()
      }
      // create list
      var list = mpv_node_list()
      list.num = Int32(objDic.count)
      list.keys = keyPtr
      list.values = valuePtr
      // create list ptr
      let listPtr = UnsafeMutablePointer<mpv_node_list>.allocate(capacity: 1)
      listPtr.pointee = list
      // assign list ptr
      node.u.list = listPtr

    default:
      throw IINAError.unsupportedMPVNodeFormat(90)

    }

    return node
  }

  static func free(_ node: mpv_node) {
    switch node.format {

    case MPV_FORMAT_STRING:
      deallocString(node.u.string)

    case MPV_FORMAT_NODE_ARRAY:
      let list = node.u.list!.pointee
      let num = Int(list.num)
      if num == 0 { return }
      let ptr = list.values!
      var iptr = ptr
      for _ in 0 ..< num {
        self.free(iptr.pointee)
        iptr = iptr.successor()
      }
      ptr.deinitialize(count: num)
      ptr.deallocate()

    case MPV_FORMAT_NODE_MAP:
      let map = node.u.list!.pointee
      let num = Int(map.num)
      if num == 0 { return }
      let kptr = map.keys!
      let vptr = map.values!
      var ikptr = kptr
      var ivptr = vptr
      for _ in 0 ..< num {
        if let strptr = ikptr.pointee { deallocString(strptr) }
        self.free(ivptr.pointee)
        ikptr = kptr.successor()
        ivptr = vptr.successor()
      }
      kptr.deinitialize(count: num)
      kptr.deallocate()
      vptr.deinitialize(count: num)
      vptr.deallocate()

    default:
      break

    }
  }

  private static func allocString(_ str: String) -> UnsafeMutablePointer<CChar> {
    let cstring = str.utf8CString
    let ptr = UnsafeMutablePointer<CChar>.allocate(capacity: cstring.count)
    var iptr = ptr
    for (_, n) in cstring.enumerated() {
      iptr.pointee = n
      iptr = iptr.successor()
    }
    return ptr
  }

  private static func deallocString(_ ptr: UnsafeMutablePointer<CChar>) {
    let str = String(cString: ptr)
    let len = str.cString(using: .utf8)!.count
    ptr.deinitialize(count: len)
    ptr.deallocate()
  }

}

extension mpv_node: CustomDebugStringConvertible {

  /// A textual representation of this instance, suitable for debugging.
  ///
  /// If the node is an array or a map the string will continue multiple lines.
  public var debugDescription: String { mpv_node.toString(self) }

  /// Return a textual representation of the given`mpv_node`, suitable for debugging.
  ///
  /// If the node is an array or a map the string will continue multiple lines.
  /// For arrays and maps the string will include all nodes referenced by the given node.
  /// - Parameter node: The `mpv_node` to return a textual representation of.
  /// - Parameter indent: Used to control indentation of nested arrays and maps.
  /// - Returns: A string representing the given node as well as any nodes that node references.
  private static func toString(_ node: mpv_node, indent: String = "") -> String {
    switch node.format {
    case MPV_FORMAT_FLAG:
      return "MPV_FORMAT_FLAG \(node.u.flag)"

    case MPV_FORMAT_STRING:
      return "MPV_FORMAT_STRING \(String(cString: node.u.string!))"

    case MPV_FORMAT_INT64:
      return "MPV_FORMAT_INT64 \(node.u.int64)"

    case MPV_FORMAT_DOUBLE:
      return "MPV_FORMAT_DOUBLE \(node.u.double_)"

    case MPV_FORMAT_NODE_ARRAY:
      let list = node.u.list!.pointee
      var results = "MPV_FORMAT_NODE_ARRAY \(list.num) entries"
      if list.num == 0 { return results }
      let deeperIndent = "\(indent)  "
      var ptr = list.values!
      for i in 0 ..< list.num {
        results += "\n\(deeperIndent)[\(i)] \(toString(ptr.pointee, indent: deeperIndent))"
        ptr = ptr.successor()
      }
      return results

    case MPV_FORMAT_NODE_MAP:
      let map = node.u.list!.pointee
      var results = "MPV_FORMAT_NODE_MAP \(map.num) entries"
      // node map can be empty.
      if map.num == 0 { return results }
      let deeperIndent = "\(indent)  "
      var kptr = map.keys!
      var vptr = map.values!
      for _ in 0 ..< map.num {
        results += """
          \n\(deeperIndent)\(String(cString: kptr.pointee!)) = \
          \(toString(vptr.pointee, indent: deeperIndent))
          """
        kptr = kptr.successor()
        vptr = vptr.successor()
      }
      return results

    case MPV_FORMAT_BYTE_ARRAY:
      let array = node.u.ba!.pointee
      let data = array.data!
      let size = array.size
      var results = "MPV_FORMAT_BYTE_ARRAY \(size) bytes "
      for i in 0 ..< size {
        results += String(data.load(fromByteOffset: i, as: UInt8.self), radix: 16, uppercase: true)
      }
      return results

    case MPV_FORMAT_NONE:
      return "MPV_FORMAT_NONE"

    default:
      return "Unsupported node format \(node.format.rawValue)"
    }
  }
}
