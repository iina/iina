//
//  FilterWindowController.swift
//  iina
//
//  Created by lhc on 25/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class FilterWindowController: NSWindowController, NSWindowDelegate {

  override var windowNibName: NSNib.Name {
    return NSNib.Name("FilterWindowController")
  }

  @objc let monospacedFont: NSFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

  @IBOutlet weak var splitView: NSSplitView!
  @IBOutlet weak var splitViewUpperView: NSView!
  @IBOutlet weak var splitViewLowerView: NSView!
  @IBOutlet var upperView: NSView!
  @IBOutlet var lowerView: NSView!
  @IBOutlet weak var currentFiltersTableView: NSTableView!
  @IBOutlet weak var savedFiltersTableView: NSTableView!
  @IBOutlet var newFilterSheet: NSWindow!
  @IBOutlet var saveFilterSheet: NSWindow!
  @IBOutlet var editFilterSheet: NSWindow!
  @IBOutlet weak var saveFilterNameTextField: NSTextField!
  @IBOutlet weak var keyRecordView: KeyRecordView!
  @IBOutlet weak var keyRecordViewLabel: NSTextField!
  @IBOutlet weak var editFilterNameTextField: NSTextField!
  @IBOutlet weak var editFilterStringTextField: NSTextField!
  @IBOutlet weak var editFilterKeyRecordView: KeyRecordView!
  @IBOutlet weak var editFilterKeyRecordViewLabel: NSTextField!
  @IBOutlet weak var removeButton: NSButton!

  var loaded = false

  var filterType: String!

  var filters: [MPVFilter] = []
  var savedFilters: [SavedFilter] = []
  private var filterIsSaved: [Bool] = []

  private var currentFilter: MPVFilter?
  private var currentSavedFilter: SavedFilter?

  override func windowDidLoad() {
    super.windowDidLoad()
    loaded = true
    window?.delegate = self

    // title
    window?.title = filterType == MPVProperty.af ? NSLocalizedString("filter.audio_filters", comment: "Audio Filters") : NSLocalizedString("filter.video_filters", comment: "Video Filters")

    splitViewUpperView.addSubview(upperView)
    splitViewLowerView.addSubview(lowerView)
    Utility.quickConstraints(["H:|[v]|", "V:|[v]|", "H:|[w]|", "V:|[w]|"], ["v": upperView, "w": lowerView])
    splitView.setPosition(splitView.frame.height - 140, ofDividerAt: 0)

    savedFilters = (Preference.array(for: filterType == MPVProperty.af ? .savedAudioFilters : .savedVideoFilters) ?? []).compactMap(SavedFilter.init(dict:))
    filters = PlayerCore.lastActive.mpv.getFilters(filterType)
    currentFiltersTableView.reloadData()
    savedFiltersTableView.reloadData()

    keyRecordView.delegate = self
    editFilterKeyRecordView.delegate = self

    updateButtonStatus()

    // notifications
    let notiName: Notification.Name = filterType == MPVProperty.af ? .iinaAFChanged : .iinaVFChanged
    NotificationCenter.default.addObserver(self, selector: #selector(reloadTableInMainThread), name: notiName, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(reloadTable), name: .iinaMainWindowChanged, object: nil)
  }

  @objc
  func reloadTableInMainThread() {
    DispatchQueue.main.async {
      self.reloadTable()
    }
  }

  @objc
  func reloadTable() {
    let pc = PlayerCore.lastActive
    // When IINA is terminating player windows are closed, which causes the iinaMainWindowChanged
    // notification to be posted and that results in the observer established above calling this
    // method. Thus this method may be called after IINA has commanded mpv to shutdown. Once mpv has
    // been told to shutdown mpv APIs must not be called as it can trigger a crash in mpv.
    guard !pc.isShuttingDown, !pc.isShutdown else { return }
    filters = pc.mpv.getFilters(filterType)
    filterIsSaved = [Bool](repeatElement(false, count: filters.count))
    savedFilters.forEach { savedFilter in
      if let asObject = MPVFilter(rawString: savedFilter.filterString),
         let index = filters.firstIndex(of: asObject) {
        savedFilter.isEnabled = true
        filterIsSaved[index] = true
      } else {
        savedFilter.isEnabled = false
      }
    }
    currentFiltersTableView.reloadData()
    savedFiltersTableView.reloadData()
  }

  func setFilters() {
    PlayerCore.lastActive.mpv.setFilters(filterType, filters: filters)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func addFilter(_ filter: MPVFilter) -> Bool {
    if filterType == MPVProperty.vf {
      guard PlayerCore.lastActive.addVideoFilter(filter) else {
        Utility.showAlert("filter.incorrect", sheetWindow: window)
        return false
      }
    } else {
      guard PlayerCore.lastActive.addAudioFilter(filter) else {
        Utility.showAlert("filter.incorrect", sheetWindow: window)
        return false
      }
    }
    filters.append(filter)
    reloadTable()
    return true
  }

  func saveFilter(_ filter: MPVFilter) {
    currentFilter = filter
    window!.beginSheet(saveFilterSheet)
  }

  private func syncSavedFilter() {
    Preference.set(savedFilters.map { $0.toDict() }, for: filterType == MPVProperty.af ? .savedAudioFilters : .savedVideoFilters)
    AppDelegate.shared.menuController?.updateSavedFilters(forType: filterType, from: savedFilters)
    UserDefaults.standard.synchronize()
  }

  /// Forms and returns a string representation of the list of configured filters.
  ///
  /// The string returned will contain one line for each filter in the list. If there are no filters configured then the string will be empty. The
  /// string representation returned is intended to be used for developer debugging.
  /// - Returns: String containing the list of configured filters with a prefix indicating the array index of the filter.
  private func filtersAsString() -> String {
    var result = ""
    for (index, filter) in filters.enumerated() {
      if !result.isEmpty {
        result += "\n"
      }
      result += "[\(index)] \(String(reflecting: filter))"
    }
    return result
  }

  // MARK: - IBAction

  @IBAction func addFilterAction(_ sender: Any) {
    saveFilterNameTextField.stringValue = ""
    keyRecordViewLabel.stringValue = ""
    window!.beginSheet(newFilterSheet)
  }

  @IBAction func removeFilterAction(_ sender: Any) {
    let pc = PlayerCore.lastActive
    let selectedRow = currentFiltersTableView.selectedRow
    if selectedRow >= 0 {
      let success: Bool
      if filterType == MPVProperty.vf {
        success = pc.removeVideoFilter(filters[selectedRow], selectedRow)
      } else {
        success = pc.removeAudioFilter(filters[selectedRow], selectedRow)
      }
      if success {
        reloadTable()
        pc.sendOSD(.removeFilter)
        // FIXME: For some reason, after removeFilterAction is called, tableViewSelectionDidChange(_:)
        // for currentFiltersTableView is not called. This is a workaround to ensure
        // tableViewSelectionDidChange(_:) is called.
        currentFiltersTableView.deselectAll(self)
      }
    }
  }

  @IBAction func saveFilterAction(_ sender: NSButton) {
    let row = currentFiltersTableView.row(for: sender)
    saveFilter(filters[row])
  }

  /// User activates or deactivates previously saved audio or video filter
  /// - Parameter sender: A checkbox in lower portion of filter window
  @IBAction func toggleSavedFilterAction(_ sender: NSButton) {
    let row = savedFiltersTableView.row(for: sender)
    let savedFilter = savedFilters[row]
    let pc = PlayerCore.lastActive

    // choose appropriate add/remove functions for .af/.vf
    var addFilterFunction: (String) -> Bool
    var removeFilterFunction: (String, Int) -> Bool
    var removeFilterUsingStringFunction: (String) -> Bool
    if filterType == MPVProperty.vf {
      addFilterFunction = pc.addVideoFilter
      removeFilterFunction = pc.removeVideoFilter
      removeFilterUsingStringFunction = pc.removeVideoFilter
    } else {
      addFilterFunction = pc.addAudioFilter
      removeFilterFunction = pc.removeAudioFilter
      removeFilterUsingStringFunction = pc.removeAudioFilter
    }

    if sender.state == .on {  // user activated filter
      if addFilterFunction(savedFilter.filterString) {
        pc.sendOSD(.addFilter(savedFilter.name))
      }
    } else {  // user deactivated filter
      if let asObject = MPVFilter(rawString: savedFilter.filterString),
         let index = filters.firstIndex(of: asObject) {
        // Remove the filter based on the index within the list of configured filters. This is the
        // preferred way to remove a filter as using the string representation is unreliable due to
        // filters that take multiple parameters having multiple valid string representations.
        if removeFilterFunction(savedFilter.filterString, index) {
          pc.sendOSD(.removeFilter)
        }
      } else {
        // If this occurs the MPVFilter method parseRawParamString may have not been able to parse
        // this kind of filter. Log the issue and attempt to remove the filter using the string
        // representation. For filters that have multiple valid string representations mpv may or
        // may not find and remove the filter.
        Logger.log("""
          Failed to locate filter: \(savedFilter.filterString)\nIn the list of filters:
          \n\(filtersAsString())
          """, level: .warning)
        if removeFilterUsingStringFunction(savedFilter.filterString) {
          pc.sendOSD(.removeFilter)
        }
      }
    }

    reloadTable()
  }

  @IBAction func deleteSavedFilterAction(_ sender: NSButton) {
    let row = savedFiltersTableView.row(for: sender)
    savedFilters.remove(at: row)
    reloadTable()
    syncSavedFilter()
  }

  @IBAction func editSavedFilterAction(_ sender: NSButton) {
    let row = savedFiltersTableView.row(for: sender)
    currentSavedFilter = savedFilters[row]
    editFilterNameTextField.stringValue = currentSavedFilter!.name
    editFilterStringTextField.stringValue = currentSavedFilter!.filterString
    editFilterKeyRecordView.currentKey = currentSavedFilter!.shortcutKey
    editFilterKeyRecordView.currentKeyModifiers = currentSavedFilter!.shortcutKeyModifiers
    editFilterKeyRecordViewLabel.stringValue = currentSavedFilter!.readableShortCutKey
    window!.beginSheet(editFilterSheet)
  }
}

extension FilterWindowController: NSTableViewDelegate, NSTableViewDataSource {

  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == currentFiltersTableView {
      return filters.count
    } else {
      return savedFilters.count
    }
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    if tableView == currentFiltersTableView {
      if tableColumn?.identifier == .key {
        return row.description
      } else if tableColumn?.identifier == .value {
        return filters[at: row]?.stringFormat
      } else {
        return filterIsSaved[row]
      }
    } else {
      return savedFilters[at: row]
    }
  }

  func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
    guard let value = object as? String, tableColumn?.identifier == .value else { return }

    if tableView == currentFiltersTableView {
      if let newFilter = MPVFilter(rawString: value) {
        filters[row] = newFilter
        setFilters()
      } else {
        Utility.showAlert("filter.incorrect", sheetWindow: window)
      }
    }
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    updateButtonStatus()
  }

  func windowDidBecomeKey(_ notification: Notification) {
    updateButtonStatus()
  }

  private func updateButtonStatus() {
    removeButton.isEnabled = currentFiltersTableView.selectedRow >= 0
  }

}

extension FilterWindowController: KeyRecordViewDelegate {

  func keyRecordView(_ view: KeyRecordView, recordedKeyDownWith event: NSEvent) {
    (view == keyRecordView ? keyRecordViewLabel : editFilterKeyRecordViewLabel).stringValue = event.charactersIgnoringModifiers != nil ? event.readableKeyDescription.0 : ""
  }

}


extension FilterWindowController {

  @IBAction func addSavedFilterAction(_ sender: Any) {
    if let currentFilter = currentFilter {
      let filter = SavedFilter(name: saveFilterNameTextField.stringValue,
                               filterString: currentFilter.stringFormat,
                               shortcutKey: keyRecordView.currentKey,
                               modifiers: keyRecordView.currentKeyModifiers)
      savedFilters.append(filter)
      reloadTable()
      syncSavedFilter()
    }
    window!.endSheet(saveFilterSheet)
  }

  @IBAction func cancelSavingFilterAction(_ sender: Any) {
    window!.endSheet(saveFilterSheet)
  }

  @IBAction func saveEditedFilterAction(_ sender: Any) {
    if let currentFilter = currentSavedFilter {
      currentFilter.name = editFilterNameTextField.stringValue
      currentFilter.filterString = editFilterStringTextField.stringValue
      currentFilter.shortcutKey = editFilterKeyRecordView.currentKey
      currentFilter.shortcutKeyModifiers = editFilterKeyRecordView.currentKeyModifiers
      reloadTable()
      syncSavedFilter()
    }
    window!.endSheet(editFilterSheet)
  }

  @IBAction func cancelEditingFilterAction(_ sender: Any) {
    window!.endSheet(editFilterSheet)
  }
}


class NewFilterSheetViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {

  @IBOutlet weak var filterWindow: FilterWindowController!
  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet weak var scrollContentView: NSView!
  @IBOutlet weak var addButton: NSButton!
  
  private var currentPreset: FilterPreset?
  private var currentBindings: [String: NSControl] = [:]
  private var presets: [FilterPreset] = []

  override func awakeFromNib() {
    tableView.dataSource = self
    tableView.delegate = self
    presets = filterWindow.filterType == MPVProperty.vf ? FilterPreset.vfPresets : FilterPreset.afPresets
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return presets.count
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    return presets[at: row]?.localizedName
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard let preset = presets[at: tableView.selectedRow] else { return }
    showSettings(for: preset)
  }

  /** Render parameter controls at right side when selected a filter in the table. */
  func showSettings(for preset: FilterPreset) {
    currentPreset = preset
    currentBindings.removeAll()
    scrollContentView.subviews.forEach { $0.removeFromSuperview() }
    addButton.isEnabled = true

    let stackView = NSStackView()
    stackView.orientation = .vertical
    stackView.alignment = .leading
    stackView.translatesAutoresizingMaskIntoConstraints = false
    scrollContentView.addSubview(stackView)
    Utility.quickConstraints(["H:|-4-[v]-4-|", "V:|-4-[v]-4-|"], ["v": stackView])

    let generateInputs: (String, FilterParameter) -> Void = { (name, param) in
      stackView.addArrangedSubview(self.quickLabel(title: preset.localizedParamName(name)))
      let input = self.quickInput(param: param)
      // For preventing crash due to adding a filter with no name:
      if name == "name", preset.name.starts(with: "custom_"), let textField = input as? NSTextField {
        textField.delegate = self
        self.addButton.isEnabled = !textField.stringValue.isEmpty
      }
      stackView.addArrangedSubview(input)
      self.currentBindings[name] = input
    }
    for name in preset.paramOrder {
      generateInputs(name, preset.params[name]!)
    }
  }

  private func quickLabel(title: String) -> NSTextField {
    let label = NSTextField(frame: NSRect(x: 0, y: 0,
                                          width: scrollContentView.frame.width,
                                          height: 17))
    label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    label.stringValue = title
    label.drawsBackground = false
    label.isBezeled = false
    label.isSelectable = false
    label.isEditable = false
    label.usesSingleLineMode = false
    label.lineBreakMode = .byWordWrapping
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
  }

  /** Create the control from a `FilterParameter` definition. */
  private func quickInput(param: FilterParameter) -> NSControl {
    switch param.type {
    case .text:
      // Text field
      let label = NSTextField(frame: NSRect(x: 0, y: 0,
                              width: scrollContentView.frame.width - 8,
                              height: 22))
      label.stringValue = param.defaultValue.stringValue
      label.isSelectable = false
      label.isEditable = true
      label.lineBreakMode = .byClipping
      label.usesSingleLineMode = true
      label.cell?.isScrollable = true
      return label
    case .int:
      // Slider
      let slider = NSSlider(frame: NSRect(x: 0, y: 0,
                                          width: scrollContentView.frame.width - 8,
                                          height: 19))
      slider.minValue = Double(param.minInt!)
      slider.maxValue = Double(param.maxInt!)
      if let step = param.step {
        slider.numberOfTickMarks = (param.maxInt! - param.minInt!) / step + 1
        slider.allowsTickMarkValuesOnly = true
        slider.frame.size.height = 24
      }
      slider.intValue = Int32(param.defaultValue.intValue)
      return slider
    case .float:
      // Slider
      let slider = NSSlider(frame: NSRect(x: 0, y: 0,
                                          width: scrollContentView.frame.width - 8,
                                          height: 19))
      slider.minValue = Double(param.min!)
      slider.maxValue = Double(param.max!)
      slider.floatValue = param.defaultValue.floatValue
      return slider
    case .choose:
      // Choose
      let popupBtn = NSPopUpButton(frame: NSRect(x: 0, y: 0,
                                                 width: scrollContentView.frame.width - 8,
                                                 height: 26))
      popupBtn.addItems(withTitles: param.choices)
      return popupBtn
    }
  }

  @IBAction func sheetAddBtnAction(_ sender: Any) {
    filterWindow.window!.endSheet(filterWindow.newFilterSheet, returnCode: .OK)
    guard let preset = currentPreset else { return }
    // create instance
    let instance = FilterPresetInstance(from: preset)
    for (name, control) in currentBindings {
      switch preset.params[name]!.type {
      case .text:
        instance.params[name] = FilterParameterValue(string: control.stringValue)
      case .int:
        instance.params[name] = FilterParameterValue(int: Int(control.intValue))
      case .float:
        instance.params[name] = FilterParameterValue(float: control.floatValue)
      case .choose:
        instance.params[name] = FilterParameterValue(string: preset.params[name]!.choices[Int(control.intValue)])
      }
    }
    // create filter
    if filterWindow.addFilter(preset.transformer(instance)) {
      PlayerCore.lastActive.sendOSD(.addFilter(preset.localizedName))
    }
  }

  @IBAction func sheetCancelBtnAction(_ sender: Any) {
    filterWindow.window!.endSheet(filterWindow.newFilterSheet, returnCode: .cancel)
  }

}

/* For preventing crash due to to adding filter with no name */
extension NewFilterSheetViewController: NSTextFieldDelegate {
  func controlTextDidChange(_ obj: Notification) {
    if let textField = obj.object as? NSTextField {
      self.addButton.isEnabled = !textField.stringValue.isEmpty
    }
  }
}
