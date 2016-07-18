//
//  Preference.swift
//  mpvx
//
//  Created by lhc on 17/7/16.
//  Copyright © 2016年 lhc. All rights reserved.
//

import Cocoa

class Preference: NSObject {
  
  struct Key {
    /** Window position. (float) */
    // static let windowPosition = "windowPosition"
    
    /** Horizontal positon of control bar. */
    static let  controlBarPositionHorizontal = "controlBarPositionHorizontal"
    
    /** Horizontal positon of control bar. In percentage from bottom. */
    static let  controlBarPositionVertical = "controlBarPositionVertical"
    
    /** Whether control bar stick to center when dragging. */
    static let  controlBarStickToCenter = "controlBarStickToCenter"
    
    /** Timeout for auto hiding control bar */
    static let  controlBarAutoHideTimeout  = "controlBarAutoHideTimeout"
  }
  
  let defaultPreference:[String : AnyObject] = [
    Key.controlBarPositionHorizontal: Float(50),
    Key.controlBarPositionVertical: Float(10),
    Key.controlBarStickToCenter: true,
    Key.controlBarAutoHideTimeout: 5,
  ]
  
  override init() {
    UserDefaults.standard.register(defaultPreference)
  }
  

}
