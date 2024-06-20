//
//  SettingsLocalization.swift
//  iina
//
//  Created by Hechen Li on 6/22/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

struct SettingsLocalization {
  struct Key: RawRepresentable {
    typealias RawValue = String
    var rawValue: String

    init(_ rawValue: String) {
      self.rawValue = rawValue
    }

    init?(rawValue: String) {
      self.rawValue = rawValue
    }
  }

  class Context {
    var tableName: String

    init(tableName: String) {
      self.tableName = tableName
    }

    func localized(_ key: Key) -> String {
      return NSLocalizedString(key.rawValue, tableName: tableName, comment: key.rawValue)
    }
  }

  static func injectContext(_ view: NSView, _ context: SettingsLocalization.Context!) {
    if var vc = view as? WithSettingsLocalizationContext {
      vc.l10n = context
    }
    for v in view.subviews {
      injectContext(v, context)
    }
  }

}

protocol WithSettingsLocalizationContext {
  var l10n: SettingsLocalization.Context! { get set }
}
