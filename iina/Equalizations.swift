//
//  Untitled.swift
//  iina
//
//  Created by Yuze Jiang on 2024/06/29.
//  Copyright © 2024 lhc. All rights reserved.
//

class EQProfile: Codable {
  var gains = [Double](repeatElement(0.0, count: 10))

  init(_ values: [Double]) {
    gains = values
  }

  init(fromCurrentSliders sliders: [NSSlider]) {
    gains = sliders.map { $0.doubleValue }
  }
}

let presetEQs: KeyValuePairs = ["Flat": EQProfile([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
                                "Acoustic": EQProfile([0, 0, 0, 0, 12, 0, 0, 0, 0, 0]),
                                ]

var userEQs: Dictionary<String, EQProfile> = [:] {
  didSet {
    let encoder = JSONEncoder()
    if let encoded = try? encoder.encode(userEQs) {
      UserDefaults.standard.set(encoded, forKey: Preference.Key.userEQPresets.rawValue)
    }
  }
}
