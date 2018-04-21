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

  var subtitles: [OnlineSubtitle] = []

  var userDoneAction: (([OnlineSubtitle]) -> Void)?
  var userCanceledAction: (() -> Void)?

  private var cellIdentifier: NSUserInterfaceItemIdentifier

  init(source: OnlineSubtitle.Source) {
    switch source {
    case .assrt:
      self.cellIdentifier = NSUserInterfaceItemIdentifier(rawValue: "AssrtCell")
    case .openSub:
      self.cellIdentifier = NSUserInterfaceItemIdentifier(rawValue: "OpenSubCell")
    default:
      fatalError("Unsupported subtitle source.")
    }
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    tableView.delegate = self
    tableView.dataSource = self
  }

  @IBAction func downloadBtnAction(_ sender: Any) {
    guard let userDoneAction = userDoneAction else { return }
    userDoneAction(tableView.selectedRowIndexes.map { subtitles[$0] })
    PlayerCore.active.hideOSD()
  }

  @IBAction func cancelBtnAction(_ sender: Any) {
    guard let userCanceledAction = userCanceledAction else { return }
    userCanceledAction()
    PlayerCore.active.hideOSD()
  }
}


extension SubChooseViewController: NSTableViewDelegate, NSTableViewDataSource {

  func numberOfRows(in tableView: NSTableView) -> Int {
    return subtitles.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    return subtitles[row]
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    return tableView.makeView(withIdentifier: cellIdentifier, owner: self)
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    if tableView.selectedRow != -1 {
      downloadBtn.isEnabled = true
    } else {
      downloadBtn.isEnabled = false
    }
  }

}
