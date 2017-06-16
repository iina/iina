//
//  PrefUIViewController.swift
//  iina
//
//  Created by lhc on 25/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import MASPreferences

class PrefUIViewController: NSViewController, MASPreferencesViewController {

  override var nibName: String {
    return "PrefUIViewController"
  }

  override var identifier: String? {
    get {
      return "ui"
    }
    set {
      super.identifier = newValue
    }
  }

  var toolbarItemImage: NSImage {
    get {
      return NSImage(named: "toolbar_play")!
    }
  }

  var toolbarItemLabel: String {
    get {
      view.layoutSubtreeIfNeeded()
      return NSLocalizedString("preference.ui", comment: "UI")
    }
  }

  var hasResizableWidth: Bool = false
  var hasResizableHeight: Bool = false

  @IBOutlet weak var oscPreviewImageView: NSImageView!
  @IBOutlet weak var oscPositionPopupButton: NSPopUpButton!
  @IBOutlet weak var thumbCacheSizeLabel: NSTextField!

  override func viewDidLoad() {
    super.viewDidLoad()
    oscPositionPopupBtnAction(oscPositionPopupButton)
  }

  @IBAction func oscPositionPopupBtnAction(_ sender: NSPopUpButton) {
    var name: String
    switch sender.selectedTag() {
    case 0:
      name = "osc_float"
    case 1:
      name = "osc_top"
    case 2:
      name = "osc_bottom"
    default:
      name = "osc_float"
    }
    oscPreviewImageView.image = NSImage(named: name)
  }

  @IBAction func clearCacheBtnAction(_ sender: AnyObject) {
    if Utility.quickAskPanel("clear_cache") {
      try? FileManager.default.removeItem(atPath: Utility.thumbnailCacheURL.path)
      updateThumbnailCacheStat()
      Utility.showAlert("clear_cache.success", style: .informational)
    }
  }

  override func viewDidAppear() {
    DispatchQueue.main.async {
      self.updateThumbnailCacheStat()
    }
  }

  private func updateThumbnailCacheStat() {
    var totalSize = 0
    if let contents = try? FileManager.default.contentsOfDirectory(at: Utility.thumbnailCacheURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
      for url in contents {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return }
        totalSize += size ?? 0
      }
    }
    thumbCacheSizeLabel.stringValue = FileSize.format(totalSize, unit: .b)
  }

}
