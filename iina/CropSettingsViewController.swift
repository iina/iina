//
//  CropSettingsViewController.swift
//  iina
//
//  Created by lhc on 22/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class CropSettingsViewController: NSViewController {

  weak var mainWindow: MainWindowController!

  lazy var cropBoxView: CropBoxView = {
    let view = CropBoxView()
    view.settingsViewController = self
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  @IBOutlet weak var cropRectLabel: NSTextField!
  @IBOutlet weak var predefinedAspectSegment: NSSegmentedControl!

  private var cropx: Int = 0
  private var cropy: Int = 0  // in flipped coord
  private var cropw: Int = 0
  private var croph: Int = 0

  var readableCropString: String {
    return "(\(cropx), \(cropy)) (\(cropw)\u{d7}\(croph))"
  }

  override func viewDidLoad() {
    super.viewDidLoad()
  }

  override func viewDidAppear() {
    predefinedAspectSegment.selectedSegment = -1
  }

  func selectedRectUpdated() {
    guard mainWindow.isInInteractiveMode else { return }
    let rect = cropBoxView.selectedRect
    updateCropValues(from: rect)
    cropRectLabel.stringValue = readableCropString
  }


  @IBAction func doneBtnAction(_ sender: AnyObject) {
    let playerCore = mainWindow.player

    mainWindow.exitInteractiveMode {
      if self.cropx == 0 && self.cropy == 0 &&
        self.cropw == playerCore.info.videoWidth &&
        self.croph == playerCore.info.videoHeight {
        // if no crop, remove the crop filter
        if let vf = playerCore.info.cropFilter {
          let _ = playerCore.removeVideoFiler(vf)
          playerCore.info.unsureCrop = "None"
          return
        }
      }
      // else, set the filter
      let filter = MPVFilter.crop(w: self.cropw, h: self.croph, x: self.cropx, y: self.cropy)
      playerCore.setCrop(fromFilter: filter)
      // custom crop has no corresponding menu entry
      playerCore.info.unsureCrop = ""
      self.mainWindow.displayOSD(.crop(self.readableCropString))
    }
  }

  @IBAction func cancelBtnAction(_ sender: AnyObject) {
    mainWindow.exitInteractiveMode{
      return
    }
  }

  @IBAction func predefinedAspectValueAction(_ sender: NSSegmentedControl) {
    guard let str = sender.label(forSegment: sender.selectedSegment) else { return }
    guard let aspect = Aspect(string: str) else { return }

    let actualSize = cropBoxView.actualSize
    let croppedSize = actualSize.crop(withAspect: aspect)
    let cropped = NSMakeRect((actualSize.width - croppedSize.width) / 2,
                             (actualSize.height - croppedSize.height) / 2,
                             croppedSize.width,
                             croppedSize.height)

    cropBoxView.setSelectedRect(to: cropped)
  }


  private func updateCropValues(from rect: NSRect) {
    cropx = Int(rect.x)
    cropy = Int(CGFloat(mainWindow.player.info.videoHeight!) - rect.height - rect.y)
    cropw = Int(rect.width)
    croph = Int(rect.height)
  }

}
