//
//  InspectorWindowController.swift
//  iina
//
//  Created by lhc on 21/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class InspectorWindowController: NSWindowController {
  
  override var windowNibName: String {
    return "InspectorWindowController"
  }
  
  @IBOutlet weak var pathField: NSTextField!
  @IBOutlet weak var durationField: NSTextField!
  @IBOutlet weak var vformatField: NSTextField!
  @IBOutlet weak var vcodecField: NSTextField!
  @IBOutlet weak var vsizeField: NSTextField!
  @IBOutlet weak var vbitrateField: NSTextField!
  @IBOutlet weak var aformatField: NSTextField!
  @IBOutlet weak var acodecField: NSTextField!
  @IBOutlet weak var achannelsField: NSTextField!
  @IBOutlet weak var abitrateField: NSTextField!
  @IBOutlet weak var asamplerateField: NSTextField!
  

  override func windowDidLoad() {
    super.windowDidLoad()
    updateInfo()
  }
  
  func updateInfo() {
    let controller = PlayerCore.shared.mpvController
    
    // string properties
    
    let strProperties: [String: NSTextField] = [
      MPVProperty.path: pathField,
      MPVProperty.videoFormat: vformatField,
      MPVProperty.videoCodec: vcodecField,
      MPVProperty.videoBitrate: vbitrateField,
      MPVProperty.audioCodec: acodecField,
      MPVProperty.audioParamsFormat: aformatField,
      MPVProperty.audioParamsChannels: achannelsField,
      MPVProperty.audioBitrate: abitrateField,
      MPVProperty.audioParamsSamplerate: asamplerateField
    ]
    
    strProperties.forEach { (k, v) in
      v.stringValue = controller.getString(k) ?? "Error"
    }
    
    // other properties
    
    let duration = controller.getDouble(MPVProperty.duration)
    durationField.stringValue = VideoTime(Int(duration)).stringRepresentation
    
    let vwidth = controller.getInt(MPVProperty.width)
    let vheight = controller.getInt(MPVProperty.height)
    vsizeField.stringValue = "\(vwidth)\u{d7}\(vheight)"
  }
  
}
