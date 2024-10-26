//
//  TouchBarSettings.swift
//  iina
//
//  Created by low-batt on 9/6/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// Provides access to the macOS [Touch Bar](https://support.apple.com/guide/mac-help/use-the-touch-bar-mchlbfd5b039/mac)  settings.
///
/// The [Customize the Touch Bar on Mac](https://support.apple.com/guide/mac-help/customize-the-touch-bar-mchl5a63b060/mac)
/// section of the [Mac User Guide](https://support.apple.com/guide/mac-help/welcome/mac) describes the
/// [Touch Bar](https://support.apple.com/guide/mac-help/use-the-touch-bar-mchlbfd5b039/mac) settings
/// provided by macOS. The user can choose to configure the Touch Bar such that it is not showing the app controls provided by IINA. In
/// order to adhere to the best practices  in the [Energy Efficiency Guide for Mac Apps](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/UsingEfficientGraphics.html#//apple_ref/doc/uid/TP40013929-CH27-SW1)
/// IINA needs to avoid drawing the Touch Bar if it is not displaying app controls. View attributes such as `visibleRect` indicate
/// IINA's app controls are visible even when the Touch Bar is not displaying them. IINA must check the Touch Bar settings to determine
/// if app controls are being displayed.
///
/// On Macs with a Touch Bar the settings are stored in `~/Library/Preferences/com.apple.touchbar.agent.plist`. The
/// current settings can be seen by running the following command in
/// [Terminal](https://support.apple.com/guide/terminal/welcome/mac):
/// ````
/// defaults read com.apple.touchbar.agent
/// ````
struct TouchBarSettings {
  /// The `TouchBarSettings` singleton object.
  static let shared = TouchBarSettings()
  
  /// The keys that are contained in the macOS Touch Bar settings property list.
  enum Key: String {
    
    /// This key has a dictionary value that stores the `Press and hold fn key to` setting.
    ///
    /// The value of the `PresentationModeGlobal` setting is used as the key to obtain the active value of this setting. Using a
    /// dictionary preserves the values of this setting for other values of the `PresentationModeGlobal` setting.
    case PresentationModeFnModes
    
    /// This key has a string value that stores the `Touch Bar shows` setting along with the `Show Control Strip` setting,
    /// indicated by a `WithControlStrip` suffix.
    ///
    /// The `Show Control Strip` setting is only applicable to a subset of the possible `Touch Bar shows` values. The
    /// possible values are:
    /// - App Controls ("app" or "appWithControlStrip")
    /// - Expanded Control Strip ("fullControlStrip")
    /// - F1, F2, etc. Keys ("functionKeys")
    /// - Quick Actions ("workflows" or "workflowsWithControlStrip")
    /// - Spaces ("spaces" or "spacesWithControlStrip")
    case PresentationModeGlobal
    
    /// This key has a dictionary value that stores the `show function keys in Touch Bar instead of app controls`
    /// setting.
    ///
    /// An app's [bundle ID](https://developer.apple.com/documentation/bundleresources/information_property_list/cfbundleidentifier_)
    /// is used as the key to the dictionary. The value is always "functionKeys".
    case PresentationModePerApp
  }

  /// The values that are contained in the macOS Touch Bar settings property list.
  private enum Value: String {
    case app
    case appWithControlStrip
    case fullControlStrip
    case functionKeys
    case spaces
    case spacesWithControlStrip
    case workflows
    case workflowsWithControlStrip
  }

  /// Will be `false` if it is _known for certain_ that the Touch Bar is not configured to show app controls; otherwise `true`.
  /// - Note: If the the `Press and hold fn key to` setting is set to `App Controls` IINA assumes app controls are being
  ///         displayed all the time. It would be possible to optimize this further so that in this case IINA would draw the Touch Bar
  ///         only when the `fn` key is pressed.
  var showAppControls: Bool {
    if hasPerAppSetting() { return false }
    guard let globalSetting = getGlobalSetting() else { return true }
    if globalSetting == Value.app || globalSetting == Value.appWithControlStrip {
      return true
    }
    guard let fnModeSetting = getFnModeSetting(globalSetting) else { return true }
    return fnModeSetting == Value.app || globalSetting == Value.appWithControlStrip
  }
  
  /// The macOS TouchBar settings.
  ///
  /// This will be `nil` on Macs that do not have a Touch Bar.
  private let defaults: UserDefaults?

  /// Registers the observer object to receive notifications for the specified setting.
  /// - Parameters:
  ///   - observer: The object to register for notifications of changes to the specified setting. The observer must implement
  ///               the key-value observing method [observeValue(forKeyPath:of:change:context:)](https://developer.apple.com/documentation/objectivec/nsobject/1416553-observevalue).
  ///   - key: The setting to observe.
  ///   - options: A combination of the `NSKeyValueObservingOptions` values that specifies what is included in
  ///             observation notifications. For possible values, see [NSKeyValueObservingOptions](https://developer.apple.com/documentation/foundation/nskeyvalueobservingoptions).
  ///   - context: Arbitrary data that is passed to observer in [observeValue(forKeyPath:of:change:context:)](https://developer.apple.com/documentation/objectivec/nsobject/1416553-observevalue).
  func addObserver(_ observer: NSObject, forKey key: Key, options: NSKeyValueObservingOptions = [],
                   context: UnsafeMutableRawPointer? = nil) {
    defaults?.addObserver(observer, forKeyPath: key.rawValue, options: options, context: context)
  }

  // MARK: - Private Functions

  /// Returns the value for the specified setting.
  ///
  /// This is a simple wrapper that merely allows the caller to specify the setting as a `Key` enumeration value instead of a String.
  /// - Parameter key: The setting to return the value of.
  /// - Returns: The value set for the specified setting.
  private func dictionary(_ key: Key) -> [String : Any]? {
    guard let defaults else { return nil }
    return defaults.dictionary(forKey: key.rawValue)
  }
  
  /// Returns the value of the `Press and hold fn key to` setting.
  /// - Parameter globalSetting: The value the `Touch Bar shows` setting is set to.
  /// - Returns: The value of the setting if known; otherwise `nil`.
  private func getFnModeSetting(_ globalSetting: Value) -> Value? {
    guard let dictionary = dictionary(Key.PresentationModeFnModes) else {
      // Return the default for the associated with the global setting.
      return globalSetting == .functionKeys ? .fullControlStrip : .functionKeys
    }
    guard let string = dictionary[globalSetting.rawValue] as? String else {
      // Return the default for the associated with the global setting.
      return globalSetting == .functionKeys ? .fullControlStrip : .functionKeys
    }
    guard let value = Value(rawValue: string) else {
      // Internal error. Should never be logged.
      Logger.log("PresentationModeFnModes value \(string) not recognized", level: .error)
      return nil
    }
    return value
  }
  
  /// Returns the value of the `Touch Bar shows` setting.
  /// - Returns: The value of the setting if known; otherwise `nil`.
  private func getGlobalSetting() -> Value? {
    guard let string = string(Key.PresentationModeGlobal) else { return nil }
    guard let value = Value(rawValue: string) else {
      // Internal error. Should never be logged.
      Logger.log("PresentationModeGlobal value \(string) not recognized", level: .error)
      return nil
    }
    return value
  }
  
  /// Returns `true` if the Touch Bar should show function keys for IINA instead of app controls.
  /// - Returns: `true` if the user has added IINA to the `show function keys in Touch Bar instead of app controls`
  ///             macOS setting; otherwise `false`.
  private func hasPerAppSetting() -> Bool {
    guard let dictionary = dictionary(Key.PresentationModePerApp),
          let string = dictionary[InfoDictionary.shared.bundleIdentifier] as? String else {
      return false
    }
    // The expectation is that the value can only ever be "functionKeys". Thus the mere presence of
    // an app's bundle ID in the dictionary means the Touch Bar will display function keys for the
    // app. Therefore following checks should not be needed. They are internal error checks that
    // confirm our understanding of how the macOS Touch Bar settings property list operates.
    guard let value = Value(rawValue: string) else {
      Logger.log("PresentationModePerApp value \(string) not recognized", level: .error)
      return false
    }
    guard value == Value.functionKeys else {
      Logger.log("PresentationModePerApp value \(value) not functionKeys", level: .error)
      return false
    }
    return true
  }

  /// Returns the value for the specified setting.
  ///
  /// This is a simple wrapper that merely allows the caller to specify the setting as a `Key` enumeration value instead of a String.
  /// - Parameter key: The setting to return the value of.
  /// - Returns: The value set for the specified setting.
  private func string(_ key: Key) -> String? {
    guard let defaults else { return nil }
    return defaults.string(forKey: key.rawValue)
  }

  private init() {
    defaults = UserDefaults(suiteName: "com.apple.touchbar.agent")
  }
}
