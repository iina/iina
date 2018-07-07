//
//  PreferenceWindowController.swift
//  iina
//
//  Created by Collider LI on 6/7/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

protocol PreferenceWindowEmbeddable where Self: NSViewController {
  var preferenceTabTitle: String { get }
}

class PreferenceWindowController: NSWindowController {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("PreferenceWindowController")
  }

  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet weak var contentView: NSView!

  private var viewControllers: [NSViewController & PreferenceWindowEmbeddable]

  init(viewControllers: [NSViewController & PreferenceWindowEmbeddable]) {
    self.viewControllers = viewControllers
    super.init(window: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func windowDidLoad() {
    super.windowDidLoad()

    window?.titlebarAppearsTransparent = true
    window?.isMovableByWindowBackground = true

    tableView.delegate = self
    tableView.dataSource = self

    loadTab(at: 0)
  }

  private func loadTab(at index: Int) {
    contentView.subviews.forEach { $0.removeFromSuperview() }
    guard let vc = viewControllers[at: index] else { return }
    contentView.addSubview(vc.view)
    Utility.quickConstraints(["H:|-20-[v]-20-|", "V:|-28-[v]-28-|"], ["v": vc.view])
  }

}

extension PreferenceWindowController: NSTableViewDelegate, NSTableViewDataSource {

  func numberOfRows(in tableView: NSTableView) -> Int {
    return viewControllers.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    return viewControllers[at: row]?.preferenceTabTitle
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    loadTab(at: tableView.selectedRow)
  }

}
