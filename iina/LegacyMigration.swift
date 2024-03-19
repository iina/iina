//
//  LegacyMigration.swift
//  iina
//
//  Created by Matt Svoboda on 11/27/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

class LegacyMigration {

  /// Map of [modern pref key → legacy key].
  ///
  /// - Important: Do not reference legacy keys outside this file.
  fileprivate static let legacyColorPrefKeyMap: [Preference.Key: Preference.Key] = [
    Preference.Key.subTextColorString: Preference.Key("subTextColor"),
    Preference.Key.subBgColorString: Preference.Key("subBgColor"),
    Preference.Key.subBorderColorString: Preference.Key("subBorderColor"),
    Preference.Key.subShadowColorString: Preference.Key("subShadowColor"),
  ]

  /**
   Loops over the set of legacy preference keys. If a value is found for a given legacy key, but no value is found for its modern equivalent key,
   the legacy value is migrated & stored under the modern key.

   Older versions of IINA serialized mpv color data into NSObject binary using the now-deprecated `NSUnarchiver` class.
   This method will transition to the new format which consists of the color components written to a `String`.
   To do this in a way which does not corrupt the values for older versions of IINA, we'll store the new format under a new `Preference.Key`,
   and leave the legacy pref entry as-is.

   This method will be executed on each of the affected prefs when IINA starts up. It will first check if there is already an entry for the new
   pref key. If it finds one, then it will assume that the migration has already occurred, and will just return that.
   Otherwise it will look for an entry for the legacy pref key. If it finds that, if will convert its value into the new format and store it under
   the new pref key, and then return that.

   This will have the effect of automatically migrating older versions of IINA into the new format with no loss of data.
   However, it is worth noting that this migration will only happen once, and afterwards newer versions of IINA will not look at the old pref entry.
   And since older versions of IINA will only use the old pref entry, users who mix old and new versions of IINA may experience different values
   for these keys.
   */
  static func migrateLegacyPreferences() {
    Logger.log("Looking for legacy color prefs to migrate", level: .verbose)

    var unmigratedEntriesFoundCount: Int = 0
    var entriesMigratedCount: Int = 0
    for (modernKey, legacyKey) in legacyColorPrefKeyMap {
      // Migrate pref only if there is a legacy entry with but no corresponding modern entry
      guard Preference.keyHasBeenPersisted(legacyKey),
            !Preference.keyHasBeenPersisted(modernKey) else { continue }
      unmigratedEntriesFoundCount += 1

      // Deserialize & convert legacy pref value to modern string format:
      guard let legacyData = Preference.data(for: legacyKey) else { continue }
      guard let color = NSUnarchiver.unarchiveObject(with: legacyData) as? NSColor,
            let mpvColorString = color.usingColorSpace(.deviceRGB)?.mpvColorString else {
        Logger.log("Failed to convert color value from legacy pref \(legacyKey.rawValue)", level: .error)
        continue
      }
      // Store string under modern pref key:
      Preference.set(mpvColorString, for: modernKey)
      Logger.log("Converted color value from legacy pref \(legacyKey.rawValue) and stored in pref \(modernKey.rawValue)")
      entriesMigratedCount += 1
    }
    if unmigratedEntriesFoundCount == 0 {
      Logger.log("No unmigrated legacy color prefs found")
    } else {
      Logger.log("Migrated \(entriesMigratedCount) of \(unmigratedEntriesFoundCount) legacy color prefs")
    }
  }

}
