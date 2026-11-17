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
  let avatarURL: String

  enum CodingKeys: String, CodingKey {
    case avatarURL = "avatar_url"
  }
}

fileprivate let ui = UIHelper(scope: "about")

class AboutWindowController: NSWindowController {
  private let windowBackgroundBox = NSBox()
  private let iconImageView = NSImageView()
  private let iinaLabel = NSTextField(labelWithString: "IINA")
  private let versionLabel = NSTextField(labelWithString: "")
  private let mpvVersionLabel = NSTextField(labelWithString: "")
  private let ffmpegVersionLabel = NSTextField(labelWithString: "")
  private let buildView = NSView()
  private let buildBranchButton = NSButton(title: "", target: nil, action: nil)
  private let buildDateLabel = NSTextField(labelWithString: "")

  private var detailTextView: NSTextView!
  private var creditsTextView: NSTextView!

  private let licenseButton = AboutWindowButton()
  private let contributorsButton = AboutWindowButton()
  private let creditsButton = AboutWindowButton()
  private let tabView = NSTabView()
  private let contributorsCollectionView = NSCollectionView()
  private let contributorsFooterView = NSVisualEffectView()

  private lazy var contributors = getContributors()

  init() {
    let window = CommonWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
      styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = ui.localized("title")
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    super.init(window: window)
    setupViews()
    window.center()

    iconImageView.image = NSApp.applicationIconImage

    let (version, build) = InfoDictionary.shared.version
    versionLabel.stringValue = "\(version) Build \(build)"

    mpvVersionLabel.stringValue = MPVOptionDefaults.shared.mpvVersion
    ffmpegVersionLabel.stringValue = "FFmpeg \(String(cString: av_version_info()))"

    // Use a localized date for the build date.
    let toString = DateFormatter()
    toString.dateStyle = .medium
    toString.timeStyle = .medium

    switch InfoDictionary.shared.buildType {
    case .nightly:
      if let buildDate = InfoDictionary.shared.buildDate,
         let buildSHA = InfoDictionary.shared.shortCommitSHA {
        buildDateLabel.stringValue = toString.string(from: buildDate)
        buildDateLabel.isHidden = false
        buildBranchButton.title = "NIGHTLY " + buildSHA
        buildBranchButton.action = #selector(self.openCommitLink)
        buildBranchButton.isHidden = false
      }
    case .debug:
      if let buildDate = InfoDictionary.shared.buildDate,
         let buildBranch = InfoDictionary.shared.buildBranch,
         let buildSHA = InfoDictionary.shared.shortCommitSHA {
        buildDateLabel.stringValue = toString.string(from: buildDate)
        buildDateLabel.isHidden = false
        buildBranchButton.title = buildBranch + " " + buildSHA
        buildBranchButton.action = #selector(self.openCommitLink)
        buildBranchButton.isHidden = false
      }
    default:
      break
    }

    if let contributionFile = Bundle.main.path(forResource: "Contribution", ofType: "rtf") {
      detailTextView.readRTFD(fromFile: contributionFile)
      detailTextView.textColor = NSColor.secondaryLabelColor
    }

    if let creditsFile = Bundle.main.path(forResource: "Credits", ofType: "rtf") {
      creditsTextView.readRTFD(fromFile: creditsFile)
      creditsTextView.textColor = NSColor.secondaryLabelColor
    }

    contributorsCollectionView.dataSource = self
    contributorsCollectionView.backgroundColors = [.clear]
    contributorsCollectionView.register(AboutWindowContributorAvatarItem.self, forItemWithIdentifier: .dataSourceItem)

    // Frames are not laid out yet, so use the footer's fixed size (tab view width x footer height)
    let footerSize = NSSize(width: 400, height: 60)
    let image = NSImage(size: footerSize)
    let rect = CGRect(origin: .zero, size: footerSize)
    image.lockFocus()
    let loc: [CGFloat] = [0, 0.3, 0.6, 0.8, 1]
    let colors: [CGFloat] = [1, 0.95, 0.8, 0.05, 0]
    let gradient = NSGradient(colors: colors.map { NSColor(white: 0.925, alpha: $0) }, atLocations: loc, colorSpace: .deviceGray)
    gradient!.draw(in: rect, angle: 90)
    image.unlockFocus()
    contributorsFooterView.material = .windowBackground
    contributorsFooterView.maskImage = image

    contributorsCollectionView.enclosingScrollView?.contentInsets.bottom = footerSize.height * loc[colors.firstIndex(of: 0)! - 1]
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupViews() {
    guard let contentView = window?.contentView else { return }

    windowBackgroundBox.translatesAutoresizingMaskIntoConstraints = false
    windowBackgroundBox.boxType = .custom
    windowBackgroundBox.borderWidth = 0
    windowBackgroundBox.titlePosition = .noTitle
    windowBackgroundBox.fillColor = .windowBackgroundColor
    contentView.addSubview(windowBackgroundBox)
    windowBackgroundBox.padding(.all)
    let boxContentView = windowBackgroundBox.contentView!

    // Sidebar

    let sidebar = NSView()
    sidebar.translatesAutoresizingMaskIntoConstraints = false
    boxContentView.addSubview(sidebar)
    sidebar.padding(.top, .leading, .bottom).size(width: 220)

    iconImageView.translatesAutoresizingMaskIntoConstraints = false
    iconImageView.imageScaling = .scaleProportionallyDown
    sidebar.addSubview(iconImageView)
    iconImageView.padding(.top(40)).size(width: 80, height: 80).center(.x)

    iinaLabel.translatesAutoresizingMaskIntoConstraints = false
    iinaLabel.font = NSFont.systemFont(ofSize: 24, weight: .light)
    sidebar.addSubview(iinaLabel)
    iinaLabel.spacing(.top(8), to: iconImageView).center(.x)

    versionLabel.translatesAutoresizingMaskIntoConstraints = false
    versionLabel.isSelectable = true
    versionLabel.textColor = .secondaryLabelColor
    versionLabel.alignment = .center
    sidebar.addSubview(versionLabel)
    versionLabel.spacing(.top(8), to: iinaLabel).center(.x)

    let miniFont = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .mini))
    for label in [mpvVersionLabel, ffmpegVersionLabel, buildDateLabel] {
      label.translatesAutoresizingMaskIntoConstraints = false
      label.controlSize = .mini
      label.font = miniFont
      label.textColor = .secondaryLabelColor
      label.isSelectable = true
    }
    mpvVersionLabel.alignment = .right
    ffmpegVersionLabel.alignment = .left
    let versionStack = ui.hStack(align: .top, spacing: 6, mpvVersionLabel, ffmpegVersionLabel)
    sidebar.addSubview(versionStack)
    versionStack.spacing(.top(4), to: versionLabel).center(.x)

    buildView.translatesAutoresizingMaskIntoConstraints = false
    sidebar.addSubview(buildView)
    buildView.spacing(.top(4), to: versionStack).padding(.bottom(150)).size(width: 180, height: 48).center(.x)

    buildDateLabel.alignment = .center
    buildDateLabel.isHidden = true
    buildView.addSubview(buildDateLabel)
    buildDateLabel.padding(.top, .horizontal)

    buildBranchButton.translatesAutoresizingMaskIntoConstraints = false
    buildBranchButton.bezelStyle = .roundRect
    buildBranchButton.isBordered = false
    buildBranchButton.controlSize = .mini
    buildBranchButton.font = miniFont
    buildBranchButton.target = self
    buildBranchButton.isHidden = true
    buildView.addSubview(buildBranchButton)
    buildBranchButton.spacing(.top(4), to: buildDateLabel).center(.x)

    var prevView: NSView = buildView
    for (index, (button, key)) in [(licenseButton, "license"), (contributorsButton, "contributors"), (creditsButton, "credits")].enumerated() {
      button.translatesAutoresizingMaskIntoConstraints = false
      button.title = ui.localized(key)
      button.tag = index
      button.state = index == 0 ? .on : .off
      button.target = self
      button.action = #selector(sectionBtnAction(_:))
      button.updateState()
      sidebar.addSubview(button)
      button.padding(.leading(lessThan: 40), .trailing(lessThan: 40))
        .spacing(.top(index == 0 ? 8 : 10), to: prevView)
        .center(.x)
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
      prevView = button
    }

    // Tab view

    tabView.translatesAutoresizingMaskIntoConstraints = false
    tabView.tabViewType = .noTabsNoBorder
    boxContentView.addSubview(tabView)
    tabView.padding(.top(36), .trailing(20), .bottom(20))
    tabView.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor).isActive = true

    let (licenseScrollView, licenseTextView) = makeTextScrollView(hasVerticalScroller: false)
    detailTextView = licenseTextView
    tabView.addTabViewItem(makeTabViewItem(key: "license", content: licenseScrollView))

    tabView.addTabViewItem(makeTabViewItem(key: "contributors", content: makeContributorsView()))

    let (creditsScrollView, creditsTextView) = makeTextScrollView(hasVerticalScroller: true)
    self.creditsTextView = creditsTextView
    tabView.addTabViewItem(makeTabViewItem(key: "credits", content: creditsScrollView))
  }

  private func makeTabViewItem(key: String, content: NSView) -> NSTabViewItem {
    let item = NSTabViewItem()
    item.label = ui.localized(key)
    let view = NSView()
    view.addSubview(content)
    content.padding(.all)
    item.view = view
    return item
  }

  private func makeTextScrollView(hasVerticalScroller: Bool) -> (NSScrollView, NSTextView) {
    let scrollView = NSTextView.scrollableTextView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = hasVerticalScroller
    let textView = scrollView.documentView as! NSTextView
    textView.isEditable = false
    textView.drawsBackground = false
    textView.importsGraphics = false
    return (scrollView, textView)
  }

  private func makeContributorsView() -> NSView {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false

    let layout = NSCollectionViewFlowLayout()
    layout.itemSize = NSSize(width: 32, height: 32)
    layout.minimumInteritemSpacing = 4
    layout.minimumLineSpacing = 4
    contributorsCollectionView.collectionViewLayout = layout

    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = contributorsCollectionView
    view.addSubview(scrollView)
    scrollView.padding(.top, .horizontal(4))

    contributorsFooterView.translatesAutoresizingMaskIntoConstraints = false
    contributorsFooterView.blendingMode = .withinWindow
    contributorsFooterView.state = .followsWindowActiveState
    view.addSubview(contributorsFooterView)
    contributorsFooterView.padding(.horizontal).size(height: 60)
    contributorsFooterView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor).isActive = true

    let contributorsBtn = makeLinkButton("iina/contributors", action: #selector(contributorsBtnAction(_:)))
    view.addSubview(contributorsBtn)
    contributorsBtn.center(.x, with: contributorsFooterView)
    contributorsBtn.bottomAnchor.constraint(equalTo: contributorsFooterView.bottomAnchor, constant: -8).isActive = true

    let crowdinLabel = ui.label("crowdin", canCompress: false)
    view.addSubview(crowdinLabel)
    crowdinLabel.padding(.leading, .trailing(greaterThan: 0)).spacing(.top(8), to: scrollView)

    let translatorsBtn = makeLinkButton("Crowdin", action: #selector(translatorsBtnAction(_:)))
    view.addSubview(translatorsBtn)
    translatorsBtn.padding(.bottom).spacing(.top(20), to: crowdinLabel).center(.x)

    return view
  }

  private func makeLinkButton(_ title: String, action: Selector) -> NSButton {
    let btn = NSButton(title: title, target: self, action: action)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.bezelStyle = .inline
    btn.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
    btn.image = .sf("link", withConfiguration: .init(pointSize: 9, weight: .bold))
    btn.imagePosition = .imageLeft
    return btn
  }

  @objc func openCommitLink() {
    guard let commitSHA = InfoDictionary.shared.buildCommit else { return }
    NSWorkspace.shared.open(.init(string: "https://github.com/iina/iina/commit/\(commitSHA)")!)
  }

  @objc func sectionBtnAction(_ sender: NSButton) {
    tabView.selectTabViewItem(at: sender.tag)
    [licenseButton, contributorsButton, creditsButton].forEach {
      $0.state = $0 == sender ? .on : .off
      $0.updateState()
    }
  }

  @objc func contributorsBtnAction(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.contributorsLink)!)
  }

  @objc func translatorsBtnAction(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.crowdinMembersLink)!)
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

class AboutWindowButton: NSButton {

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setButtonType(.momentaryChange)
    bezelStyle = .shadowlessSquare
    isBordered = false
    lineBreakMode = .byTruncatingTail
    wantsLayer = true
    layer?.cornerRadius = 4
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateState() {
    if let cell = self.cell as? NSButtonCell {
      cell.backgroundColor = state == .on ? .controlAccentColor : .clear
    }
    attributedTitle = NSAttributedString(string: title,
                                         attributes: [.foregroundColor: state == .on ? NSColor.white : NSColor.labelColor])
  }
}
