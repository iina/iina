//
//  UPnPBrowserWindowController.swift
//  iina
//
//  Created for UPnP/DLNA support
//  Copyright © 2024 Contributors. All rights reserved.
//

import Cocoa

class UPnPBrowserWindowController: NSWindowController {
  
  @IBOutlet weak var deviceTableView: NSTableView!
  @IBOutlet weak var contentOutlineView: NSOutlineView!
  @IBOutlet weak var refreshButton: NSButton!
  @IBOutlet weak var playButton: NSButton!
  @IBOutlet weak var statusLabel: NSTextField!
  
  private var devices: [UPnPDevice] = []
  private var contentCache: [String: [UPnPItem]] = [:] // objectID -> items
  private var selectedDevice: UPnPDevice?
  private var selectedItem: UPnPItem?
  private var isLoading = false
  
  private let subsystem = Logger.makeSubsystem("upnp-browser")
  
  convenience init() {
    self.init(windowNibName: "UPnPBrowserWindowController")
  }
  
  override func windowDidLoad() {
    super.windowDidLoad()
    
    setupUI()
    startDiscovery()
  }
  
  private func setupUI() {
    guard let window = window else { return }
    
    window.title = NSLocalizedString("upnp.browser.title", comment: "UPnP/DLNA Browser")
    window.styleMask.insert(.fullSizeContentView)
    
    // Setup table view
    deviceTableView.delegate = self
    deviceTableView.dataSource = self
    deviceTableView.target = self
    deviceTableView.doubleAction = #selector(deviceDoubleClicked)
    
    // Setup outline view
    contentOutlineView.delegate = self
    contentOutlineView.dataSource = self
    contentOutlineView.target = self
    contentOutlineView.doubleAction = #selector(itemDoubleClicked)
    
    // Setup buttons
    playButton.isEnabled = false
    refreshButton.action = #selector(refreshDevices)
    playButton.action = #selector(playSelectedItem)
    
    statusLabel.stringValue = NSLocalizedString("upnp.browser.status.discovering", comment: "Discovering devices...")
  }
  
  @objc private func startDiscovery() {
    guard !isLoading else { return }
    
    isLoading = true
    statusLabel.stringValue = NSLocalizedString("upnp.browser.status.discovering", comment: "Discovering devices...")
    refreshButton.isEnabled = false
    
    UPnPManager.shared.onDeviceDiscovered = { [weak self] device in
      DispatchQueue.main.async {
        self?.deviceDiscovered(device)
      }
    }
    
    UPnPManager.shared.startDiscovery()
    
    // Re-enable refresh after discovery completes
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
      self?.isLoading = false
      self?.refreshButton.isEnabled = true
      let deviceCount = self?.devices.count ?? 0
      self?.statusLabel.stringValue = String(format: NSLocalizedString("upnp.browser.status.found", comment: "Found %d devices"), deviceCount)
    }
  }
  
  @objc private func refreshDevices() {
    devices.removeAll()
    contentCache.removeAll()
    selectedDevice = nil
    selectedItem = nil
    deviceTableView.reloadData()
    contentOutlineView.reloadData()
    playButton.isEnabled = false
    
    UPnPManager.shared.clearDevices()
    startDiscovery()
  }
  
  private func deviceDiscovered(_ device: UPnPDevice) {
    if !devices.contains(where: { $0.id == device.id }) {
      devices.append(device)
      deviceTableView.reloadData()
      Logger.log("Device discovered: \(device.friendlyName)", subsystem: subsystem)
    }
  }
  
  @objc private func deviceDoubleClicked() {
    let row = deviceTableView.clickedRow
    guard row >= 0 && row < devices.count else { return }
    
    let device = devices[row]
    selectedDevice = device
    browseDevice(device)
  }
  
  private func browseDevice(_ device: UPnPDevice) {
    guard device.supportsContentDirectory else {
      statusLabel.stringValue = NSLocalizedString("upnp.browser.status.no_content", comment: "Device does not support content browsing")
      return
    }
    
    statusLabel.stringValue = NSLocalizedString("upnp.browser.status.browsing", comment: "Browsing content...")
    contentCache.removeAll()
    contentOutlineView.reloadData()
    
    Task {
      do {
        let items = try await UPnPManager.shared.browseContent(device: device, objectID: "0")
        await MainActor.run {
          self.contentCache["0"] = items
          self.contentOutlineView.reloadData()
          self.statusLabel.stringValue = String(format: NSLocalizedString("upnp.browser.status.items", comment: "Found %d items"), items.count)
        }
      } catch {
        await MainActor.run {
          self.statusLabel.stringValue = NSLocalizedString("upnp.browser.status.error", comment: "Error: ") + error.localizedDescription
          Logger.log("Failed to browse device: \(error)", level: .error, subsystem: self.subsystem)
        }
      }
    }
  }
  
  private func browseContainer(_ container: UPnPItem, device: UPnPDevice) {
    guard container.isContainer, let device = selectedDevice else { return }
    
    // Check cache first
    if contentCache[container.id] != nil {
      contentOutlineView.reloadItem(container)
      return
    }
    
    statusLabel.stringValue = NSLocalizedString("upnp.browser.status.browsing", comment: "Browsing content...")
    
    Task {
      do {
        let items = try await UPnPManager.shared.browseContent(device: device, objectID: container.id)
        await MainActor.run {
          self.contentCache[container.id] = items
          self.contentOutlineView.reloadItem(container, reloadChildren: true)
          self.statusLabel.stringValue = String(format: NSLocalizedString("upnp.browser.status.items", comment: "Found %d items"), items.count)
        }
      } catch {
        await MainActor.run {
          self.statusLabel.stringValue = NSLocalizedString("upnp.browser.status.error", comment: "Error: ") + error.localizedDescription
          Logger.log("Failed to browse container: \(error)", level: .error, subsystem: self.subsystem)
        }
      }
    }
  }
  
  @objc private func itemDoubleClicked() {
    playSelectedItem()
  }
  
  @objc private func playSelectedItem() {
    guard let item = selectedItem,
          let url = item.resourceURL else {
      return
    }
    
    Logger.log("Playing UPnP item: \(item.title) from \(url)", subsystem: subsystem)
    
    // Close browser window
    window?.close()
    
    // Open in player
    PlayerCore.activeOrNewForMenuAction(isAlternative: false).openURL(url)
  }
}

// MARK: - NSTableViewDataSource & Delegate

extension UPnPBrowserWindowController: NSTableViewDataSource, NSTableViewDelegate {
  
  func numberOfRows(in tableView: NSTableView) -> Int {
    return devices.count
  }
  
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard row < devices.count else { return nil }
    
    let device = devices[row]
    let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("DeviceName")
    
    if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
      if identifier.rawValue == "DeviceName" {
        cell.textField?.stringValue = device.friendlyName
      } else if identifier.rawValue == "DeviceType" {
        cell.textField?.stringValue = device.modelName ?? device.deviceType
      }
      return cell
    }
    
    // Fallback: create a simple text field
    let textField = NSTextField()
    textField.stringValue = device.friendlyName
    textField.isEditable = false
    textField.isBordered = false
    textField.backgroundColor = .clear
    return textField
  }
  
  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = deviceTableView.selectedRow
    guard row >= 0 && row < devices.count else {
      selectedDevice = nil
      contentCache.removeAll()
      contentOutlineView.reloadData()
      return
    }
    
    let device = devices[row]
    selectedDevice = device
    browseDevice(device)
  }
}

// MARK: - NSOutlineViewDataSource & Delegate

extension UPnPBrowserWindowController: NSOutlineViewDataSource, NSOutlineViewDelegate {
  
  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    guard let device = selectedDevice else { return 0 }
    
    if item == nil {
      // Root level - show items from objectID "0"
      return contentCache["0"]?.count ?? 0
    }
    
    if let container = item as? UPnPItem, container.isContainer {
      return contentCache[container.id]?.count ?? 0
    }
    
    return 0
  }
  
  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    if item == nil {
      return contentCache["0"]?[index] ?? UPnPItem(
        id: "",
        title: "Error",
        itemType: .item,
        resourceURL: nil,
        parentID: "0",
        metadata: UPnPItem.ItemMetadata(artist: nil, album: nil, genre: nil, duration: nil, size: nil, mimeType: nil, resolution: nil, bitrate: nil)
      )
    }
    
    if let container = item as? UPnPItem {
      return contentCache[container.id]?[index] ?? UPnPItem(
        id: "",
        title: "Error",
        itemType: .item,
        resourceURL: nil,
        parentID: container.id,
        metadata: UPnPItem.ItemMetadata(artist: nil, album: nil, genre: nil, duration: nil, size: nil, mimeType: nil, resolution: nil, bitrate: nil)
      )
    }
    
    return UPnPItem(
      id: "",
      title: "Error",
      itemType: .item,
      resourceURL: nil,
      parentID: "0",
      metadata: UPnPItem.ItemMetadata(artist: nil, album: nil, genre: nil, duration: nil, size: nil, mimeType: nil, resolution: nil, bitrate: nil)
    )
  }
  
  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    if let container = item as? UPnPItem {
      return container.isContainer
    }
    return false
  }
  
  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    guard let upnpItem = item as? UPnPItem else { return nil }
    
    let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("Title")
    
    if let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
      if identifier.rawValue == "Title" {
        cell.textField?.stringValue = upnpItem.title
        // Add icon for containers
        if upnpItem.isContainer {
          cell.imageView?.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Folder")
        } else {
          cell.imageView?.image = NSImage(systemSymbolName: "play.circle", accessibilityDescription: "Media")
        }
      } else if identifier.rawValue == "Duration" {
        cell.textField?.stringValue = upnpItem.formattedDuration ?? "--:--"
      }
      return cell
    }
    
    // Fallback
    let textField = NSTextField()
    textField.stringValue = upnpItem.title
    textField.isEditable = false
    textField.isBordered = false
    textField.backgroundColor = .clear
    return textField
  }
  
  func outlineViewSelectionDidChange(_ notification: Notification) {
    let selectedRow = contentOutlineView.selectedRow
    guard selectedRow >= 0,
          let item = contentOutlineView.item(atRow: selectedRow) as? UPnPItem else {
      selectedItem = nil
      playButton.isEnabled = false
      return
    }
    
    selectedItem = item
    playButton.isEnabled = item.isPlayable
    
    // Auto-expand containers
    if item.isContainer, let device = selectedDevice {
      browseContainer(item, device: device)
    }
  }
}

