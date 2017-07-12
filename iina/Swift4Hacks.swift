//
//  Swift4Hacks.swift
//  iina
//
//  Created by Saagar Jha on 7/9/17.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

// These symbols aren't available in AppKit yet
#if swift(>=4.0)
let NSURLPboardType = NSPasteboard.PasteboardType(kUTTypeURL as String)
let NSFilenamesPboardType = NSPasteboard.PasteboardType(kUTTypeURL as String)
#endif
