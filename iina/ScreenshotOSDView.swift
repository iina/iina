//
//  ScreenshotOSDView.swift
//  iina
//
//  Created by Collider LI on 17/8/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

fileprivate let ui = UIHelper(scope: "osd.screenshot")

class ScreenshotOSDView: NSViewController {
  private var image: NSImage?
  private var size: NSSize?
  private var fileURL: URL?

  func setImage(_ image: NSImage, size: NSSize, fileURL: URL?) {
    self.image = image
    self.size = size
    self.fileURL = fileURL
  }

  override func loadView() {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    self.view = view

    let imageView = NSImageView()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.image = image
    imageView.wantsLayer = true
    imageView.layer?.borderColor = NSColor.gridColor.withAlphaComponent(0.6).cgColor
    imageView.layer?.borderWidth = 1
    imageView.layer?.cornerRadius = 4
    imageView.layer?.masksToBounds = true
    view.addSubview(imageView)
    imageView.padding(.top(8), .horizontal).size(width: size!.width, height: size!.height)

    guard fileURL != nil else {
      imageView.padding(.bottom(8))
      return
    }

    let buttons = [
      ("delete", #selector(deleteBtnAction(_:))),
      ("edit", #selector(editBtnAction(_:))),
      ("reveal", #selector(revealBtnAction(_:)))
    ].map { (key, action) in
      let btn = ui.button(key, target: self, action: action)
      btn.isBordered = false
      btn.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
      return btn
    }
    let buttonStack = ui.hStack(align: .firstBaseline, spacing: 12, buttons)
    view.addSubview(buttonStack)
    buttonStack.padding(.leading, .bottom(8)).spacing(.top(12), to: imageView)
  }

  @objc func deleteBtnAction(_ sender: Any) {
    guard let fileURL else { return }
    try? FileManager.default.removeItem(at: fileURL)
    PlayerCore.active.hideOSD()
  }

  @objc func revealBtnAction(_ sender: Any) {
    guard let fileURL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    PlayerCore.active.hideOSD()
  }

  @objc func editBtnAction(_ sender: Any) {
    guard let fileURL else { return }
    NSWorkspace.shared.open(fileURL)
    PlayerCore.active.hideOSD()
  }
}
