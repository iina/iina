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
  private var cropy: Int = 0
  private var cropw: Int = 0
  private var croph: Int = 0
  
  override func viewDidLoad() {
    super.viewDidLoad()
  }
  
  override func viewDidAppear() {
    predefinedAspectSegment.selectedSegment = -1
  }
  
  func selectedRectUpdated() {
    guard mainWindow.isInInteractiveMode else { return }
    let rect = cropBoxView.selectedRect
    cropx = Int(rect.origin.x)
    cropy = Int(rect.origin.y)
    cropw = Int(rect.width)
    croph = Int(rect.height)
    cropRectLabel.stringValue = "Origin(\(cropx), \(cropy))  Size(\(cropw) \u{d7} \(croph))"
  }

  
  @IBAction func doneBtnAction(_ sender: AnyObject) {
    mainWindow.exitInteractiveMode {
      let filter = MPVFilter.crop(w: self.cropw, h: self.croph, x: self.cropx, y: self.cropy)
      self.mainWindow.playerCore.setCrop(fromFilter: filter)
      // custom crop has no corresponding menu entry
      self.mainWindow.playerCore.info.unsureCrop = ""
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
  
    
}
