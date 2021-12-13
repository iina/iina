//
//  ScreenshootOSDView.swift
//  iina
//
//  Created by Collider LI on 17/8/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

class ScreenshootOSDView: NSViewController {
  @IBOutlet weak var imageView: NSImageView!
  @IBOutlet weak var heightConstraint: NSLayoutConstraint!
  @IBOutlet weak var widthConstraint: NSLayoutConstraint!
  @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
  @IBOutlet weak var deleteBtn: NSButton!
  @IBOutlet weak var editBtn: NSButton!
  @IBOutlet weak var revealBtn: NSButton!

  private var image: NSImage?
  private var size: NSSize?
  private var fileURL: URL?

  func setImage(_ image: NSImage, size: NSSize, fileURL: URL?) {
    self.image = image
    self.size = size
    self.fileURL = fileURL
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.translatesAutoresizingMaskIntoConstraints = false
    widthConstraint.constant = size!.width
    heightConstraint.constant = size!.height
    imageView.image = image
    imageView.wantsLayer = true
    imageView.layer?.borderColor = NSColor.gridColor.withAlphaComponent(0.6).cgColor
    imageView.layer?.borderWidth = 1
    imageView.layer?.cornerRadius = 4
    imageView.layer?.masksToBounds = true
    if fileURL == nil {
      [deleteBtn, editBtn, revealBtn].forEach { $0?.isHidden = true }
      bottomConstraint.constant = 8
    }
  }

  @IBAction func deleteBtnAction(_ sender: Any) {
    guard let fileURL = fileURL else { return }
    try? FileManager.default.removeItem(at: fileURL)
    PlayerCore.active.hideOSD()
  }

  @IBAction func revealBtnAction(_ sender: Any) {
    guard let fileURL = fileURL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    PlayerCore.active.hideOSD()
  }

  @IBAction func editBtnAction(_ sender: Any) {
    guard let fileURL = fileURL else { return }
    NSWorkspace.shared.open(fileURL)
    PlayerCore.active.hideOSD()
  }
}
