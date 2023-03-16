//  MIT License
//
//  Copyright (c) 2021 Stefan Schmitt (https://schmittsfn.com)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import Foundation


/*
 # BiDictionary

 A bi-directional dictionary/map for the Swift programming language.


 Usage:
 ```
 var biDict = BiDictionary<String, String>()
 biDict[key: "foo"] = "bar"

 let value = biDict[key: "foo"]
 let key = biDict[value: "bar"]
 ```

 Project URL: https://github.com/schmittsfn/BiDictionary
 */
@frozen
public struct BiDictionary<Key: Hashable, Value: Hashable> {
  @usableFromInline
  internal var _keyValueDict: Dictionary<Key, Value>

  @usableFromInline
  internal var _valueKeyDict: Dictionary<Value, Key>

  @inlinable
  @inline(__always)
  internal init(
    _keyValueDict keys: Dictionary<Key, Value>,
    _valueKeyDict values: Dictionary<Value, Key>
  ) {
    self._keyValueDict = keys
    self._valueKeyDict = values
  }
}

extension BiDictionary {
  @inlinable
  @inline(__always)
  public var keys: Set<Key> { Set(_keyValueDict.keys) }

  @inlinable
  @inline(__always)
  public var values: Set<Value> { Set(_valueKeyDict.keys) }
}

extension BiDictionary {
  @inlinable
  public subscript(key key: Key) -> Value? {
    get {
      return _keyValueDict[key]
    }
    _modify {
      var value: Value? = nil
      value = _keyValueDict[key]

      defer {
        if let value = value {
          _valueKeyDict[value] = key
        }
        _keyValueDict[key] = value
      }

      yield &value
    }
  }

  @inlinable
  public subscript(value value: Value) -> Key? {
    get {
      return _valueKeyDict[value]
    }
    _modify {
      var key: Key? = nil
      key = _valueKeyDict[value]

      defer {
        if let key = key {
          _keyValueDict[key] = value
        }
        _valueKeyDict[value] = key
      }

      yield &key
    }
  }
}

extension BiDictionary {
  @inlinable
  @inline(__always)
  public init() {
    self._keyValueDict = Dictionary<Key, Value>()
    self._valueKeyDict = Dictionary<Value, Key>()
  }
}
