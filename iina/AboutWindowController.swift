//
//  AboutWindowController.swift
//  iina
//
//  Created by lhc on 31/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import Just

fileprivate extension NSUserInterfaceItemIdentifier {
  static let dataSourceItem = NSUserInterfaceItemIdentifier(rawValue: "dataSourceItem")
}

struct Contributor: Decodable {
  let username: String
  let avatarURL: String

  enum CodingKeys: String, CodingKey {
    case username = "login"
    case avatarURL = "avatar_url"
  }
}

class AboutWindowController: NSWindowController {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("AboutWindowController")
  }

  @IBOutlet weak var windowBackgroundBox: NSBox!
  @IBOutlet weak var iconImageView: NSImageView!
  @IBOutlet weak var iinaLabel: NSTextField! {
    didSet {
      iinaLabel.font = NSFont.systemFont(ofSize: 24, weight: .light)
    }
  }
  @IBOutlet weak var versionLabel: NSTextField!
  @IBOutlet weak var mpvVersionLabel: NSTextField!
  @IBOutlet var detailTextView: NSTextView!
  @IBOutlet var creditsTextView: NSTextView!

  @IBOutlet weak var licenseButton: AboutWindowButton!
  @IBOutlet weak var contributorsButton: AboutWindowButton!
  @IBOutlet weak var creditsButton: AboutWindowButton!
  @IBOutlet weak var tabView: NSTabView!
  @IBOutlet weak var contributorsCollectionView: NSCollectionView!
  @IBOutlet weak var contributorsCollectionViewHeightConstraint: NSLayoutConstraint!
  @IBOutlet weak var contributorsFooterView: NSVisualEffectView!
  @IBOutlet weak var contributorsFooterImage: NSImageView!
  @IBOutlet weak var translatorsTableView: NSTableView!

  private lazy var contributors = getContributors()
  private lazy var translators = loadTraslators()

  override func windowDidLoad() {
    super.windowDidLoad()

    window?.titlebarAppearsTransparent = true
    window?.titleVisibility = .hidden

    windowBackgroundBox.fillColor = .windowBackgroundColor
    iconImageView.image = NSApp.applicationIconImage

    let (version, build) = Utility.iinaVersion()
    versionLabel.stringValue = "\(version) Build \(build)"
    // let copyright = infoDic["NSHumanReadableCopyright"] as! String

    mpvVersionLabel.stringValue = PlayerCore.active.mpv.mpvVersion

    if let contrubutionFile = Bundle.main.path(forResource: "Contribution", ofType: "rtf") {
      detailTextView.readRTFD(fromFile: contrubutionFile)
      detailTextView.textColor = NSColor.secondaryLabelColor
    }

    if let creditsFile = Bundle.main.path(forResource: "Credits", ofType: "rtf") {
      creditsTextView.readRTFD(fromFile: creditsFile)
      creditsTextView.textColor = NSColor.secondaryLabelColor
    }

    contributorsCollectionView.dataSource = self
    contributorsCollectionView.backgroundColors = [.clear]
    contributorsCollectionView.register(AboutWindowContributorAvatarItem.self, forItemWithIdentifier: .dataSourceItem)

    let image = NSImage(size: contributorsFooterView.frame.size)
    let rect = CGRect(origin: .zero, size: contributorsFooterView.frame.size)
    image.lockFocus()
    let loc: [CGFloat] = [0, 0.3, 0.6, 0.8, 1]
    let colors: [CGFloat] = [1, 0.95, 0.8, 0.05, 0]
    let gradient = NSGradient(colors: colors.map { NSColor(white: 0.925, alpha: $0) }, atLocations: loc, colorSpace: .deviceGray)
    gradient!.draw(in: rect, angle: 90)
    image.unlockFocus()
    if #available(macOS 10.14, *) {
      contributorsFooterView.material = .windowBackground
      contributorsFooterView.maskImage = image
    } else {
      contributorsFooterView.isHidden = true
      contributorsFooterImage.image = image
      contributorsFooterImage.isHidden = false
    }

    contributorsCollectionView.enclosingScrollView?.contentInsets.bottom = contributorsFooterView.frame.height * loc[colors.firstIndex(of: 0)! - 1]

    translatorsTableView.dataSource = self
    translatorsTableView.delegate = self
  }

  @IBAction func sectionBtnAction(_ sender: NSButton) {
    tabView.selectTabViewItem(at: sender.tag)
    [licenseButton, contributorsButton, creditsButton].forEach {
      $0?.state = $0 == sender ? .on : .off
      $0?.updateState()
    }
  }

  @IBAction func contributorsBtnAction(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.contributorsLink)!)
  }
}

extension AboutWindowController: NSCollectionViewDataSource {
  func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
    return contributors.count
  }

  func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
    let item = contributorsCollectionView.makeItem(withIdentifier: .dataSourceItem, for: indexPath) as! AboutWindowContributorAvatarItem
    item.imageView?.image = nil
    guard let contributor = contributors[at: indexPath.item] else { return item }
    item.avatarURL = contributor.avatarURL
    return item
  }

  private func getContributors() -> [Contributor] {
    // This method will be called only once when `self.contributors` is needed,
    // i.e. when `contributorsCollectionView` is being initialized.
    loadContributors(from: "https://api.github.com/repos/iina/iina/contributors")
    return []
  }

  private func loadContributors(from url: String) {
    Just.get(url, asyncCompletionHandler: { response in
      let prevCount = self.contributors.count
      guard let data = response.content,
        let contributors = try? JSONDecoder().decode([Contributor].self, from: data) else {
          DispatchQueue.main.async {
            self.contributorsCollectionViewHeightConstraint.constant = 24
          }
          return
      }
      self.contributors.append(contentsOf: contributors)
      // avoid possible crash
      guard self.contributors.count > prevCount else { return }
      let insertIndices = ([Int](prevCount..<self.contributors.count)).map {
        IndexPath(item: $0, section: 0)
      }
      DispatchQueue.main.sync {
        self.contributorsCollectionView.insertItems(at: Set(insertIndices))
      }
      if let nextURL = response.links["next"]?["url"] {
        self.loadContributors(from: nextURL)
      }
    })
  }
}

fileprivate extension NSUserInterfaceItemIdentifier {
  static let langColumn = NSUserInterfaceItemIdentifier("LangColumn")
  static let langCell = NSUserInterfaceItemIdentifier("LangCell")
  static let translatorColumn = NSUserInterfaceItemIdentifier("TranslatorColumn")
  static let translatorCell = NSUserInterfaceItemIdentifier("TranslatorCell")
}

fileprivate let identifierMap: [NSUserInterfaceItemIdentifier: NSUserInterfaceItemIdentifier] = [
  .langColumn: .langCell,
  .translatorColumn: .translatorCell
]

extension AboutWindowController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    return translators.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    return translators[at: row]
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard
      let translatorInfo = translators[at: row],
      let tableColumn = tableColumn,
      let identifier = identifierMap[tableColumn.identifier],
      let view = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
      else { return nil }
    if identifier == .langCell {
      view.textField!.stringValue = translatorInfo["lang"]!
    } else {
      view.textField!.setHTMLValue(translatorInfo["translator"]!)
    }
    return view
  }

  private func loadTraslators() -> [[String: String]] {
    let locale = NSLocale.current
    var result: [[String: String]] = []

    let languages = Translator.all.keys.sorted()

    for langCode in languages {
      let translators = Translator.all[langCode]!
      let splitted = langCode.split(separator: "-").map(String.init)
      let baseLangCode = locale.localizedString(forLanguageCode: splitted[0]) ?? ""
      let language: String
      if splitted.count == 1 {
        language = baseLangCode
      } else {
        let desc = locale.localizedString(forScriptCode: splitted[1]) ??
          locale.localizedString(forRegionCode: splitted[1]) ?? ""
        language = "\(baseLangCode) (\(desc))"
      }
      for (index, translator) in translators.enumerated() {
        let urlString = translator.url == nil ? nil : "(<a href=\"\(translator.url!)\">\(translator.title!)</a>)"
        let emailString = translator.email == nil ? nil : "<a href=\"mailto:\(translator.email!)\">\(translator.email!)</a>"
        result.append([
          "lang": index == 0 ? language : "",
          "translator": ["\(translator.name)", urlString, emailString].compactMap { $0 }.joined(separator: " ")
          ])
      }
    }
    return result
  }
}

class AboutWindowButton: NSButton {

  override func awakeFromNib() {
    wantsLayer = true
    layer?.cornerRadius = 4
    updateState()
  }

  func updateState() {
    if let cell = self.cell as? NSButtonCell {
      if #available(macOS 10.14, *) {
        cell.backgroundColor = state == .on ? .controlAccentColor : .clear
      } else {
        layer?.backgroundColor = state == .on ? CGColor(red: 0.188, green: 0.482, blue: 0.965, alpha: 1) : .clear
      }
    }
    // Workground for macOS 10.13-
    // For some reason the text alignment setting will lost after setting in layer
    // Remove paragraph settings when dropping macOS 10.13 support
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    attributedTitle = NSAttributedString(string: title,
                                         attributes: [.foregroundColor: state == .on ? NSColor.white : NSColor.labelColor, .paragraphStyle: paragraph])
  }
}
