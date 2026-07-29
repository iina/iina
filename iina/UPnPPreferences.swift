//
//  UPnPPreferences.swift
//  iina
//
//  Private UserDefaults storage for UPnP/DLNA browser settings.
//  Kept out of Preference.swift so UPnP does not touch IINA's Preferences / Settings UI.
//

import Foundation

/// UPnP/DLNA settings stored in `UserDefaults` under the same key strings previously used via
/// `Preference`, so existing installs keep favorites, columns, and behavior.
enum UPnPPreferences {

  // MARK: - Keys (stable UserDefaults names)

  enum Key {
    static let favorites = "upnpFavorites"
    static let columnDurationHidden = "upnpColumnDurationHidden"
    static let columnDateHidden = "upnpColumnDateHidden"
    static let columnAuthorHidden = "upnpColumnAuthorHidden"
    static let columnDescriptionHidden = "upnpColumnDescriptionHidden"
    static let columnSizeHidden = "upnpColumnSizeHidden"
    static let columnTypeHidden = "upnpColumnTypeHidden"
    static let autoPlayNext = "upnpAutoPlayNext"
    /// 0: close, 1: keep open, 2: reopen on end
    static let browserBehavior = "upnpBrowserBehavior"
    static let playbackContext = "upnpPlaybackContext"
    static let autoRefreshEnabled = "upnpAutoRefreshEnabled"
    static let autoRefreshInterval = "upnpAutoRefreshInterval"
    static let sortKey = "upnpSortKey"
    static let sortAscending = "upnpSortAscending"
  }

  private static let ud = UserDefaults.standard

  private static let defaults: [String: Any] = [
    Key.favorites: Data(),
    Key.columnDurationHidden: false,
    Key.columnDateHidden: true,
    Key.columnAuthorHidden: true,
    Key.columnDescriptionHidden: true,
    Key.columnSizeHidden: false,
    Key.columnTypeHidden: true,
    Key.autoPlayNext: true,
    Key.browserBehavior: 1,
    Key.playbackContext: Data(),
    Key.autoRefreshEnabled: true,
    Key.autoRefreshInterval: 30,
    Key.sortKey: "title",
    Key.sortAscending: true,
  ]

  /// Register defaults so missing keys (e.g. bools that default to `true`) resolve correctly.
  static func registerDefaults() {
    ud.register(defaults: defaults)
  }

  // MARK: - Accessors

  static func bool(forKey key: String) -> Bool {
    ud.bool(forKey: key)
  }

  static func integer(forKey key: String) -> Int {
    ud.integer(forKey: key)
  }

  static func string(forKey key: String) -> String? {
    ud.string(forKey: key)
  }

  static func data(forKey key: String) -> Data? {
    ud.data(forKey: key)
  }

  static func set(_ value: Bool, forKey key: String) {
    ud.set(value, forKey: key)
  }

  static func set(_ value: Int, forKey key: String) {
    ud.set(value, forKey: key)
  }

  static func set(_ value: String, forKey key: String) {
    ud.set(value, forKey: key)
  }

  static func set(_ value: Data, forKey key: String) {
    ud.set(value, forKey: key)
  }

  static func set(_ value: Any?, forKey key: String) {
    ud.set(value, forKey: key)
  }
}
