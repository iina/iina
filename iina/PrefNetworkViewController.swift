//
//  PrefNetworkViewController.swift
//  iina
//
//  Created by lhc on 27/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

@objcMembers
class PrefNetworkViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefNetworkViewController")
  }

  var viewIdentifier: String = "PrefNetworkViewController"

  var preferenceTabImage: NSImage {
    return makeSymbol("network", fallbackImage: "pref_network")
  }

  var preferenceTabTitle: String {
    view.layoutSubtreeIfNeeded()
    return NSLocalizedString("preference.network", comment: "Network")
  }

  @IBOutlet weak var ytdlHelpLabel: NSTextField!
  @IBOutlet weak var enableYTDLCheckBox: NSButton!
  
  override var sectionViews: [NSView] {
    return [sectionCacheView, sectionNetworkView, sectionYTDLView]
  }

  @IBOutlet var sectionCacheView: NSView!
  @IBOutlet var sectionNetworkView: NSView!
  @IBOutlet var sectionYTDLView: NSView!

  override func viewDidLoad() {
    super.viewDidLoad()

    updateYTDLSettings()
    NotificationCenter.default.addObserver(forName: .iinaPluginChanged, object: nil, queue: .main) { [unowned self] _ in
      self.updateYTDLSettings()
    }
  }

  private func updateYTDLSettings() {
    let hasYTDL = JavascriptPlugin.hasYTDL
    enableYTDLCheckBox.state = hasYTDL ? .off : (Preference.bool(for: .ytdlEnabled) ? .on : .off)
    sectionYTDLView.subviews.forEach {
      if let control = $0 as? NSControl {
        control.isEnabled = !hasYTDL
      }
    }
    ytdlHelpLabel.stringValue = hasYTDL ?
      NSLocalizedString("preference.ytdl_plugin_installed", comment: "") :
      NSLocalizedString("preference.ytdl_plugin_not_installed", comment: "")
  }

  @IBAction func ytdlHelpAction(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.ytdlHelpLink)!)
  }

}
