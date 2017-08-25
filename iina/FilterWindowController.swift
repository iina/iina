//
//  FilterWindowController.swift
//  iina
//
//  Created by lhc on 25/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class FilterWindowController: NSWindowController {

  override var windowNibName: String {
    return "FilterWindowController"
  }

  var filterType: String!

  var filters: [MPVFilter] = []

  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet var newFilterSheet: NSWindow!

  override func windowDidLoad() {
    super.windowDidLoad()

    // title
    window?.title = filterType == MPVProperty.af ? NSLocalizedString("filter.audio_filters", comment: "Audio Filters") : NSLocalizedString("filter.video_filters", comment: "Video Filters")

    filters = PlayerCore.active.mpv.getFilters(filterType)
    tableView.delegate = self
    tableView.dataSource = self

    // notifications
    let notiName = filterType == MPVProperty.af ? Constants.Noti.afChanged : Constants.Noti.vfChanged
    NotificationCenter.default.addObserver(self, selector: #selector(reloadTable), name: notiName, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(reloadTable), name: Constants.Noti.mainWindowChanged, object: nil)
  }

  @objc
  func reloadTable() {
    filters = PlayerCore.active.mpv.getFilters(filterType)
    tableView.reloadData()
  }

  func setFilters() {
    PlayerCore.active.mpv.setFilters(filterType, filters: filters)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func addFilter(_ filter: MPVFilter) {
    filters.append(filter)
    guard PlayerCore.active.addVideoFilter(filter) else {
      Utility.showAlert("filter.incorrect")
      return
    }
    reloadTable()
  }

  // MARK: - IBAction

  @IBAction func addFilterAction(_ sender: AnyObject) {
    window!.beginSheet(newFilterSheet)
  }

  @IBAction func removeFilterAction(_ sender: AnyObject) {
    if tableView.selectedRow >= 0 {
      if PlayerCore.active.removeVideoFiler(filters[tableView.selectedRow]) {
        reloadTable()
      }
    }
  }

}

extension FilterWindowController: NSTableViewDelegate, NSTableViewDataSource {

  func numberOfRows(in tableView: NSTableView) -> Int {
    return filters.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    guard let filter = filters.at(row) else { return nil }
    if tableColumn?.identifier == Constants.Identifier.key {
      return row.toStr()
    } else if tableColumn?.identifier == Constants.Identifier.value {
      return filter.stringFormat
    }
    return ""
  }

  func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
    guard let value = object as? String, tableColumn?.identifier == Constants.Identifier.value else { return }

    if let newFilter = MPVFilter(rawString: value) {
      filters[row] = newFilter
      setFilters()
    } else {
      Utility.showAlert("filter.incorrect")
    }
  }

}


class NewFilterSheetViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {

  @IBOutlet weak var filterWindow: FilterWindowController!
  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet weak var scrollContentView: NSView!

  private var currentPreset: FilterPreset?
  private var currentBindings: [String: NSControl] = [:]

  override func awakeFromNib() {
    tableView.dataSource = self
    tableView.delegate = self
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return FilterPreset.presets.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    return FilterPreset.presets.at(row)?.localizedName
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard let preset = FilterPreset.presets.at(tableView.selectedRow) else { return }
    showSettings(for: preset)
  }

  /** Render parameter controls at right side when selected a filter in the table. */
  func showSettings(for preset: FilterPreset) {
    currentPreset = preset
    currentBindings.removeAll()
    scrollContentView.subviews.forEach { $0.removeFromSuperview() }
    var maxY: CGFloat = 0
    let generateInputs: (String, FilterParameter) -> Void = { (name, param) in
      self.scrollContentView.addSubview(self.quickLabel(yPos: maxY, title: preset.localizedParamName(name)))
      maxY += 21
      let input = self.quickInput(yPos: &maxY, param: param)
      self.scrollContentView.addSubview(input)
      self.currentBindings[name] = input
    }
    if let paramOrder = preset.paramOrder {
      for name in paramOrder {
        generateInputs(name, preset.params[name]!)
      }
    } else {
      for (name, param) in preset.params {
        generateInputs(name, param)
      }
    }
    scrollContentView.frame.size.height = maxY
  }

  private func quickLabel(yPos: CGFloat, title: String) -> NSTextField {
    let label = NSTextField(frame: NSRect(x: 0, y: yPos,
                                          width: scrollContentView.frame.width,
                                          height: 17))
    label.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize())
    label.stringValue = title
    label.drawsBackground = false
    label.isBezeled = false
    label.isSelectable = false
    label.isEditable = false
    return label
  }

  /** Create the control from a `FilterParameter` definition. */
  private func quickInput(yPos: inout CGFloat, param: FilterParameter) -> NSControl {
    switch param.type {
    case .text:
      // Text field
      let label = ShortcutAvailableTextField(frame: NSRect(x: 4, y: yPos,
                                            width: scrollContentView.frame.width - 8,
                                            height: 22))
      label.stringValue = param.defaultValue.stringValue
      label.isSelectable = false
      label.isEditable = true
      label.lineBreakMode = .byClipping
      label.usesSingleLineMode = true
      label.cell?.isScrollable = true
      yPos += 22 + 8
      return label
    case .int:
      // Slider
      let slider = NSSlider(frame: NSRect(x: 4, y: yPos,
                                          width: scrollContentView.frame.width - 8,
                                          height: 19))
      slider.minValue = Double(param.minInt!)
      slider.maxValue = Double(param.maxInt!)
      yPos += 19 + 8
      if let step = param.step {
        slider.numberOfTickMarks = (param.maxInt! - param.minInt!) / step + 1
        slider.allowsTickMarkValuesOnly = true
        slider.frame.size.height = 24
        yPos += 5
      }
      slider.intValue = Int32(param.defaultValue.intValue)
      return slider
    case .float:
      // Slider
      let slider = NSSlider(frame: NSRect(x: 4, y: yPos,
                                          width: scrollContentView.frame.width - 8,
                                          height: 19))
      slider.minValue = Double(param.min!)
      slider.maxValue = Double(param.max!)
      slider.floatValue = param.defaultValue.floatValue
      yPos += 19 + 8
      return slider
    }
  }

  @IBAction func sheetAddBtnAction(_ sender: Any) {
    filterWindow.window!.endSheet(filterWindow.newFilterSheet, returnCode: NSModalResponseOK)
    guard let preset = currentPreset else { return }
    // create instance
    let instance = FilterPresetInstance(from: preset)
    for (name, control) in currentBindings {
      switch preset.params[name]!.type {
      case .text:
        instance.params[name] = FilterParamaterValue(string: control.stringValue)
      case .int:
        instance.params[name] = FilterParamaterValue(int: Int(control.intValue))
      case .float:
        instance.params[name] = FilterParamaterValue(float: control.floatValue)
      }
    }
    // create filter
    filterWindow.addFilter(preset.transformer(instance))
  }

  @IBAction func sheetCancelBtnAction(_ sender: Any) {
    filterWindow.window!.endSheet(filterWindow.newFilterSheet, returnCode: NSModalResponseCancel)
  }

}
