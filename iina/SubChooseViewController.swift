//
//  SubChooseViewController.swift
//  iina
//
//  Created by Collider LI on 4/3/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class SubChooseViewController: NSViewController {

  @IBOutlet weak var tableView: NSTableView!

  var subtitles: [OnlineSubtitle] = []

  var userDoneAction: (([OnlineSubtitle]) -> Void)?
  var userCanceledAction: (() -> Void)?

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
    return tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "OpenSubCell"), owner: self)
  }

}
