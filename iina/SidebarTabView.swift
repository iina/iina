//
//  SidebarTabView.swift
//  iina
//
//  Created by Collider LI on 10/10/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

class SidebarTabView: NSViewController {
  var name: String!
  var pluginID: String!
  weak var pluginSidebarView: PluginViewController!

  @IBOutlet weak var label: NSTextField!

  override var acceptsFirstResponder: Bool {
    true
  }

  var isActive: Bool = false {
    didSet {
      updateStyle()
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.wantsLayer = true
    view.layer?.cornerRadius = 10
    updateStyle()
    label.stringValue = name
  }

  override func mouseDown(with event: NSEvent) {
    pluginSidebarView.pleaseSwitchToTab(pluginID)
    isActive = true
  }

  private func updateStyle() {
    let background = NSColor.controlBackgroundColor
    if isActive {
      view.layer?.backgroundColor = background.withAlphaComponent(0.2).cgColor
      label.textColor = .textColor
    } else {
      view.layer?.backgroundColor = background.withAlphaComponent(0.1).cgColor
      label.textColor = NSColor.textColor.withAlphaComponent(0.5)
    }
  }
}


class SidebarTabActiveView: NSView {
  override var acceptsFirstResponder: Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    self.nextResponder?.mouseDown(with: event)
  }
}
