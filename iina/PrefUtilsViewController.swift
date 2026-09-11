//
//  PrefUtilsViewController.swift
//  iina
//
//  Created by Collider LI on 9/7/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class PrefUtilsViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefUtilsViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.utilities", comment: "Utilities")
  }

  var preferenceTabImage: NSImage {
    return .sf("wrench.and.screwdriver", withConfiguration: symbolConfiguration)!
  }

  override var sectionViews: [NSView] {
    return [sectionDefaultAppView, sectionRestoreAlertsView, sectionClearCacheView, sectionBrowserExtView]
  }

  @IBOutlet var sectionDefaultAppView: NSView!
  @IBOutlet var sectionRestoreAlertsView: NSView!
  @IBOutlet var sectionClearCacheView: NSView!
  @IBOutlet var sectionBrowserExtView: NSView!
  @IBOutlet var setAsDefaultSheet: NSWindow!
  @IBOutlet weak var setAsDefaultVideoCheckBox: NSButton!
  @IBOutlet weak var setAsDefaultAudioCheckBox: NSButton!
  @IBOutlet weak var setAsDefaultPlaylistCheckBox: NSButton!
  @IBOutlet weak var thumbCacheSizeLabel: NSTextField!
  @IBOutlet weak var savedPlaybackProgressClearedLabel: NSTextField!
  @IBOutlet weak var playHistoryClearedLabel: NSTextField!
  @IBOutlet weak var restoreAlertsRestoredLabel: NSTextField!

  override func viewDidLoad() {
    super.viewDidLoad()

    DispatchQueue.main.async {
      self.updateThumbnailCacheStat()
    }
  }

  private func updateThumbnailCacheStat() {
    thumbCacheSizeLabel.stringValue = "\(FloatingPointByteCountFormatter.string(fromByteCount: CacheManager.shared.getCacheSize(), countStyle: .binary))B"
  }

  @IBAction func setIINAAsDefaultAction(_ sender: Any) {
    view.window!.beginSheet(setAsDefaultSheet)
  }

  @IBAction func setAsDefaultOKBtnAction(_ sender: Any) {

    guard
      let utiImportedTypes = Bundle.main.infoDictionary?["UTImportedTypeDeclarations"] as? [[String: Any]]
      else { return }

    Logger.log("Setting this app as default")

    let utiChecked = [
      "public.movie": setAsDefaultVideoCheckBox.state == .on,
      "public.audio": setAsDefaultAudioCheckBox.state == .on,
      "public.text": setAsDefaultPlaylistCheckBox.state == .on
    ]

    guard let utiTargetSet = DefaultApplicationSetter.targetIdentifiers(
      utiImportedTypes: utiImportedTypes,
      checkedCategories: utiChecked
    ) else { return }

    DefaultApplicationSetter.setAsDefault(identifiers: utiTargetSet) { [weak self] successCount, failedCount in
      guard let self else { return }
      Utility.showAlert("set_default.success", arguments: [successCount, failedCount], style: .informational,
                        sheetWindow: self.view.window)
      self.view.window!.endSheet(self.setAsDefaultSheet)
    }
  }

  @IBAction func setAsDefaultCancelBtnAction(_ sender: Any) {
    view.window!.endSheet(setAsDefaultSheet)
  }

  @IBAction func resetSuppressedAlertsBtnAction(_ sender: Any) {
    Utility.quickAskPanel("restore_alerts", sheetWindow: view.window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      // This operation used to restore an alert about preventing display sleeping failing. That
      // alert has been removed so at this time we do not have any alerts that can be suppressed.
      // That might change in the future, so for now we are retaining this operation.
      self.restoreAlertsRestoredLabel.isHidden = false
    }
  }

  @IBAction func clearWatchLaterBtnAction(_ sender: Any) {
    Utility.quickAskPanel("clear_watch_later", sheetWindow: view.window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      try? FileManager.default.removeItem(atPath: Utility.watchLaterURL.path)
      Utility.createDirIfNotExist(url: Utility.watchLaterURL)
      self.savedPlaybackProgressClearedLabel.isHidden = false
    }
  }

  @IBAction func clearHistoryBtnAction(_ sender: Any) {
    Utility.quickAskPanel("clear_history", sheetWindow: view.window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      try? FileManager.default.removeItem(atPath: Utility.playbackHistoryURL.path)
      AppDelegate.shared.clearRecentDocuments(self)
      Preference.set(nil, for: .iinaLastPlayedFilePath)
      self.playHistoryClearedLabel.isHidden = false
    }
  }

  @IBAction func clearCacheBtnAction(_ sender: Any) {
    Utility.quickAskPanel("clear_cache", sheetWindow: view.window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      try? FileManager.default.removeItem(atPath: Utility.thumbnailCacheURL.path)
      Utility.createDirIfNotExist(url: Utility.thumbnailCacheURL)
      self.updateThumbnailCacheStat()
    }
  }

  @IBAction func extChromeBtnAction(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.chromeExtensionLink)!)
  }

  @IBAction func extFirefoxBtnAction(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.firefoxExtensionLink)!)
  }
}
