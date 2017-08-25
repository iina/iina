//
//  FilterPresets.swift
//  iina
//
//  Created by lhc on 25/8/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

fileprivate typealias PM = FilterParameter

class FilterPreset {
  typealias Transformer = (FilterPresetInstance) -> MPVFilter

  var name: String
  var params: [String: FilterParameter]
  var transformer: Transformer

  init(_ name: String, params: [String: FilterParameter], transformer: @escaping Transformer) {
    self.name = name
    self.params = params
    self.transformer = transformer
  }
}

class FilterPresetInstance {
  var preset: FilterPreset
  var params: [String: FilterParamaterValue] = [:]

  init(preset: FilterPreset) {
    self.preset = preset
  }

  func value(for name: String) -> FilterParamaterValue {
    return params[name] ?? preset.params[name]!.defaultValue
  }
}

class FilterParameter {
  enum ParamType {
    case text, int, float
  }
  var type: ParamType
  var defaultValue: FilterParamaterValue

  var min: Float?
  var max: Float?
  var minInt: Int?
  var maxInt: Int?
  var step: Int?

  static func text(defaultValue: String = "") -> FilterParameter {
    return FilterParameter(.text, defaultValue: FilterParamaterValue(string: defaultValue))
  }

  static func int(min: Int, max: Int, step: Int = 1, defaultValue: Int = 0) -> FilterParameter {
    let pm = FilterParameter(.int, defaultValue: FilterParamaterValue(int: defaultValue))
    pm.minInt = min
    pm.maxInt = max
    pm.step = step
    return pm
  }

  static func float(min: Float, max: Float, defaultValue: Float = 0) -> FilterParameter {
    let pm = FilterParameter(.float, defaultValue: FilterParamaterValue(float: defaultValue))
    pm.min = min
    pm.max = max
    return pm
  }


  private init(_ type: ParamType, defaultValue: FilterParamaterValue) {
    self.type = type
    self.defaultValue = defaultValue
  }
}

struct FilterParamaterValue {
  private var _stringValue: String?
  private var _intValue: Int?
  private var _floatValue: Float?

  var stringValue: String {
    return _stringValue ?? ""
  }

  var intValue: Int {
    return _intValue ?? 0
  }

  var floatValue: Float {
    return _floatValue ?? 0
  }

  init(string: String) {
    self._stringValue = string
  }

  init(int: Int) {
    self._intValue = int
  }

  init(float: Float) {
    self._floatValue = float
  }
}


extension FilterPreset {
  static let presets: [FilterPreset] = [
    // unsharpen
    FilterPreset("unsharpen", params: [
      "amount": PM.float(min: 0, max: 1.5)
    ]) { instance in
      let rawValue = instance.value(for: "amount").floatValue
      return MPVFilter.unsharp(amount: rawValue)
    }
  ]
}
