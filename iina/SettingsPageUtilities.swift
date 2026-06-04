//
//  SettingsPageUtilities.swift
//  iina
//
//  Created by Hechen Li on 2026-02-02.
//  Copyright © 2026 lhc. All rights reserved.
//

import UniformTypeIdentifiers
import SafariServices.SFSafariApplication

class SettingsPageUtilities: SettingsPage {
  override var identifier: String {
    "utilities"
  }

  override var title: String {
    return NSLocalizedString("preference.utilities", comment: "Utilities")
  }

  override var image: NSImage {
    return .sf("wrench.and.screwdriver", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsUtilsLocalizable"
  }

  private lazy var setAsDefaultSheet = SetAsDefaultSheetWindow(l10n: localizationContext)
  private lazy var browserExtensionView = BrowserExtensionView(l10n: localizationContext)
  private lazy var thumbCacheSizeLabel: NSTextField = makeLabel()

  override func content() -> [SettingsSection] {
    return sections {
      section {
        SettingsList(title: .text_DefaultApplication) {
          SettingsItem.General(title: .text_SetIINAAsTheDefault)
            .image(name: ["app.badge.checkmark.fill", "app"])
            .extraViews(actionButton(action: #selector(setIINAAsDefaultAction)))
        }
      }
      section {
        SettingsList(title: .text_RestoreAlerts) {
          SettingsItem.General(title: .text_RestoreSuppressedAlerts)
            .image(name: "arrow.counterclockwise")
            .extraViews(actionButton(action: #selector(resetSuppressedAlertsBtnAction)))
            .hasDescription(content: .text_RestoreAllAlertsThat)
        }
      }
      section {
        SettingsList(title: .text_ClearCache) {
          SettingsItem.General(title: .text_ClearSavedPlaybackProgress)
            .image(name: "clock")
            .extraViews(actionButton(action: #selector(clearWatchLaterBtnAction), symbolName: ["trash"]))
            .hasDescription(content: .text_DeleteAllWatchLater)
          SettingsItem.General(title: .text_ClearPlaybackHistory)
            .image(name: ["document.badge.clock", "doc.badge.clock", "doc"])
            .extraViews(thumbCacheSizeLabel, actionButton(action: #selector(clearCacheBtnAction), symbolName: ["trash"]))
            .hasDescription(content: .text_DeleteAllPlaybackHistories)
          SettingsItem.General(title: .text_ClearThumbnailCache)
            .image(name: "photo")
            .extraViews(thumbCacheSizeLabel, actionButton(action: #selector(clearCacheBtnAction), symbolName: ["trash"]))
        }
      }
      section {
        SettingsList(title: .text_BrowserExtensions) {
          SettingsItem.General(title: .text_GetBrowserExtensionsForIINA)
            .image(name: "globe")
            .hasDescription(content: .text_OpenLinksOrCurrentWebpage)
            .withDetailView(browserExtensionView)
        }
      }
    }
  }

  private func actionButton(action: Selector, symbolName: [String] = []) -> NSButton {
    return NSButton(title: "", image: .sf(symbolName + ["arrow.right"])!, target: self, action: action)
  }

  private func updateThumbnailCacheStat() {
    thumbCacheSizeLabel.stringValue = "\(FloatingPointByteCountFormatter.string(fromByteCount: CacheManager.shared.getCacheSize(), countStyle: .binary))B"
  }

  override init () {
    super.init()
    self.updateThumbnailCacheStat()
  }

  @objc func setIINAAsDefaultAction(_ sender: Any) {
    guard let window = (sender as? NSView)?.window else { return }
    setAsDefaultSheet.contextWindow = window
    window.beginSheet(setAsDefaultSheet)
  }


  @objc func resetSuppressedAlertsBtnAction(_ sender: Any) {
    guard let window = (sender as? NSView)?.window else { return }
    Utility.quickAskPanel("restore_alerts", sheetWindow: window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      // This operation used to restore an alert about preventing display sleeping failing. That
      // alert has been removed so at this time we do not have any alerts that can be suppressed.
      // That might change in the future, so for now we are retaining this operation.
      Utility.showAlert("restored", style: .informational, sheetWindow: window)
    }
  }

  @objc func clearWatchLaterBtnAction(_ sender: Any) {
    guard let window = (sender as? NSView)?.window else { return }
    Utility.quickAskPanel("clear_watch_later", sheetWindow: window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      do {
        try FileManager.default.removeItem(atPath: Utility.watchLaterURL.path)
        Utility.createDirIfNotExist(url: Utility.watchLaterURL)
        Utility.showAlert("cleared", style: .informational, sheetWindow: window)
      } catch {
        Utility.showAlert("custom", arguments: ["\(error)"], style: .critical, sheetWindow: window)
      }
    }
  }

  @objc func clearHistoryBtnAction(_ sender: Any) {
    guard let window = (sender as? NSView)?.window else { return }
    Utility.quickAskPanel("clear_history", sheetWindow: window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      try? FileManager.default.removeItem(atPath: Utility.playbackHistoryURL.path)
      AppDelegate.shared.clearRecentDocuments(self)
      Preference.set(nil, for: .iinaLastPlayedFilePath)
      Utility.showAlert("cleared", style: .informational, sheetWindow: window)
    }
  }

  @objc func clearCacheBtnAction(_ sender: Any) {
    guard let window = (sender as? NSView)?.window else { return }
    Utility.quickAskPanel("clear_cache", sheetWindow: window) { respond in
      guard respond == .alertFirstButtonReturn else { return }
      ThumbnailCache.clearThumbnailCache()
      self.updateThumbnailCacheStat()
    }
  }
}

fileprivate func makeLabel() -> NSTextField {
  let tf = NSTextField(labelWithString: "")
  tf.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
  tf.textColor = .secondaryLabelColor
  return tf
}

fileprivate class SetAsDefaultSheetWindow: NSWindow {
  var contextWindow: NSWindow!

  private let label: NSTextField
  private let okButton: NSButton
  private let cancelButton: NSButton

  private let videoCheckBox: NSButton
  private let audioCheckBox: NSButton
  private let playListCheckBox: NSButton

  init(l10n: SettingsLocalization.Context) {
    let style: NSWindow.StyleMask = [.titled, .resizable, .fullSizeContentView]

    self.okButton = NSButton(title: l10n.localized(.text_OK), target: nil, action: nil)
    okButton.translatesAutoresizingMaskIntoConstraints = false
    self.cancelButton = NSButton(title: l10n.localized(.text_Cancel), target: nil, action: nil)
    cancelButton.translatesAutoresizingMaskIntoConstraints = false
    self.label = NSTextField(labelWithString: l10n.localized(.text_PleaseSelectTheMediaTypes))
    self.videoCheckBox = NSButton(title: l10n.localized(.text_Video), target: nil, action: nil)
    self.audioCheckBox = NSButton(title: l10n.localized(.text_Audio), target: nil, action: nil)
    self.playListCheckBox = NSButton(title: l10n.localized(.text_Playlist), target: nil, action: nil)
    [videoCheckBox, audioCheckBox, playListCheckBox].forEach {
      $0.setButtonType(.switch)
      $0.state = .on
    }

    super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 150),
               styleMask: style,
               backing: .buffered,
               defer: false)

    okButton.target = self
    okButton.action = #selector(okBtnAction)
    cancelButton.target = self
    cancelButton.action = #selector(cancelBtnAction)

    let stackView = NSStackView(views: [label, videoCheckBox, audioCheckBox, playListCheckBox])
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.spacing = 8
    stackView.alignment = .leading

    contentView?.addSubview(stackView)
    contentView?.addSubview(okButton)
    contentView?.addSubview(cancelButton)

    stackView.padding(.leading(24), .trailing(24), .top(24))
      .spacing(.bottom(16), to: okButton)
    cancelButton.center(.y, with: okButton)
    okButton.padding(.bottom(24), .trailing(24))
      .spacing(.leading(8), to: cancelButton)
  }

  @objc func okBtnAction(_ sender: Any) {
    guard let window = contextWindow else { return }
    guard
      let utiImportedTypes = Bundle.main.infoDictionary?["UTImportedTypeDeclarations"] as? [[String: Any]],
      let cfBundleID = Bundle.main.bundleIdentifier as CFString?
      else { return }

    Logger.log("Setting this app as default")

    var successCount = 0
    var failedCount = 0

    let utiChecked = [
      "public.movie": videoCheckBox.state == .on,
      "public.audio": audioCheckBox.state == .on,
      "public.text": playListCheckBox.state == .on
    ]

    var utiTargetSet: Set<String> = []
    for utiImportedType in utiImportedTypes {
      guard
        let identifier = utiImportedType["UTTypeIdentifier"] as? String,
        let conformsTo = utiImportedType["UTTypeConformsTo"] as? [String],
        let tagSpec = utiImportedType["UTTypeTagSpecification"] as? [String: Any],
        let exts = tagSpec["public.filename-extension"] as? [String]
      else {
        return
      }

      // make sure that `conformsTo` contains a checked UTI type
      guard utiChecked.map({ (uti, checked) in checked && conformsTo.contains(uti) }).contains(true) else {
        continue
      }

      Logger.log("UTImportedType: \(identifier.quoted) ➤ \(exts)", level: .verbose)
      for ext in exts {
        let uttypesForExt = UTType.types(tag: ext, tagClass: .filenameExtension, conformingTo: nil)
        for uttype in uttypesForExt {
          utiTargetSet.insert(uttype.identifier)
        }
      }
    }

    for identifier in utiTargetSet {
      Logger.log("Setting default for UTI: \(identifier.quoted)", level: .verbose)
      let status = LSSetDefaultRoleHandlerForContentType(identifier as CFString, .all, cfBundleID)
      if status == kOSReturnSuccess {
        successCount += 1
      } else {
        Logger.log("Failed for \(identifier.quoted): return value \(status)", level: .error)
        failedCount += 1
      }
    }

    Utility.showAlert("set_default.success", arguments: [successCount, failedCount], style: .informational,
                      sheetWindow: window)
    window.endSheet(self)
  }

  @objc func cancelBtnAction(_ sender: Any) {
    guard let window = contextWindow else { return }
    window.endSheet(self)
  }
}

fileprivate class BrowserExtensionView: SettingsAccessory.Base {
  func linkButton(_ key: SettingsLocalization.Key, _ selector: Selector, _ symbolName: [String] = []) -> NSButton {
    let button = ui.button(key)
    button.image = .sf(symbolName + ["square.and.arrow.down"])
    button.imagePosition = .imageTrailing
    button.target = self
    button.action = selector
    return button
  }

  override init(l10n: SettingsLocalization.Context) {
    super.init(l10n: l10n)

    let chromeBtn = linkButton(.text_Chrome, #selector(extChromeBtnAction))
    let firefoxBtn = linkButton(.text_Firefox, #selector(extFirefoxBtnAction))
    let safariBtn = linkButton(.text_Safari, #selector(extSafariBtnAction), ["safari"])
    let stackView = ui.hStack(safariBtn, chromeBtn, firefoxBtn)
    view.addSubview(stackView)
    stackView.padding(.top(0), .bottom(16), .leading(SettingsSubList.indent), .trailing(8))
  }

  @objc func extChromeBtnAction(_ sender: Any) {
    NSWorkspace.shared.open([URL(string: AppData.chromeExtensionLink)!], withApplicationAt: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") ?? NSWorkspace.shared.urlForApplication(toOpen: URL(string: "http://")!)!, configuration: NSWorkspace.OpenConfiguration())
  }

  @objc func extFirefoxBtnAction(_ sender: Any) {
    NSWorkspace.shared.open([URL(string: AppData.firefoxExtensionLink)!], withApplicationAt: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.mozilla.firefox") ?? NSWorkspace.shared.urlForApplication(toOpen: URL(string: "http://")!)!, configuration: NSWorkspace.OpenConfiguration())
  }

  @objc func extSafariBtnAction() {
    SFSafariApplication.showPreferencesForExtension(withIdentifier: "com.colliderli.iina.OpenInIINA")
  }
}
