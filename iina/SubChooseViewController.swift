//
//  SubChooseViewController.swift
//  iina
//
//  Created by Collider LI on 4/3/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

fileprivate let ui = UIHelper(scope: "osd.sub_choose")
fileprivate let subCellIdentifier = NSUserInterfaceItemIdentifier("SubCell")

class SubChooseViewController: NSViewController {
  let tableView = NSTableView()
  private var downloadBtn: NSButton!

  var subtitles: [OnlineSubtitle] = []

  var userDoneAction: (([OnlineSubtitle]) -> Void)?
  var userCanceledAction: (() -> Void)?

  var context: Any?

  override func loadView() {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    self.view = view

    let promptLabel = ui.label("prompt", isSecondary: true)
    view.addSubview(promptLabel)
    promptLabel.padding(.top, .horizontal)

    let column = NSTableColumn()
    column.width = 468
    column.minWidth = 40
    column.maxWidth = 2000
    column.resizingMask = [.autoresizingMask, .userResizingMask]
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.style = .fullWidth
    tableView.rowHeight = 50
    tableView.intercellSpacing = NSSize(width: 3, height: 2)
    tableView.backgroundColor = NSColor(white: 1, alpha: 0.05)
    tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    tableView.allowsColumnReordering = false
    tableView.allowsTypeSelect = false
    tableView.allowsMultipleSelection = true
    tableView.delegate = self
    tableView.dataSource = self

    // Download subtitle when table view row is double clicked
    tableView.target = self
    tableView.doubleAction = #selector(downloadBtnAction(_:))

    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = tableView
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.horizontalScrollElasticity = .none
    scrollView.verticalScrollElasticity = .none
    scrollView.wantsLayer = true
    scrollView.layer?.cornerRadius = 6
    scrollView.setContentCompressionResistancePriority(.init(1), for: .vertical)
    view.addSubview(scrollView)
    scrollView.padding(.horizontal).spacing(.top(8), to: promptLabel)

    let cancelBtn = ui.button("cancel", target: self, action: #selector(cancelBtnAction(_:)))
    cancelBtn.keyEquivalent = "\u{1b}"
    downloadBtn = ui.button("download", target: self, action: #selector(downloadBtnAction(_:)))
    downloadBtn.isEnabled = false
    for btn in [cancelBtn, downloadBtn!] {
      btn.isBordered = false
      btn.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    }
    let buttonStack = ui.hStack(cancelBtn, downloadBtn)
    view.addSubview(buttonStack)
    buttonStack.padding(.trailing, .bottom, .leading(greaterThan: 8)).spacing(.top(8), to: scrollView)

    let widthConstraint = view.widthAnchor.constraint(equalToConstant: 600)
    widthConstraint.priority = .init(499)
    widthConstraint.isActive = true
    let heightConstraint = view.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
    heightConstraint.priority = .init(1)
    heightConstraint.isActive = true
  }

  @objc func downloadBtnAction(_ sender: Any) {
    guard let userDoneAction else { return }
    userDoneAction(tableView.selectedRowIndexes.map { subtitles[$0] })
    PlayerCore.active.hideOSD()
    context = nil
  }

  @objc func cancelBtnAction(_ sender: Any) {
    guard let userCanceledAction else { return }
    userCanceledAction()
    PlayerCore.active.hideOSD()
    context = nil
  }
}


extension SubChooseViewController: NSTableViewDelegate, NSTableViewDataSource {

  func numberOfRows(in tableView: NSTableView) -> Int {
    return subtitles.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = tableView.makeView(withIdentifier: subCellIdentifier, owner: self) as? SubCellView ?? SubCellView()
    let (name, left, right) = subtitles[row].getDescription()
    cell.textField?.stringValue = name
    cell.leftLabel.stringValue = left
    cell.rightLabel.stringValue = right
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    downloadBtn.isEnabled = tableView.selectedRow != -1
  }
}

fileprivate class SubCellView: NSTableCellView {
  let leftLabel = NSTextField(labelWithString: "")
  let rightLabel = NSTextField(labelWithString: "")

  init() {
    super.init(frame: .zero)
    identifier = subCellIdentifier

    for label in [leftLabel, rightLabel] {
      label.translatesAutoresizingMaskIntoConstraints = false
      label.controlSize = .small
      label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
      label.textColor = .secondaryLabelColor
      label.allowsExpansionToolTips = true
      label.setContentHuggingPriority(.init(251), for: .horizontal)
      addSubview(label)
    }
    leftLabel.padding(.top(8), .leading(8))
    rightLabel.padding(.trailing(8)).alignBaseline(with: leftLabel)
    rightLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leftLabel.trailingAnchor, constant: 8).isActive = true

    let nameLabel = NSTextField(labelWithString: "")
    nameLabel.translatesAutoresizingMaskIntoConstraints = false
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.allowsExpansionToolTips = true
    nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    addSubview(nameLabel)
    nameLabel.padding(.horizontal(8), .bottom(8)).spacing(.top(4), to: leftLabel)
    textField = nameLabel
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
