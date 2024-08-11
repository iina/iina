//
//  PreferenceViewController.swift
//  iina
//
//  Created by Collider LI on 8/7/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class PreferenceViewController: NSViewController {

  var stackView: NSStackView!

  var sectionViews: [NSView] {
    return []
  }

  @available(macOS 11.0, *)
  func makeSymbol(_ name: String, fallbackName: NSImage.Name) -> NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .bold)
    return Utility.findSFSymbol(name, withConfiguration: configuration, fallbackName: fallbackName)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let views = sectionViews.flatMap { [$0, NSBox.horizontalLine()] }.dropLast()

    stackView = NSStackView(views: Array(views))
    stackView.orientation = .vertical
    stackView.alignment = .leading
    stackView.spacing = 16
    stackView.distribution = .fill

    stackView.views.forEach { Utility.quickConstraints(["H:|[v]|"], ["v": $0]) }

    view.addSubview(stackView)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": stackView])
  }

}
