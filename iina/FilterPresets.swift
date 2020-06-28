//
//  FilterPresets.swift
//  iina
//
//  Created by lhc on 25/8/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation

fileprivate typealias PM = FilterParameter

/**
 A filter preset or tamplate, which contains the filter name and definitions of all parameters.
 */
class FilterPreset {
  typealias Transformer = (FilterPresetInstance) -> MPVFilter

  private static let defaultTransformer: Transformer = { instance in
    return MPVFilter(lavfiFilterFromPresetInstance: instance)
  }

  var name: String
  var params: [String: FilterParameter]
  var paramOrder: [String]?
  /** Given an instance, create the corresponding `MPVFilter`. */
  var transformer: Transformer

  var localizedName: String {
    return FilterPreset.l10nDic[name] ?? name
  }

  init(_ name: String,
       params: [String: FilterParameter],
       paramOrder: String? = nil,
       transformer: @escaping Transformer = FilterPreset.defaultTransformer) {
    self.name = name
    self.params = params
    self.paramOrder = paramOrder?.components(separatedBy: ":")
    self.transformer = transformer
  }

  func localizedParamName(_ param: String) -> String {
    return FilterPreset.l10nDic["\(name).\(param)"] ?? param
  }
}

/**
 An instance of a filter preset, with concrete values for each parameter.
 */
class FilterPresetInstance {
  var preset: FilterPreset
  var params: [String: FilterParameterValue] = [:]

  init(from preset: FilterPreset) {
    self.preset = preset
  }

  func value(for name: String) -> FilterParameterValue {
    return params[name] ?? preset.params[name]!.defaultValue
  }
}

/**
 Definition of a filter parameter. It can be one of several types:
 - `text`: A generic string value.
 - `int`: An int value with range. It will be rendered as a slider.
 - `float`: A float value with range. It will be rendered as a slider.
 */
class FilterParameter {
  enum ParamType {
    case text, int, float, choose
  }
  var type: ParamType
  var defaultValue: FilterParameterValue
  // for float
  var min: Float?
  var max: Float?
  // for int
  var minInt: Int?
  var maxInt: Int?
  var step: Int?
  // for choose
  var choices: [String] = []

  static func text(defaultValue: String = "") -> FilterParameter {
    return FilterParameter(.text, defaultValue: FilterParameterValue(string: defaultValue))
  }

  static func int(min: Int, max: Int, step: Int = 1, defaultValue: Int = 0) -> FilterParameter {
    let pm = FilterParameter(.int, defaultValue: FilterParameterValue(int: defaultValue))
    pm.minInt = min
    pm.maxInt = max
    pm.step = step
    return pm
  }

  static func float(min: Float, max: Float, defaultValue: Float = 0) -> FilterParameter {
    let pm = FilterParameter(.float, defaultValue: FilterParameterValue(float: defaultValue))
    pm.min = min
    pm.max = max
    return pm
  }

  static func choose(from choices: [String], defaultChoiceIndex: Int = 0) -> FilterParameter {
    guard !choices.isEmpty else { fatalError("FilterParameter: Choices cannot be empty") }
    let pm = FilterParameter(.choose, defaultValue: FilterParameterValue(string: choices[defaultChoiceIndex]))
    pm.choices = choices
    return pm
  }

  private init(_ type: ParamType, defaultValue: FilterParameterValue) {
    self.type = type
    self.defaultValue = defaultValue
  }
}

/**
 The structure to store values of different param types.
 */
struct FilterParameterValue {
  private var _stringValue: String?
  private var _intValue: Int?
  private var _floatValue: Float?

  var stringValue: String {
    return _stringValue ?? _intValue?.description ?? _floatValue?.description ?? ""
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

/** Related data. */

extension FilterPreset {
  /** Preloaded localization. */
  static let l10nDic: [String: String] = {
    guard let filePath = Bundle.main.path(forResource: "FilterPresets", ofType: "strings"),
      let dic = NSDictionary(contentsOfFile: filePath) as? [String : String] else {
        return [:]
    }
    return dic
  }()

  static private let customMPVFilterPreset = FilterPreset("custom_mpv", params: ["name": PM.text(defaultValue: ""), "string": PM.text(defaultValue: "")]) { instance in
      return MPVFilter(rawString: instance.value(for: "name").stringValue + "=" + instance.value(for: "string").stringValue)!
  }
  // custom ffmpeg
  static private let customFFmpegFilterPreset = FilterPreset("custom_ffmpeg", params: [ "name": PM.text(defaultValue: ""), "string": PM.text(defaultValue: "") ]) { instance in
    return MPVFilter(name: "lavfi", label: nil, paramString: "[\(instance.value(for: "name").stringValue)=\(instance.value(for: "string").stringValue)]")
  }

  /** All filter presets. */
  static let vfPresets: [FilterPreset] = [
    // crop
    FilterPreset("crop", params: [
      "x": PM.text(), "y": PM.text(),
      "w": PM.text(), "h": PM.text()
    ], paramOrder: "w:h:x:y") { instance in
      return MPVFilter(mpvFilterFromPresetInstance: instance)
    },
    // expand
    FilterPreset("expand", params: [
      "x": PM.text(), "y": PM.text(),
      "w": PM.text(), "h": PM.text(),
      "aspect": PM.text(defaultValue: "0"),
      "round": PM.text(defaultValue: "1")
    ], paramOrder: "w:h:x:y:aspect:round") { instance in
      return MPVFilter(mpvFilterFromPresetInstance: instance)
    },
    // sharpen
    FilterPreset("sharpen", params: [
      "amount": PM.float(min: 0, max: 1.5),
      "msize": PM.int(min: 3, max: 23, step: 2, defaultValue: 5)
    ]) { instance in
      return MPVFilter.unsharp(amount: instance.value(for: "amount").floatValue,
                               msize: instance.value(for: "msize").intValue)
    },
    // blur
    FilterPreset("blur", params: [
      "amount": PM.float(min: 0, max: 1.5),
      "msize": PM.int(min: 3, max: 23, step: 2, defaultValue: 5)
    ]) { instance in
      return MPVFilter.unsharp(amount: -instance.value(for: "amount").floatValue,
                               msize: instance.value(for: "msize").intValue)
    },
    // delogo
    FilterPreset("delogo", params: [
      "x": PM.text(defaultValue: "1"),
      "y": PM.text(defaultValue: "1"),
      "w": PM.text(defaultValue: "1"),
      "h": PM.text(defaultValue: "1")
    ], paramOrder: "x:y:w:h"),
    // invert color
    FilterPreset("negative", params: [:]) { instance in
      return MPVFilter(lavfiName: "lutrgb", label: nil, paramDict: [
          "r": "negval", "g": "negval", "b": "negval"
        ])
    },
    // flip
    FilterPreset("vflip", params: [:]) { instance in
      return MPVFilter(mpvFilterFromPresetInstance: instance)
    },
    // mirror
    FilterPreset("hflip", params: [:]) { instance in
      return MPVFilter(mpvFilterFromPresetInstance: instance)
    },
    // 3d lut
    FilterPreset("lut3d", params: [
      "file": PM.text(),
      "interp": PM.choose(from: ["nearest", "trilinear", "tetrahedral"], defaultChoiceIndex: 0)
    ]) { instance in
      return MPVFilter(lavfiName: "lut3d", label: nil, paramDict: [
        "file": instance.value(for: "file").stringValue,
        "interp": instance.value(for: "interp").stringValue,
        ])
    },
    // custom
    customMPVFilterPreset,
    customFFmpegFilterPreset
  ]

  static let afPresets: [FilterPreset] = [
    customMPVFilterPreset,
    customFFmpegFilterPreset
  ]
}
