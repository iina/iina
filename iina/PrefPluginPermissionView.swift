//
//  PrefPluginPermissionView.swift
//  iina
//
//  Created by Collider LI on 17/9/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class PrefPluginPermissionView: NSViewController {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefPluginPermissionView")
  }

  var name: String
  var desc: String
  var isDangerous: Bool

  @IBOutlet weak var nameLabel: NSTextField!
  @IBOutlet weak var descLabel: NSTextField!
  @IBOutlet weak var cautionImage: NSImageView!

  init(name: String, desc: String, isDangerous: Bool) {
    self.name = name
    self.desc = desc
    self.isDangerous = isDangerous
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    nameLabel.stringValue = name
    descLabel.stringValue = desc
    cautionImage.isHidden = !isDangerous
  }

}
