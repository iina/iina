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
  @IBOutlet weak var contributorsFooterView: NSVisualEffectView!

  private lazy var contributors = getContributors()

  override func windowDidLoad() {
    super.windowDidLoad()

    // print(Translator.all)

    if #available(macOS 10.13, *) {
      windowBackgroundBox.fillColor = NSColor(named: .aboutWindowBackground)!
    } else {
      windowBackgroundBox.fillColor = .white
    }
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

    if #available(OSX 10.14, *) {
      contributorsFooterView.material = .windowBackground
    }
    let image = NSImage(size: contributorsFooterView.frame.size)
    let rect = CGRect(origin: .zero, size: contributorsFooterView.frame.size)
    image.lockFocus()
    let loc: [CGFloat] = [0, 0.3, 0.6, 0.8, 1]
    let colors: [CGFloat] = [1, 0.95, 0.8, 0.05, 0]
    let gradient = NSGradient(colors: colors.map { NSColor(white: 0, alpha: $0) }, atLocations: loc, colorSpace: .deviceGray)
    gradient!.draw(in: rect, angle: 90)
    image.unlockFocus()
    contributorsFooterView.maskImage = image
  }

  @IBAction func sectionBtnAction(_ sender: NSButton) {
    tabView.selectTabViewItem(at: sender.tag)
    [licenseButton, contributorsButton, creditsButton].forEach {
      $0?.state = $0 == sender ? .on : .off
      $0?.updateState()
    }
  }
}

extension AboutWindowController: NSCollectionViewDataSource {
  func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
    return contributors.count
  }

  func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
    let item = contributorsCollectionView.makeItem(withIdentifier: .dataSourceItem, for: indexPath) as! AboutWindowContributorAvatarItem
    guard let contributor = contributors[at: indexPath.item] else { return item }
    item.avatarURL = contributor.avatarURL
    return item
  }

  private func getContributors() -> [Contributor] {
    // This method will be called only once when `self.contributor` is needed,
    // i.e. when `contributorsCollectionView` is being initialized.
    loadContributors(from: "https://api.github.com/repos/lhc70000/iina/contributors")
    return []
  }

  private func loadContributors(from url: String) {
    Just.get(url) { response in
      guard let data = response.content,
        let contributors = try? JSONDecoder().decode([Contributor].self, from: data) else { return }
      self.contributors.append(contentsOf: contributors)
      DispatchQueue.main.sync {
        self.contributorsCollectionView.reloadData()
      }
      if let nextURL = response.links["next"]?["url"] {
        self.loadContributors(from: nextURL)
      }
    }
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
      if #available(OSX 10.14, *) {
        cell.backgroundColor = state == .on ? .controlAccentColor : .clear
      } else {
        cell.backgroundColor = state == .on ? .systemBlue : .clear
      }
    }
    attributedTitle = NSAttributedString(string: title,
                                         attributes: [.foregroundColor: state == .on ? NSColor.white : NSColor.labelColor])
  }
}
