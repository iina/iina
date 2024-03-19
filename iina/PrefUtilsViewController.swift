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
    return NSImage(named: NSImage.Name("pref_utils"))!
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
      let utiTypes = Bundle.main.infoDictionary?["UTImportedTypeDeclarations"] as? [[String: Any]],
      let cfBundleID = Bundle.main.bundleIdentifier as CFString?
      else { return }

    Logger.log("Set self as default")

    var successCount = 0
    var failedCount = 0

    let utiChecked = [
      "public.movie": setAsDefaultVideoCheckBox.state == .on,
      "public.audio": setAsDefaultAudioCheckBox.state == .on,
      "public.text": setAsDefaultPlaylistCheckBox.state == .on
    ]

    for utiType in utiTypes {
      guard
        let conformsTo = utiType["UTTypeConformsTo"] as? [String],
        let tagSpec = utiType["UTTypeTagSpecification"] as? [String: Any],
        let exts = tagSpec["public.filename-extension"] as? [String]
        else {
          return
      }

      // make sure that `conformsTo` contains a checked UTI type
      guard utiChecked.map({ (uti, checked) in checked && conformsTo.contains(uti) }).contains(true) else {
        continue
      }

      for ext in exts {
        let utiString = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)!.takeUnretainedValue()
        let status = LSSetDefaultRoleHandlerForContentType(utiString, .all, cfBundleID)
        if status == kOSReturnSuccess {
          successCount += 1
        } else {
          Logger.log("failed for \(ext): return value \(status)", level: .error)
          failedCount += 1
        }
      }
    }

    Utility.showAlert("set_default.success", arguments: [successCount, failedCount], style: .informational,
                      sheetWindow: view.window)
    view.window!.endSheet(setAsDefaultSheet)
  }

  @IBAction func setAsDefaultCancelBtnAction(_ sender: Any) {
    view.window!.endSheet(setAsDefaultSheet)
  }

  @IBAction func resetSuppressedAlertsBtnAction(_ sender: Any) {
    Utility.quickAskPanel("restore_alerts", sheetWindow: view.window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      Preference.set(false, for: .suppressCannotPreventDisplaySleep)
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
