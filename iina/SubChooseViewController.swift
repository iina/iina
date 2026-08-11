//
//  SubChooseViewController.swift
//  iina
//
//  Created by Collider LI on 4/3/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class SubChooseViewController: NSViewController {
  override var nibName: NSNib.Name {
    return NSNib.Name("SubChooseViewController")
  }

  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet weak var downloadBtn: NSButton!

  var subtitles: [OnlineSubtitle] = [] {
    didSet {
      filteredSubtitles = subtitles
      tableView?.reloadData()
    }
  }

  var filteredSubtitles: [OnlineSubtitle] = []

  var userDoneAction: (([OnlineSubtitle]) -> Void)?
  var userCanceledAction: (() -> Void)?

  var context: Any?

  private var searchField: NSSearchField!

  override func viewDidLoad() {
    super.viewDidLoad()

    if let scrollView = tableView.enclosingScrollView {
      scrollView.wantsLayer = true
      scrollView.layer?.cornerRadius = 6
    }

    tableView.delegate = self
    tableView.dataSource = self

    // Download subtitle when table view row is double clicked
    tableView.target = self
    tableView.doubleAction = #selector(downloadBtnAction(_:))

    // Add search field programmatically above the scroll view
    searchField = NSSearchField()
    searchField.translatesAutoresizingMaskIntoConstraints = false
    searchField.placeholderString = "Filter subtitles…"
    searchField.delegate = self
    view.addSubview(searchField)

    guard let scrollView = tableView.enclosingScrollView else { return }

    // Anchor search field: 16pt below the description label, 8pt above the scroll view.
    // The description label is the first text field in the view loaded from the XIB.
    let descriptionLabel = view.subviews.first { $0 is NSTextField }
    let topAnchor: NSLayoutYAxisAnchor = descriptionLabel?.bottomAnchor ?? view.topAnchor

    NSLayoutConstraint.activate([
      searchField.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      searchField.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
      searchField.topAnchor.constraint(equalTo: topAnchor, constant: 16),
      searchField.bottomAnchor.constraint(equalTo: scrollView.topAnchor, constant: -8),
    ])
  }

  @IBAction func downloadBtnAction(_ sender: Any) {
    guard let userDoneAction = userDoneAction else { return }
    userDoneAction(tableView.selectedRowIndexes.map { filteredSubtitles[$0] })
    PlayerCore.active.hideOSD()
    context = nil
  }

  @IBAction func cancelBtnAction(_ sender: Any) {
    guard let userCanceledAction = userCanceledAction else { return }
    userCanceledAction()
    PlayerCore.active.hideOSD()
    context = nil
  }
}


extension SubChooseViewController: NSTableViewDelegate, NSTableViewDataSource {

  func numberOfRows(in tableView: NSTableView) -> Int {
    return filteredSubtitles.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    let (name, left, right) = filteredSubtitles[row].getDescription()
    return ["name": name, "left": left, "right": right]
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    return tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "SubCell"), owner: self)
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    downloadBtn.isEnabled = tableView.selectedRow != -1
  }
}


extension SubChooseViewController: NSSearchFieldDelegate {
  func controlTextDidChange(_ obj: Notification) {
    let query = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
    if query.isEmpty {
      filteredSubtitles = subtitles
    } else {
      filteredSubtitles = subtitles.filter { sub in
        let (name, left, right) = sub.getDescription()
        return name.lowercased().contains(query)
          || left.lowercased().contains(query)
          || right.lowercased().contains(query)
      }
    }
    tableView.reloadData()
    downloadBtn.isEnabled = tableView.selectedRow != -1
  }
}
