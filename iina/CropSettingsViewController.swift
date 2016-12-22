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
  
  private var cropx: Int = 0
  private var cropy: Int = 0
  private var cropw: Int = 0
  private var croph: Int = 0
  
  override func viewDidLoad() {
    super.viewDidLoad()
    // Do view setup here.
  }
  
  func updateSelectedRect() {
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
      self.mainWindow.playerCore.addVideoFilter(MPVFilter.crop(w: self.cropw, h: self.croph, x: self.cropx, y: self.cropy))
    }
  }
  
  @IBAction func PredefinedAspectValueAction(_ sender: NSSegmentedControl) {
    guard let str = sender.label(forSegment: sender.selectedSegment) else { return }
    guard let aspect = Aspect(string: str) else { return }
    
    let actualSize = cropBoxView.actualSize
    let videoRect = cropBoxView.videoRect
    let croppedSize = actualSize.crop(withAspect: aspect)
    let cropped = NSMakeRect((actualSize.width - croppedSize.width) / 2,
                             (actualSize.height - croppedSize.height) / 2,
                             croppedSize.width,
                             croppedSize.height)
    
    let xScale =  videoRect.width / actualSize.width
    let yScale =  videoRect.height / actualSize.height
    
    let ix = cropped.origin.x * xScale + videoRect.origin.x
    let iy = cropped.origin.y * xScale + videoRect.origin.y
    let iw = cropped.width * xScale
    let ih = cropped.height * yScale
    
    cropBoxView.boxRect = NSMakeRect(ix, iy, iw, ih)
    cropBoxView.updateCursorRects()
    cropBoxView.needsDisplay = true
  }
  
    
}
