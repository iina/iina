//
//  UPnPBrowserWindowController.swift
//  iina
//
//  Created for UPnP/DLNA support
//  Copyright © 2024 Contributors. All rights reserved.
//

import Cocoa

class UPnPBrowserWindowController: NSWindowController {
  
  @IBOutlet weak var favoritesTableView: NSTableView?
  @IBOutlet weak var deviceTableView: NSTableView?
  @IBOutlet weak var contentOutlineView: NSOutlineView?
  @IBOutlet weak var refreshButton: NSButton?
  @IBOutlet weak var playButton: NSButton?
  @IBOutlet weak var statusLabel: NSTextField?
  
  private var devices: [UPnPDevice] = []
  private var contentCache: [String: [UPnPItem]] = [:] // objectID -> items
  private var selectedDevice: UPnPDevice?
  private var selectedItem: UPnPItem?
  private var isLoading = false
  private var favorites: [UPnPFavorite] = []
  /// The container whose contents are currently shown in the outline view.
  /// - "0" = device root, or flattened favorite root.
  private var currentContainerID: String = "0"
  /// Timer to monitor playback position and trigger auto-play next when near EOF.
  private var autoPlayTimer: Timer?
  /// Timer to periodically refresh the current folder content
  private var autoRefreshTimer: Timer?
  
  // Track current playback context for auto-play next
  private var currentPlaybackContext: UPnPPlaybackContext?
  
  /// Flag to prevent re-entrant auto-play calls (cascade prevention)
  private var isAutoPlayingNext = false
  
  private let subsystem = Logger.makeSubsystem("upnp-browser")
  
  struct UPnPPlaybackContext: Codable {
    let deviceID: String
    let containerID: String
    let currentItemID: String
    let currentItemURL: String
    let allItems: [UPnPPlaybackItem] // All playable items in current context
  }
  
  struct UPnPPlaybackItem: Codable {
    let id: String
    let title: String
    let url: String
  }
  
  struct UPnPFavorite: Codable {
    let deviceID: String
    let deviceName: String
    let containerID: String
    let containerTitle: String
    let containerPath: String // Full path for display
  }
  
  override var windowNibName: NSNib.Name {
    return NSNib.Name("UPnPBrowserWindowController")
  }
  
  override func windowDidLoad() {
    super.windowDidLoad()
    
    Logger.log("UPnP browser windowDidLoad called", subsystem: subsystem)
    loadFavorites()
    createUI()
    setupUI()
    startDiscovery()
    startAutoRefreshIfNeeded()
    
    // Listen for player stopped (when window closes) to reopen browser if needed
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handlePlayerStopped),
      name: .iinaPlayerStopped,
      object: nil
    )
    
    // Listen for file loaded to restart auto-play monitor after transitioning to next video
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleFileLoaded),
      name: .iinaFileLoaded,
      object: nil
    )
  }
  
  deinit {
    NotificationCenter.default.removeObserver(self)
    stopAutoPlay()
    stopAutoRefresh()
  }
  
  /// Stop auto-play monitoring and clear flags (called when window closes or player stops)
  private func stopAutoPlay() {
    autoPlayTimer?.invalidate()
    autoPlayTimer = nil
    isAutoPlayingNext = false
    Logger.log("Stopped auto-play monitoring", subsystem: subsystem)
  }
  
  /// Stop auto-refresh timer
  private func stopAutoRefresh() {
    autoRefreshTimer?.invalidate()
    autoRefreshTimer = nil
  }
  
  
  override func showWindow(_ sender: Any?) {
    // Access window to trigger loading if not already loaded - this will call windowDidLoad()
    guard let _ = self.window else {
      Logger.log("ERROR: UPnP browser window is nil!", level: .error, subsystem: subsystem)
      return
    }
    super.showWindow(sender)
  }
  
  private func createUI() {
    guard let window = window, let contentView = window.contentView else {
      Logger.log("ERROR: createUI - window or contentView is nil!", level: .error, subsystem: subsystem)
      return
    }
    
    Logger.log("createUI called - contentView frame: \(contentView.frame)", subsystem: subsystem)
    
    // Remove existing subviews if any
    contentView.subviews.forEach { $0.removeFromSuperview() }
    
    // Create main container
    let containerView = NSView()
    containerView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(containerView)
    
    // Create main split view (devices | content)
    let splitView = NSSplitView()
    splitView.dividerStyle = .thin
    splitView.isVertical = true
    splitView.translatesAutoresizingMaskIntoConstraints = false
    
    // Create left panel container (devices + favorites stacked vertically)
    let leftPanel = NSView()
    leftPanel.translatesAutoresizingMaskIntoConstraints = false
    
    // Device list section (top)
    let deviceHeaderLabel = NSTextField(labelWithString: NSLocalizedString("upnp.browser.device_list", comment: "UPnP/DLNA Device List"))
    deviceHeaderLabel.font = NSFont.boldSystemFont(ofSize: 13)
    deviceHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
    leftPanel.addSubview(deviceHeaderLabel)
    
    let deviceScrollView = NSScrollView()
    deviceScrollView.hasVerticalScroller = true
    deviceScrollView.hasHorizontalScroller = false
    deviceScrollView.autohidesScrollers = true
    deviceScrollView.borderType = .noBorder
    
    let deviceTable = NSTableView()
    deviceTable.headerView = nil
    let deviceColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("DeviceName"))
    deviceColumn.title = NSLocalizedString("upnp.browser.device_list", comment: "UPnP/DLNA Device List")
    deviceColumn.width = 280
    deviceTable.addTableColumn(deviceColumn)
    
    deviceScrollView.documentView = deviceTable
    deviceScrollView.translatesAutoresizingMaskIntoConstraints = false
    leftPanel.addSubview(deviceScrollView)
    
    // Favorites section (below devices)
    let favoritesHeaderLabel = NSTextField(labelWithString: NSLocalizedString("upnp.browser.favorites", comment: "Favorites"))
    favoritesHeaderLabel.font = NSFont.boldSystemFont(ofSize: 13)
    favoritesHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
    leftPanel.addSubview(favoritesHeaderLabel)
    
    let favoritesScrollView = NSScrollView()
    favoritesScrollView.hasVerticalScroller = true
    favoritesScrollView.hasHorizontalScroller = false
    favoritesScrollView.autohidesScrollers = true
    favoritesScrollView.borderType = .noBorder
    
    let favoritesTable = NSTableView()
    favoritesTable.headerView = nil
    let favoritesColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FavoriteName"))
    favoritesColumn.title = NSLocalizedString("upnp.browser.favorites", comment: "Favorites")
    favoritesColumn.width = 280
    favoritesTable.addTableColumn(favoritesColumn)
    
    favoritesScrollView.documentView = favoritesTable
    favoritesScrollView.translatesAutoresizingMaskIntoConstraints = false
    leftPanel.addSubview(favoritesScrollView)
    
    // Layout for left panel (devices on top, favorites below)
    NSLayoutConstraint.activate([
      // Device header
      deviceHeaderLabel.topAnchor.constraint(equalTo: leftPanel.topAnchor, constant: 8),
      deviceHeaderLabel.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor, constant: 8),
      deviceHeaderLabel.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor, constant: -8),
      
      // Device scroll view
      deviceScrollView.topAnchor.constraint(equalTo: deviceHeaderLabel.bottomAnchor, constant: 4),
      deviceScrollView.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
      deviceScrollView.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
      deviceScrollView.heightAnchor.constraint(equalTo: leftPanel.heightAnchor, multiplier: 0.5, constant: -30), // 50% height minus headers
      
      // Favorites header
      favoritesHeaderLabel.topAnchor.constraint(equalTo: deviceScrollView.bottomAnchor, constant: 8),
      favoritesHeaderLabel.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor, constant: 8),
      favoritesHeaderLabel.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor, constant: -8),
      
      // Favorites scroll view
      favoritesScrollView.topAnchor.constraint(equalTo: favoritesHeaderLabel.bottomAnchor, constant: 4),
      favoritesScrollView.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
      favoritesScrollView.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
      favoritesScrollView.bottomAnchor.constraint(equalTo: leftPanel.bottomAnchor)
    ])
    
    // Create content outline view (right side)
    let contentScrollView = NSScrollView()
    contentScrollView.hasVerticalScroller = true
    contentScrollView.hasHorizontalScroller = false
    contentScrollView.autohidesScrollers = true
    contentScrollView.borderType = .noBorder
    
    let contentOutline = NSOutlineView()
    
    // Title column (always visible)
    let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Title"))
    titleColumn.title = NSLocalizedString("upnp.browser.column.title", comment: "Title")
    titleColumn.sortDescriptorPrototype = NSSortDescriptor(key: "title", ascending: true)
    titleColumn.width = 500
    titleColumn.minWidth = 200
    titleColumn.isHidden = false
    contentOutline.addTableColumn(titleColumn)
    
    // Duration column
    let durationColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Duration"))
    durationColumn.title = NSLocalizedString("upnp.browser.column.duration", comment: "Duration")
    durationColumn.sortDescriptorPrototype = NSSortDescriptor(key: "duration", ascending: true)
    durationColumn.width = 120
    durationColumn.minWidth = 80
    durationColumn.isHidden = Preference.bool(for: .upnpColumnDurationHidden)
    contentOutline.addTableColumn(durationColumn)
    
    // Date column
    let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Date"))
    dateColumn.title = NSLocalizedString("upnp.browser.column.date", comment: "Date")
    dateColumn.sortDescriptorPrototype = NSSortDescriptor(key: "date", ascending: true)
    dateColumn.width = 120
    dateColumn.minWidth = 80
    dateColumn.isHidden = Preference.bool(for: .upnpColumnDateHidden)
    contentOutline.addTableColumn(dateColumn)
    
    // Author column
    let authorColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Author"))
    authorColumn.title = NSLocalizedString("upnp.browser.column.author", comment: "Author")
    authorColumn.width = 150
    authorColumn.minWidth = 100
    authorColumn.isHidden = Preference.bool(for: .upnpColumnAuthorHidden)
    contentOutline.addTableColumn(authorColumn)
    
    // Description column
    let descriptionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Description"))
    descriptionColumn.title = NSLocalizedString("upnp.browser.column.description", comment: "Description")
    descriptionColumn.width = 200
    descriptionColumn.minWidth = 120
    descriptionColumn.isHidden = Preference.bool(for: .upnpColumnDescriptionHidden)
    contentOutline.addTableColumn(descriptionColumn)
    
    // File Size column
    let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Size"))
    sizeColumn.title = NSLocalizedString("upnp.browser.column.size", comment: "Size")
    sizeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: true)
    sizeColumn.width = 100
    sizeColumn.minWidth = 80
    sizeColumn.isHidden = Preference.bool(for: .upnpColumnSizeHidden)
    contentOutline.addTableColumn(sizeColumn)
    
    // Type column (MIME type)
    let typeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Type"))
    typeColumn.title = NSLocalizedString("upnp.browser.column.type", comment: "Type")
    typeColumn.width = 120
    typeColumn.minWidth = 80
    typeColumn.isHidden = Preference.bool(for: .upnpColumnTypeHidden)
    contentOutline.addTableColumn(typeColumn)
    
    contentOutline.outlineTableColumn = titleColumn
    
    contentScrollView.documentView = contentOutline
    contentScrollView.translatesAutoresizingMaskIntoConstraints = false
    
    // Add views to main split view (left panel | content)
    splitView.addSubview(leftPanel)
    splitView.addSubview(contentScrollView)
    
    // Create bottom panel
    let bottomPanel = NSView()
    bottomPanel.translatesAutoresizingMaskIntoConstraints = false
    
    let statusLabel = NSTextField(labelWithString: NSLocalizedString("upnp.browser.status.discovering", comment: "Discovering devices…"))
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    bottomPanel.addSubview(statusLabel)
    
    // Create refresh button with menu for options
    let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshCurrentFolder))
    refreshButton.bezelStyle = .rounded
    refreshButton.translatesAutoresizingMaskIntoConstraints = false
    refreshButton.imagePosition = .imageLeading
    // Add menu for refresh options
    let refreshMenu = NSMenu()
    refreshMenu.addItem(NSMenuItem(title: NSLocalizedString("upnp.browser.refresh.current_folder", comment: "Refresh Current Folder"), action: #selector(refreshCurrentFolder), keyEquivalent: ""))
    refreshMenu.addItem(NSMenuItem(title: NSLocalizedString("upnp.browser.refresh.all_devices", comment: "Refresh All Devices"), action: #selector(refreshDevices), keyEquivalent: ""))
    refreshMenu.addItem(NSMenuItem.separator())
    refreshMenu.addItem(NSMenuItem(title: NSLocalizedString("upnp.browser.refresh.settings", comment: "Auto-Refresh Settings..."), action: #selector(showAutoRefreshSettings), keyEquivalent: ""))
    refreshButton.menu = refreshMenu
    bottomPanel.addSubview(refreshButton)
    
    let playButton = NSButton(title: NSLocalizedString("upnp.browser.menu.play", comment: "Play"), target: self, action: #selector(playSelectedItem))
    playButton.bezelStyle = .rounded
    playButton.isEnabled = false
    playButton.translatesAutoresizingMaskIntoConstraints = false
    bottomPanel.addSubview(playButton)
    
    // Add to container
    containerView.addSubview(splitView)
    containerView.addSubview(bottomPanel)
    
    // Set outlets
    self.favoritesTableView = favoritesTable
    self.deviceTableView = deviceTable
    self.contentOutlineView = contentOutline
    self.refreshButton = refreshButton
    self.playButton = playButton
    self.statusLabel = statusLabel
    
    // Layout constraints
    NSLayoutConstraint.activate([
      // Container
      containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
      containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      
      // Split view
      splitView.topAnchor.constraint(equalTo: containerView.topAnchor),
      splitView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      splitView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      splitView.bottomAnchor.constraint(equalTo: bottomPanel.topAnchor),
      
      // Left panel (devices + favorites)
      leftPanel.widthAnchor.constraint(equalToConstant: 280),
      
      // Bottom panel
      bottomPanel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      bottomPanel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      bottomPanel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
      bottomPanel.heightAnchor.constraint(equalToConstant: 40),
      
      // Status label
      statusLabel.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor, constant: 12),
      statusLabel.centerYAnchor.constraint(equalTo: bottomPanel.centerYAnchor),
      
      // Refresh button
      refreshButton.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -8),
      refreshButton.centerYAnchor.constraint(equalTo: bottomPanel.centerYAnchor),
      refreshButton.widthAnchor.constraint(equalToConstant: 70),
      
      // Play button
      playButton.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor, constant: -12),
      playButton.centerYAnchor.constraint(equalTo: bottomPanel.centerYAnchor),
      playButton.widthAnchor.constraint(equalToConstant: 60),
      
      // Status label trailing
      statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -8)
    ])
    
    Logger.log("createUI completed - containerView frame: \(containerView.frame), subviews: \(containerView.subviews.count)", subsystem: subsystem)
    
    // Force layout update
    containerView.needsLayout = true
    containerView.layoutSubtreeIfNeeded()
  }
  
  private func setupUI() {
    guard let window = window else { return }
    
    window.title = NSLocalizedString("upnp.browser.title", comment: "UPnP/DLNA Browser")
    window.styleMask.insert(.fullSizeContentView)
    
    // Setup device table view
    if let tableView = deviceTableView {
      tableView.delegate = self
      tableView.dataSource = self
      tableView.target = self
      tableView.doubleAction = #selector(deviceDoubleClicked)
    }
    
    // Setup favorites table view (single-click to open)
    if let tableView = favoritesTableView {
      tableView.delegate = self
      tableView.dataSource = self
      tableView.target = self
      tableView.action = #selector(favoriteClicked)
    }
    
    // Setup outline view
    if let outlineView = contentOutlineView {
      outlineView.delegate = self
      outlineView.dataSource = self
      outlineView.target = self
      outlineView.doubleAction = #selector(itemDoubleClicked)
      // Enable context menu
      let menu = NSMenu()
      menu.delegate = self as NSMenuDelegate
      outlineView.menu = menu
      // Track selection changes
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(outlineViewSelectionDidChange),
        name: NSOutlineView.selectionDidChangeNotification,
        object: outlineView
      )
    }
    
    // Setup buttons
    playButton?.isEnabled = false
    refreshButton?.action = #selector(refreshDevices)
    playButton?.action = #selector(playSelectedItem)
    
    statusLabel?.stringValue = NSLocalizedString("upnp.browser.status.discovering", comment: "Discovering devices...")
  }
  
  @objc private func startDiscovery() {
    guard !isLoading else { return }
    
    isLoading = true
    statusLabel?.stringValue = NSLocalizedString("upnp.browser.status.discovering", comment: "Discovering devices...")
    refreshButton?.isEnabled = false
    
    UPnPManager.shared.onDeviceDiscovered = { [weak self] device in
      DispatchQueue.main.async {
        self?.deviceDiscovered(device)
      }
    }
    
    UPnPManager.shared.startDiscovery()
    
    // Re-enable refresh after discovery completes
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
      self?.isLoading = false
      self?.refreshButton?.isEnabled = true
      let deviceCount = self?.devices.count ?? 0
      self?.statusLabel?.stringValue = String(format: NSLocalizedString("upnp.browser.status.found", comment: "Found %d devices"), deviceCount)
    }
  }
  
  @objc private func refreshDevices() {
    devices.removeAll()
    contentCache.removeAll()
    selectedDevice = nil
    selectedItem = nil
    deviceTableView?.reloadData()
    contentOutlineView?.reloadData()
    playButton?.isEnabled = false
    
    UPnPManager.shared.clearDevices()
    startDiscovery()
    // Restart auto-refresh after device refresh
    startAutoRefreshIfNeeded()
  }
  
  /// Refresh the current folder/container being viewed
  @objc private func refreshCurrentFolder() {
    guard let device = selectedDevice else {
      // If no device selected, refresh devices instead
      refreshDevices()
      return
    }
    
    // If we're viewing a favorite, refresh that container
    if currentContainerID != "0" {
      // Find the container item
      if let containerItems = contentCache.values.first(where: { items in
        items.contains(where: { $0.id == currentContainerID })
      }),
         let container = containerItems.first(where: { $0.id == currentContainerID }) {
        Logger.log("Refreshing current container: \(container.title) (ID: \(currentContainerID))", subsystem: subsystem)
        // Clear cache for this container to force reload
        contentCache.removeValue(forKey: currentContainerID)
        browseContainer(container, device: device)
        return
      }
    }
    
    // Otherwise refresh the device root
    Logger.log("Refreshing device root", subsystem: subsystem)
    contentCache.removeValue(forKey: "0")
    browseDevice(device)
  }
  
  private func deviceDiscovered(_ device: UPnPDevice) {
    if !devices.contains(where: { $0.id == device.id }) {
      devices.append(device)
      deviceTableView?.reloadData()
      Logger.log("Device discovered: \(device.friendlyName)", subsystem: subsystem)
    }
  }
  
  @objc private func deviceDoubleClicked() {
    guard let tableView = deviceTableView else { return }
    let row = tableView.clickedRow
    guard row >= 0 && row < devices.count else { return }
    
    let device = devices[row]
    selectedDevice = device
    browseDevice(device)
  }
  
  private func browseDevice(_ device: UPnPDevice) {
    guard device.supportsContentDirectory else {
      statusLabel?.stringValue = NSLocalizedString("upnp.browser.status.no_content", comment: "Device does not support content browsing")
      return
    }
    
    statusLabel?.stringValue = NSLocalizedString("upnp.browser.status.browsing", comment: "Browsing content...")
    // Reset cache and set current container to root
    contentCache.removeAll()
    currentContainerID = "0"
    contentOutlineView?.reloadData()
    
    Task {
      do {
        let items = try await UPnPManager.shared.browseContent(device: device, objectID: "0")
        await MainActor.run {
          self.contentCache["0"] = items
          self.contentOutlineView?.reloadData()
          self.statusLabel?.stringValue = String(format: NSLocalizedString("upnp.browser.status.items", comment: "Found %d items"), items.count)
          // Restart auto-refresh when browsing a new container
          self.startAutoRefreshIfNeeded()
        }
      } catch {
        await MainActor.run {
          self.statusLabel?.stringValue = NSLocalizedString("upnp.browser.status.error", comment: "Error: ") + error.localizedDescription
          Logger.log("Failed to browse device: \(error)", level: .error, subsystem: self.subsystem)
        }
      }
    }
  }
  
  /// Recursively load all items from a container and its subfolders
  private func loadAllItemsRecursively(device: UPnPDevice, containerID: String, maxDepth: Int, currentDepth: Int = 0) async throws -> [UPnPItem] {
    guard currentDepth < maxDepth else { return [] }
    
    var allItems: [UPnPItem] = []
    let items = try await UPnPManager.shared.browseContent(device: device, objectID: containerID)
    
    for item in items {
      if item.isContainer {
        // Recursively load subfolder contents
        let subItems = try await loadAllItemsRecursively(device: device, containerID: item.id, maxDepth: maxDepth, currentDepth: currentDepth + 1)
        allItems.append(contentsOf: subItems)
      } else {
        // Add file directly
        allItems.append(item)
      }
    }
    
    return allItems
  }
  
  private func browseContainer(_ container: UPnPItem, device: UPnPDevice) {
    guard container.isContainer else { 
      Logger.log("browseContainer called on non-container item: \(container.title)", level: .error, subsystem: subsystem)
      return 
    }
    
    guard let device = selectedDevice else {
      Logger.log("No device selected for browsing container", level: .error, subsystem: subsystem)
      return
    }
    
    Logger.log("Browsing container '\(container.title)' (ID: \(container.id))", subsystem: subsystem)
    
    // Update current container ID
    currentContainerID = container.id
    
    // Check cache first - if already loaded and not empty, just reload and expand
    if let cachedItems = contentCache[container.id], !cachedItems.isEmpty {
      Logger.log("Container already cached with \(cachedItems.count) items, reloading and expanding", subsystem: subsystem)
      contentOutlineView?.reloadItem(container, reloadChildren: true)
      contentOutlineView?.expandItem(container)
      // Restart auto-refresh when browsing a container
      startAutoRefreshIfNeeded()
      return
    }
    
    statusLabel?.stringValue = NSLocalizedString("upnp.browser.status.browsing", comment: "Browsing content...")
    
    Task {
      do {
        let items = try await UPnPManager.shared.browseContent(device: device, objectID: container.id)
        await MainActor.run {
          Logger.log("Loaded \(items.count) items from container '\(container.title)' (ID: \(container.id))", subsystem: subsystem)
          
          // Store items in cache with their original parent ID
          self.contentCache[container.id] = items
          
          // Reload the container and its children
          self.contentOutlineView?.reloadItem(container, reloadChildren: true)
          
          // Expand the container to show children
          self.contentOutlineView?.expandItem(container)
          
          self.statusLabel?.stringValue = String(format: NSLocalizedString("upnp.browser.status.items", comment: "Found %d items"), items.count)
          // Restart auto-refresh when browsing a container
          self.startAutoRefreshIfNeeded()
        }
      } catch {
        await MainActor.run {
          self.statusLabel?.stringValue = NSLocalizedString("upnp.browser.status.error", comment: "Error: ") + error.localizedDescription
          Logger.log("Failed to browse container '\(container.title)' (ID: \(container.id)): \(error)", level: .error, subsystem: self.subsystem)
        }
      }
    }
  }
  
  @objc func outlineViewSelectionDidChange(_ notification: Notification) {
    guard let outlineView = notification.object as? NSOutlineView else { return }
    let selectedRow = outlineView.selectedRow
    if selectedRow >= 0, let item = outlineView.item(atRow: selectedRow) as? UPnPItem {
      selectedItem = item
      playButton?.isEnabled = item.isPlayable
    } else {
      selectedItem = nil
      playButton?.isEnabled = false
    }
  }
  
  @objc private func itemDoubleClicked() {
    // Get the clicked item from the outline view
    guard let outlineView = contentOutlineView else { return }
    let clickedRow = outlineView.clickedRow
    guard clickedRow >= 0,
          let item = outlineView.item(atRow: clickedRow) as? UPnPItem else {
      return
    }
    
    // Update selectedItem and selection
    selectedItem = item
    outlineView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
    
    // Play the item
    playSelectedItem()
  }
  
  /// Prepare a player for UPnP playback by disabling watch-later resume and resetting speed.
  /// mpv's watch-later files store `speed` and `start` position. DLNA servers may redirect URLs
  /// or reuse object IDs, so the watch-later hash may not match the original URL we have.
  /// The only reliable approach is to disable `resume-playback` entirely for UPnP files.
  private func preparePlayerForUPnPPlayback(_ player: PlayerCore, url: URL, title: String) {
    // Disable resume-playback BEFORE loadfile so mpv won't read any watch-later file.
    // This prevents stale speed, volume, and position from being restored.
    // (Will be re-enabled in handleFileLoaded after the file starts playing.)
    player.mpv.setFlag(MPVOption.WatchLater.resumePlayback, false)
    Logger.log("Disabled resume-playback for UPnP file load", subsystem: subsystem)
    
    // Reset speed to 1x to prevent speed carrying over from a previous file
    // on the same player instance (mpv's speed property persists across loadfile calls)
    player.mpv.setDouble(MPVOption.PlaybackControl.speed, 1.0)
    Logger.log("Reset playback speed to 1.0 for UPnP file", subsystem: subsystem)
    
    // Best-effort: delete any existing watch-later file for this URL.
    // This may not match if the server redirected to a different URL, but it cleans up
    // the common case where the URL is stable.
    let urlString = url.absoluteString
    let md5 = urlString.md5
    let watchLaterFile = Utility.watchLaterURL.appendingPathComponent(md5)
    if FileManager.default.fileExists(atPath: watchLaterFile.path) {
      do {
        try FileManager.default.removeItem(at: watchLaterFile)
        Logger.log("Deleted stale watch-later file for UPnP URL (md5: \(md5))", subsystem: subsystem)
      } catch {
        Logger.log("Failed to delete watch-later file: \(error)", level: .warning, subsystem: subsystem)
      }
    }
    
    // Set force-media-title before opening
    if !title.isEmpty {
      player.mpv.setString(MPVOption.Miscellaneous.forceMediaTitle, title)
    }
  }
  
  @objc private func playSelectedItem() {
    // Get the actually selected item from the outline view
    guard let outlineView = contentOutlineView else { return }
    let selectedRow = outlineView.selectedRow
    guard selectedRow >= 0,
          let item = outlineView.item(atRow: selectedRow) as? UPnPItem,
          let url = item.resourceURL,
          let device = selectedDevice else {
      Logger.log("No valid item selected for playback", subsystem: subsystem)
      return
    }
    
    // Update selectedItem for consistency
    selectedItem = item
    
    Logger.log("Playing UPnP item: \(item.title) (ID: \(item.id)) from \(url)", subsystem: subsystem)
    
    // Find the actual parent container for this item
    // If item.parentID is "0", it means it's at root level, otherwise it's in a subfolder
    let parentContainerID = item.parentID == "0" ? currentContainerID : item.parentID
    
    // Get all playable items from the parent container
    var playableItems: [UPnPItem] = []
    if let containerItems = contentCache[parentContainerID] {
      playableItems = containerItems.filter { $0.isPlayable }
    } else if let rootItems = contentCache["0"] {
      // Fallback: if parent container not found, try root
      playableItems = rootItems.filter { $0.isPlayable && $0.parentID == item.parentID }
    }
    
    // Sort by title using natural (numeric-aware) sorting for intelligent continuation
    // This ensures "episode 1" < "episode 2" < "episode 12" (not "episode 12" < "episode 2")
    playableItems.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    
    Logger.log("Found \(playableItems.count) playable items in container '\(parentContainerID)' (item parentID: \(item.parentID))", subsystem: subsystem)
    Logger.log("Playable items: \(playableItems.map { $0.title }.joined(separator: ", "))", subsystem: subsystem)
    
    // Store playback context
    let playbackItems = playableItems.map { UPnPPlaybackItem(id: $0.id, title: $0.title, url: $0.resourceURL?.absoluteString ?? "") }
    currentPlaybackContext = UPnPPlaybackContext(
      deviceID: device.id,
      containerID: parentContainerID,
      currentItemID: item.id,
      currentItemURL: url.absoluteString,
      allItems: playbackItems
    )
    savePlaybackContext()
    Logger.log("Saved UPnP playback context: deviceID=\(device.id), itemID=\(item.id), itemTitle='\(item.title)', URL=\(url.absoluteString), totalItems=\(playbackItems.count)", subsystem: subsystem)
    
    // Verify the context was saved correctly
    if let savedContext = loadPlaybackContext() {
      Logger.log("Verified saved context: currentItemID=\(savedContext.currentItemID), currentItemTitle='\(savedContext.allItems.first(where: { $0.id == savedContext.currentItemID })?.title ?? "NOT FOUND")'", subsystem: subsystem)
    }
    
    // Handle browser behavior
    let browserBehavior = Preference.integer(for: .upnpBrowserBehavior)
    if browserBehavior == 0 {
      // Close browser
      window?.close()
    } else if browserBehavior == 1 || browserBehavior == 2 {
      // Keep browser open in background (will be shown again when player stops)
      window?.orderOut(nil)
    }
    
    // Open in player - prepare player for UPnP playback (reset speed, clear watch-later, set title)
    let player = PlayerCore.activeOrNewForMenuAction(isAlternative: false)
    preparePlayerForUPnPPlayback(player, url: url, title: item.title)
    
    player.openURL(url)
    
    // Start monitoring for auto-play-next
    startAutoPlayMonitor()
    
    // Also set window title after opening as backup
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      if let mainWindow = player.mainWindow {
        mainWindow.window?.title = item.title
      }
    }
  }
  
  
  /// Save playback context to preferences
  private func savePlaybackContext() {
    guard let context = currentPlaybackContext,
          let data = try? JSONEncoder().encode(context) else { return }
    Preference.set(data, for: .upnpPlaybackContext)
  }
  
  /// Load playback context from preferences
  private func loadPlaybackContext() -> UPnPPlaybackContext? {
    guard let data = Preference.data(for: .upnpPlaybackContext) else {
      Logger.log("No UPnP playback context data in preferences", subsystem: subsystem)
      return nil
    }
    guard let context = try? JSONDecoder().decode(UPnPPlaybackContext.self, from: data) else {
      Logger.log("Failed to decode UPnP playback context from preferences", level: .error, subsystem: subsystem)
      return nil
    }
    Logger.log("Loaded UPnP playback context: deviceID=\(context.deviceID), itemID=\(context.currentItemID), URL=\(context.currentItemURL), totalItems=\(context.allItems.count)", subsystem: subsystem)
    return context
  }
  
  /// Handle file ended - auto-play next
  @objc private func handleFileEnded(_ notification: Notification) {
    Logger.log("handleFileEnded called, autoPlayNext: \(Preference.bool(for: .upnpAutoPlayNext)), isAutoPlayingNext: \(isAutoPlayingNext)", subsystem: subsystem)
    
    // Prevent re-entrancy - if we're already auto-playing, ignore this notification
    guard !isAutoPlayingNext else {
      Logger.log("Ignoring fileEnded notification - already auto-playing next", subsystem: subsystem)
      return
    }
    
    guard Preference.bool(for: .upnpAutoPlayNext) else {
      Logger.log("Auto-play next is disabled", subsystem: subsystem)
      return
    }
    
    // Delegate to playNextUPnPItem which has the re-entrancy guard
    // Note: PlayerCore.fileEnded() also calls playNextUPnPItem() directly,
    // so this notification handler is a backup/alternative path
    playNextUPnPItem()
  }
  
  /// Start or restart timer to monitor playback and trigger auto-play-next when near EOF.
  private func startAutoPlayMonitor() {
    autoPlayTimer?.invalidate()
    
    guard Preference.bool(for: .upnpAutoPlayNext) else { return }
    
    autoPlayTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkAutoPlayNextIfNeeded), userInfo: nil, repeats: true)
  }
  
  /// Periodically check if current UPnP item is at/near end and advance to next.
  @objc private func checkAutoPlayNextIfNeeded() {
    guard Preference.bool(for: .upnpAutoPlayNext),
          let context = currentPlaybackContext ?? loadPlaybackContext() else {
      return
    }
    
    let player = PlayerCore.lastActive
    
    // Check if EOF is reached (more reliable than position calculation)
    let eofReached = player.mpv.getFlag(MPVProperty.eofReached)
    
    // Get duration and position as backup
    let durationSeconds = player.info.videoDuration?.second ?? player.mpv.getDouble(MPVProperty.duration)
    let pos = player.mpv.getDouble(MPVProperty.timePos)
    
    // Check if we're at EOF or very close to the end
    let atEnd: Bool
    if eofReached {
      atEnd = true
    } else if durationSeconds > 0 && pos >= 0 {
      let remaining = durationSeconds - pos
      atEnd = remaining <= 1.0
    } else {
      return
    }
    
    if atEnd {
      // Ensure there is actually a "next" item
      guard let currentIndex = context.allItems.firstIndex(where: { $0.id == context.currentItemID }),
            currentIndex + 1 < context.allItems.count else {
        autoPlayTimer?.invalidate()
        autoPlayTimer = nil
        return
      }
      
      Logger.log("Auto-play monitor detected EOF (eofReached=\(eofReached), remaining=\(durationSeconds > 0 && pos >= 0 ? durationSeconds - pos : -1)s), advancing to next UPnP item", subsystem: subsystem)
      autoPlayTimer?.invalidate()
      autoPlayTimer = nil
      playNextUPnPItem()
    }
  }
  
  /// Play next UPnP item (called from next button or menu)
  func playNextUPnPItem() {
    Logger.log("playNextUPnPItem called, isAutoPlayingNext: \(isAutoPlayingNext)", subsystem: subsystem)
    
    // Check if player is stopping - don't auto-play if user closed the window
    // Note: We don't check for .idle here because when a video naturally ends, the state
    // might be .idle, but we should still auto-play. Only block if explicitly stopping.
    let player = PlayerCore.lastActive
    if player.info.state == .stopping || player.info.state == .shuttingDown || player.info.state == .shutDown {
      Logger.log("Ignoring playNextUPnPItem - player is stopping/shutting down (state: \(player.info.state))", subsystem: subsystem)
      stopAutoPlay()
      return
    }
    
    // Prevent re-entrancy - if we're already auto-playing, ignore this call
    guard !isAutoPlayingNext else {
      Logger.log("Ignoring playNextUPnPItem - already auto-playing next", subsystem: subsystem)
      return
    }
    
    let context = currentPlaybackContext ?? loadPlaybackContext()
    guard let context = context else {
      Logger.log("No UPnP playback context found for next button", subsystem: subsystem)
      return
    }
    
    // Find next item
    guard let currentIndex = context.allItems.firstIndex(where: { $0.id == context.currentItemID }) else {
      Logger.log("Current item (ID: \(context.currentItemID)) not found in context for next button. Available IDs: \(context.allItems.map { $0.id }.joined(separator: ", "))", subsystem: subsystem)
      return
    }
    
    guard currentIndex + 1 < context.allItems.count else {
      Logger.log("No next item available (currentIndex: \(currentIndex), total: \(context.allItems.count))", subsystem: subsystem)
      return
    }
    
    let nextItem = context.allItems[currentIndex + 1]
    Logger.log("Next item: '\(nextItem.title)' (ID: \(nextItem.id)) at index \(currentIndex + 1)", subsystem: subsystem)
    guard let nextURL = URL(string: nextItem.url) else { return }
    
    Logger.log("Playing next UPnP item via button: \(nextItem.title)", subsystem: subsystem)
    
    // Set flag to prevent re-entrancy
    isAutoPlayingNext = true
    
    // Update context
    currentPlaybackContext = UPnPPlaybackContext(
      deviceID: context.deviceID,
      containerID: context.containerID,
      currentItemID: nextItem.id,
      currentItemURL: nextItem.url,
      allItems: context.allItems
    )
    savePlaybackContext()
    
    // Prepare player for UPnP playback (reset speed, clear watch-later, set title)
    preparePlayerForUPnPPlayback(player, url: nextURL, title: nextItem.title)
    
    player.openURL(nextURL)
    
    // Restart monitoring for auto-play-next on the new item
    startAutoPlayMonitor()
    
    // Set window title
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      guard let self = self else { return }
      if let mainWindow = player.mainWindow {
        mainWindow.window?.title = nextItem.title
      }
    }
    
    // Reset flag after a delay to allow file to start loading
    // This prevents cascading when openURL triggers fileEnded
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
      self.isAutoPlayingNext = false
      Logger.log("Reset isAutoPlayingNext flag", subsystem: self.subsystem)
    }
  }
  
  /// Play previous UPnP item (called from previous button or menu)
  func playPreviousUPnPItem() {
    Logger.log("playPreviousUPnPItem called", subsystem: subsystem)
    
    let context = currentPlaybackContext ?? loadPlaybackContext()
    guard let context = context else {
      Logger.log("No UPnP playback context found for previous button", subsystem: subsystem)
      return
    }
    
    // Find previous item
    guard let currentIndex = context.allItems.firstIndex(where: { $0.id == context.currentItemID }),
          currentIndex > 0 else {
      Logger.log("No previous item available", subsystem: subsystem)
      return
    }
    
    let previousItem = context.allItems[currentIndex - 1]
    guard let previousURL = URL(string: previousItem.url) else { return }
    
    Logger.log("Playing previous UPnP item via button: \(previousItem.title)", subsystem: subsystem)
    
    // Update context
    currentPlaybackContext = UPnPPlaybackContext(
      deviceID: context.deviceID,
      containerID: context.containerID,
      currentItemID: previousItem.id,
      currentItemURL: previousItem.url,
      allItems: context.allItems
    )
    savePlaybackContext()
    
    // Prepare player for UPnP playback (reset speed, clear watch-later, set title)
    let player = PlayerCore.lastActive
    preparePlayerForUPnPPlayback(player, url: previousURL, title: previousItem.title)
    player.openURL(previousURL)
    
    // Restart monitoring for auto-play-next on the new item
    startAutoPlayMonitor()
    
    // Set window title
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      if let mainWindow = player.mainWindow {
        mainWindow.window?.title = previousItem.title
      }
    }
  }
  
  /// Handle player stopped - stop auto-play and reopen browser if configured
  @objc private func handlePlayerStopped(_ notification: Notification) {
    Logger.log("Player stopped notification received, isAutoPlayingNext: \(isAutoPlayingNext)", subsystem: subsystem)
    
    // Don't stop auto-play if we're in the middle of auto-playing (transitioning between videos)
    // The player stops briefly when switching videos, but we want to continue auto-play
    if isAutoPlayingNext {
      Logger.log("Ignoring player stopped - currently auto-playing next item", subsystem: subsystem)
      return
    }
    
    Logger.log("Stopping auto-play monitoring", subsystem: subsystem)
    stopAutoPlay()
    
    // Handle browser behavior when video closes
    let behavior = Preference.integer(for: .upnpBrowserBehavior)
    Logger.log("Browser behavior setting: \(behavior) (0=close, 1=keep open, 2=reopen)", subsystem: subsystem)
    
    if behavior == 1 || behavior == 2 {
      // behavior 1: Window was hidden with orderOut when playback started - show it again
      // behavior 2: Explicitly reopen browser when video ends
      Logger.log("Showing browser window (behavior=\(behavior))", subsystem: subsystem)
      DispatchQueue.main.async { [weak self] in
        self?.showWindow(nil)
      }
    }
  }
  
  /// Handle file loaded - reset UPnP playback state and restart auto-play monitor
  @objc private func handleFileLoaded(_ notification: Notification) {
    // Check if we're in a UPnP playback context
    if currentPlaybackContext != nil || loadPlaybackContext() != nil {
      let player = PlayerCore.lastActive
      
      // Force speed back to 1.0 AFTER file loads. This is the safety net that catches
      // speed restored from watch-later (which happens during loadfile, after our
      // pre-load reset). This runs after mpv's file-loaded event, so it overrides
      // any watch-later restored speed.
      player.mpv.setDouble(MPVOption.PlaybackControl.speed, 1.0)
      Logger.log("Post-load: reset speed to 1.0 for UPnP file", subsystem: subsystem)
      
      // Restore resume-playback to user's preference (was disabled in preparePlayerForUPnPPlayback)
      let resumeEnabled = Preference.bool(for: .resumeLastPosition)
      player.mpv.setFlag(MPVOption.WatchLater.resumePlayback, resumeEnabled)
      Logger.log("Post-load: restored resume-playback to \(resumeEnabled)", subsystem: subsystem)
    }
    
    // If we're auto-playing, restart the monitor for the new file
    if isAutoPlayingNext {
      Logger.log("File loaded during auto-play - restarting auto-play monitor", subsystem: subsystem)
      startAutoPlayMonitor()
    }
  }
  
  // MARK: - Auto-Refresh
  
  /// Start auto-refresh timer if enabled and we have a valid container to refresh
  private func startAutoRefreshIfNeeded() {
    stopAutoRefresh()
    
    guard Preference.bool(for: .upnpAutoRefreshEnabled) else {
      Logger.log("Auto-refresh is disabled", subsystem: subsystem)
      return
    }
    
    // Only auto-refresh if we have a selected device and a valid container
    guard selectedDevice != nil, currentContainerID != "" else {
      Logger.log("No device or container selected for auto-refresh", subsystem: subsystem)
      return
    }
    
    let interval = TimeInterval(Preference.integer(for: .upnpAutoRefreshInterval))
    guard interval > 0 else {
      Logger.log("Invalid auto-refresh interval: \(interval)", subsystem: subsystem)
      return
    }
    
    Logger.log("Starting auto-refresh timer with interval: \(interval) seconds", subsystem: subsystem)
    autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      self?.performAutoRefresh()
    }
  }
  
  /// Perform auto-refresh of current folder
  @objc private func performAutoRefresh() {
    guard Preference.bool(for: .upnpAutoRefreshEnabled),
          let device = selectedDevice,
          currentContainerID != "" else {
      stopAutoRefresh()
      return
    }
    
    Logger.log("Auto-refreshing container ID: \(currentContainerID)", subsystem: subsystem)
    
    // Refresh the current container
    if currentContainerID == "0" {
      // Refresh device root
      Task {
        do {
          let items = try await UPnPManager.shared.browseContent(device: device, objectID: "0")
          await MainActor.run {
            let oldCount = self.contentCache["0"]?.count ?? 0
            self.contentCache["0"] = items
            self.contentOutlineView?.reloadData()
            if items.count != oldCount {
              Logger.log("Auto-refresh: Container count changed from \(oldCount) to \(items.count)", subsystem: self.subsystem)
              self.statusLabel?.stringValue = String(format: NSLocalizedString("upnp.browser.status.items", comment: "Found %d items"), items.count)
            }
          }
        } catch {
          await MainActor.run {
            Logger.log("Auto-refresh failed: \(error)", level: .error, subsystem: self.subsystem)
          }
        }
          }
        } else {
      // Refresh specific container - find it in cache
      var foundContainer: UPnPItem?
      for (_, items) in contentCache {
        if let container = items.first(where: { $0.id == currentContainerID && $0.isContainer }) {
          foundContainer = container
          break
        }
      }
      
      if let container = foundContainer {
        Task {
          do {
            let items = try await UPnPManager.shared.browseContent(device: device, objectID: container.id)
            await MainActor.run {
              let oldCount = self.contentCache[container.id]?.count ?? 0
              self.contentCache[container.id] = items
              self.contentOutlineView?.reloadItem(container, reloadChildren: true)
              if items.count != oldCount {
                Logger.log("Auto-refresh: Container '\(container.title)' count changed from \(oldCount) to \(items.count)", subsystem: self.subsystem)
                self.statusLabel?.stringValue = String(format: NSLocalizedString("upnp.browser.status.items", comment: "Found %d items"), items.count)
              }
            }
          } catch {
            await MainActor.run {
              Logger.log("Auto-refresh failed for container '\(container.title)': \(error)", level: .error, subsystem: self.subsystem)
            }
          }
        }
      }
    }
  }
  
  /// Show auto-refresh settings dialog
  @objc private func showAutoRefreshSettings() {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("upnp.browser.settings.title", comment: "UPnP Browser Settings")
    alert.informativeText = NSLocalizedString("upnp.browser.settings.description", comment: "Configure auto-refresh and browser behavior")
    
    // Create a view for settings
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
    
    // Auto-refresh enabled checkbox
    let autoRefreshCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("upnp.browser.settings.auto_refresh", comment: "Enable Auto-Refresh"), target: nil, action: nil)
    autoRefreshCheckbox.state = Preference.bool(for: .upnpAutoRefreshEnabled) ? .on : .off
    autoRefreshCheckbox.frame = NSRect(x: 20, y: 80, width: 360, height: 20)
    view.addSubview(autoRefreshCheckbox)
    
    // Refresh interval label and field
    let intervalLabel = NSTextField(labelWithString: NSLocalizedString("upnp.browser.settings.refresh_interval", comment: "Refresh Interval (seconds):"))
    intervalLabel.frame = NSRect(x: 20, y: 50, width: 200, height: 20)
    view.addSubview(intervalLabel)
    
    let intervalField = NSTextField(frame: NSRect(x: 220, y: 48, width: 80, height: 24))
    intervalField.stringValue = String(Preference.integer(for: .upnpAutoRefreshInterval))
    intervalField.isEditable = true
    view.addSubview(intervalField)
    
    // Browser behavior label and popup
    let behaviorLabel = NSTextField(labelWithString: NSLocalizedString("upnp.browser.settings.browser_behavior", comment: "When Video Closes:"))
    behaviorLabel.frame = NSRect(x: 20, y: 20, width: 200, height: 20)
    view.addSubview(behaviorLabel)
    
    let behaviorPopup = NSPopUpButton(frame: NSRect(x: 220, y: 18, width: 160, height: 24))
    behaviorPopup.addItem(withTitle: NSLocalizedString("upnp.browser.settings.behavior.close", comment: "Close Browser"))
    behaviorPopup.addItem(withTitle: NSLocalizedString("upnp.browser.settings.behavior.keep_open", comment: "Keep Browser Open"))
    behaviorPopup.addItem(withTitle: NSLocalizedString("upnp.browser.settings.behavior.reopen", comment: "Reopen Browser"))
    behaviorPopup.selectItem(at: Preference.integer(for: .upnpBrowserBehavior))
    view.addSubview(behaviorPopup)
    
    alert.accessoryView = view
    alert.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    alert.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    
    if alert.runModal() == .alertFirstButtonReturn {
      // Save settings
      Preference.set(autoRefreshCheckbox.state == .on, for: .upnpAutoRefreshEnabled)
      if let interval = Int(intervalField.stringValue), interval > 0 {
        Preference.set(interval, for: .upnpAutoRefreshInterval)
      }
      Preference.set(behaviorPopup.indexOfSelectedItem, for: .upnpBrowserBehavior)
      
      // Restart auto-refresh with new settings
      startAutoRefreshIfNeeded()
    }
  }
  
  /// Handle single-click on favorites table to browse the favorite folder
  @objc private func favoriteClicked() {
    guard let tableView = favoritesTableView else { return }
    let row = tableView.clickedRow
    guard row >= 0 && row < favorites.count else { return }
    
    let favorite = favorites[row]
    Logger.log("Opening favorite: \(favorite.containerTitle) (device: \(favorite.deviceName), containerID: \(favorite.containerID))", subsystem: subsystem)
    
    // Find the device
    guard let device = devices.first(where: { $0.id == favorite.deviceID }) else {
      statusLabel?.stringValue = NSLocalizedString("upnp.browser.status.device_not_found", comment: "Device not found")
      Logger.log("Device not found for favorite: \(favorite.deviceName)", level: .error, subsystem: subsystem)
      return
    }
    
    // Select the device
    selectedDevice = device
    deviceTableView?.reloadData()
    
    // Create a container item for the favorite
    let container = UPnPItem(
      id: favorite.containerID,
      title: favorite.containerTitle,
      itemType: .container,
      resourceURL: nil,
      parentID: "0",
      metadata: UPnPItem.ItemMetadata(artist: nil, album: nil, genre: nil, duration: nil, size: nil, mimeType: nil, resolution: nil, bitrate: nil, date: nil, author: nil, description: nil)
    )
    
    // Browse the favorite container
    currentContainerID = favorite.containerID
    browseContainer(container, device: device)
    // Auto-refresh will be started by browseContainer
  }
}

// MARK: - NSTableViewDataSource & Delegate

extension UPnPBrowserWindowController: NSTableViewDataSource, NSTableViewDelegate {
  
  func numberOfRows(in tableView: NSTableView) -> Int {
    if let favTable = favoritesTableView, tableView == favTable {
      return favorites.count
    }
    return devices.count
  }
  
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    if let favTable = favoritesTableView, tableView == favTable {
      guard row < favorites.count else { return nil }
      let favorite = favorites[row]
      let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("FavoriteName")
      
      if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
        cell.textField?.stringValue = favorite.containerTitle
        if #available(macOS 14.0, *) {
          cell.imageView?.image = NSImage.findSFSymbol(["star.fill"], withConfiguration: nil)
        }
        return cell
      }
      
      let textField = NSTextField()
      textField.stringValue = favorite.containerTitle
      textField.isEditable = false
      textField.isBordered = false
      textField.backgroundColor = .clear
      return textField
    }
    
    guard row < devices.count else { return nil }
    let device = devices[row]
    let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("DeviceName")
    
    if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
        cell.textField?.stringValue = device.friendlyName
      return cell
    }
    
    let textField = NSTextField()
    textField.stringValue = device.friendlyName
    textField.isEditable = false
    textField.isBordered = false
    textField.backgroundColor = .clear
    return textField
  }
  
}

// MARK: - NSOutlineViewDataSource & Delegate

extension UPnPBrowserWindowController: NSOutlineViewDataSource, NSOutlineViewDelegate {
  
  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    guard selectedDevice != nil else { return 0 }
    
    if item == nil {
      return contentCache[currentContainerID]?.count ?? 0
    }
    
    if let container = item as? UPnPItem, container.isContainer {
      return contentCache[container.id]?.count ?? 0
    }
    
    return 0
  }
  
  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    if item == nil {
      if let items = contentCache[currentContainerID] {
        return items[index]
      }
      return UPnPItem(
        id: "",
        title: "Error",
        itemType: .item,
        resourceURL: nil,
        parentID: "0",
        metadata: UPnPItem.ItemMetadata(artist: nil, album: nil, genre: nil, duration: nil, size: nil, mimeType: nil, resolution: nil, bitrate: nil, date: nil, author: nil, description: nil)
      )
    }
    
    if let container = item as? UPnPItem {
      if let items = contentCache[container.id] {
        return items[index]
      }
      return UPnPItem(
        id: "",
        title: "Error",
        itemType: .item,
        resourceURL: nil,
        parentID: container.id,
        metadata: UPnPItem.ItemMetadata(artist: nil, album: nil, genre: nil, duration: nil, size: nil, mimeType: nil, resolution: nil, bitrate: nil, date: nil, author: nil, description: nil)
      )
    }
    
    return UPnPItem(
      id: "",
      title: "Error",
      itemType: .item,
      resourceURL: nil,
      parentID: "0",
      metadata: UPnPItem.ItemMetadata(artist: nil, album: nil, genre: nil, duration: nil, size: nil, mimeType: nil, resolution: nil, bitrate: nil, date: nil, author: nil, description: nil)
    )
  }
  
  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    if let container = item as? UPnPItem {
      return container.isContainer
    }
    return false
  }
  
  func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
    guard let container = item as? UPnPItem, container.isContainer, let device = selectedDevice else {
      return false
    }
    
    // If children are not cached, load them
    if contentCache[container.id] == nil || contentCache[container.id]?.isEmpty == true {
      Logger.log("Expanding container '\(container.title)' (ID: \(container.id)) - loading children", subsystem: subsystem)
      browseContainer(container, device: device)
    }
    
    return true
  }
  
  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    guard let upnpItem = item as? UPnPItem else { return nil }
    
    let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("Title")
    
    var cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
    if cell == nil {
      cell = NSTableCellView()
      cell?.identifier = identifier
      let textField = NSTextField()
      textField.isEditable = false
      textField.isBordered = false
      textField.backgroundColor = .clear
      textField.translatesAutoresizingMaskIntoConstraints = false
      cell?.addSubview(textField)
      cell?.textField = textField
      NSLayoutConstraint.activate([
        textField.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
        textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
        textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
      ])
    }
    
    switch identifier.rawValue {
    case "Title":
      cell?.textField?.stringValue = upnpItem.title
    case "Duration":
      cell?.textField?.stringValue = upnpItem.formattedDuration ?? ""
    case "Size":
      cell?.textField?.stringValue = upnpItem.formattedSize ?? ""
    case "Date":
      cell?.textField?.stringValue = upnpItem.formattedDate ?? ""
    case "Author":
      cell?.textField?.stringValue = upnpItem.metadata.author ?? ""
    case "Description":
      cell?.textField?.stringValue = upnpItem.metadata.description ?? ""
    case "Type":
      cell?.textField?.stringValue = upnpItem.metadata.mimeType ?? ""
    default:
      cell?.textField?.stringValue = upnpItem.title
    }
    
    return cell
  }
  
  func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
    guard let sortDescriptor = outlineView.sortDescriptors.first,
          let device = selectedDevice else { return }
    
    let key = sortDescriptor.key ?? "title"
    let ascending = sortDescriptor.ascending
    
    var items: [UPnPItem] = []
    if let cachedItems = contentCache[currentContainerID] {
      items = cachedItems
    }
    
    items.sort { item1, item2 in
      let result: ComparisonResult
      switch key {
      case "title":
        result = item1.title.localizedStandardCompare(item2.title)
      case "duration":
        let dur1 = item1.metadata.duration ?? ""
        let dur2 = item2.metadata.duration ?? ""
        result = dur1.localizedStandardCompare(dur2)
      case "size":
        let size1 = item1.metadata.size ?? 0
        let size2 = item2.metadata.size ?? 0
        result = size1 < size2 ? .orderedAscending : (size1 > size2 ? .orderedDescending : .orderedSame)
      case "date":
        let date1 = item1.metadata.date ?? ""
        let date2 = item2.metadata.date ?? ""
        result = date1.localizedStandardCompare(date2)
      default:
        result = item1.title.localizedStandardCompare(item2.title)
      }
      return ascending ? result == .orderedAscending : result == .orderedDescending
    }
    
    contentCache[currentContainerID] = items
    outlineView.reloadData()
  }
}

// MARK: - Context Menu

extension UPnPBrowserWindowController: NSMenuDelegate {
  
  func menuNeedsUpdate(_ menu: NSMenu) {
    guard let outlineView = contentOutlineView else { return }
    let clickedRow = outlineView.clickedRow
    guard clickedRow >= 0 else {
      menu.removeAllItems()
      menu.addItem(withTitle: NSLocalizedString("upnp.browser.menu.select_all", comment: "Select All"), action: #selector(selectAllItems(_:)), keyEquivalent: "a")
      menu.addItem(NSMenuItem.separator())
      menu.addItem(withTitle: NSLocalizedString("upnp.browser.menu.expand_all", comment: "Expand All"), action: #selector(expandAll(_:)), keyEquivalent: "")
      menu.addItem(withTitle: NSLocalizedString("upnp.browser.menu.collapse_all", comment: "Collapse All"), action: #selector(collapseAll(_:)), keyEquivalent: "")
      return
    }
    
    guard let item = outlineView.item(atRow: clickedRow) as? UPnPItem else {
      menu.removeAllItems()
      return
    }
    
    menu.removeAllItems()
    
    if item.isPlayable {
      menu.addItem(withTitle: NSLocalizedString("upnp.browser.menu.play", comment: "Play"), action: #selector(contextMenuPlay(_:)), keyEquivalent: "")
      menu.addItem(NSMenuItem.separator())
    }
    
    if item.isContainer, let device = selectedDevice {
      let isFavorite = favorites.contains { fav in
        fav.deviceID == device.id && fav.containerID == item.id
      }
      
      if isFavorite {
        menu.addItem(withTitle: NSLocalizedString("upnp.browser.menu.remove_favorite", comment: "Remove from Favorites"), action: #selector(removeFavorite(_:)), keyEquivalent: "")
      } else {
        menu.addItem(withTitle: NSLocalizedString("upnp.browser.menu.add_favorite", comment: "Add to Favorites"), action: #selector(addFavorite(_:)), keyEquivalent: "")
      }
      menu.addItem(NSMenuItem.separator())
    }
    
    menu.addItem(withTitle: NSLocalizedString("upnp.browser.menu.select_all", comment: "Select All"), action: #selector(selectAllItems(_:)), keyEquivalent: "a")
    menu.addItem(NSMenuItem.separator())
    menu.addItem(withTitle: NSLocalizedString("upnp.browser.menu.expand_all", comment: "Expand All"), action: #selector(expandAll(_:)), keyEquivalent: "")
    menu.addItem(withTitle: NSLocalizedString("upnp.browser.menu.collapse_all", comment: "Collapse All"), action: #selector(collapseAll(_:)), keyEquivalent: "")
    menu.addItem(NSMenuItem.separator())
    
    let columnMenu = NSMenu()
    let durationItem = NSMenuItem(title: NSLocalizedString("upnp.browser.column.duration", comment: "Duration"), action: #selector(toggleColumnVisibility(_:)), keyEquivalent: "")
    durationItem.state = Preference.bool(for: .upnpColumnDurationHidden) ? .off : .on
    durationItem.representedObject = "Duration"
    columnMenu.addItem(durationItem)
    
    let sizeItem = NSMenuItem(title: NSLocalizedString("upnp.browser.column.size", comment: "File Size"), action: #selector(toggleColumnVisibility(_:)), keyEquivalent: "")
    sizeItem.state = Preference.bool(for: .upnpColumnSizeHidden) ? .off : .on
    sizeItem.representedObject = "Size"
    columnMenu.addItem(sizeItem)
    
    let dateItem = NSMenuItem(title: NSLocalizedString("upnp.browser.column.date", comment: "Date"), action: #selector(toggleColumnVisibility(_:)), keyEquivalent: "")
    dateItem.state = Preference.bool(for: .upnpColumnDateHidden) ? .off : .on
    dateItem.representedObject = "Date"
    columnMenu.addItem(dateItem)
    
    let authorItem = NSMenuItem(title: NSLocalizedString("upnp.browser.column.author", comment: "Author"), action: #selector(toggleColumnVisibility(_:)), keyEquivalent: "")
    authorItem.state = Preference.bool(for: .upnpColumnAuthorHidden) ? .off : .on
    authorItem.representedObject = "Author"
    columnMenu.addItem(authorItem)
    
    let descItem = NSMenuItem(title: NSLocalizedString("upnp.browser.column.description", comment: "Description"), action: #selector(toggleColumnVisibility(_:)), keyEquivalent: "")
    descItem.state = Preference.bool(for: .upnpColumnDescriptionHidden) ? .off : .on
    descItem.representedObject = "Description"
    columnMenu.addItem(descItem)
    
    let typeItem = NSMenuItem(title: NSLocalizedString("upnp.browser.column.type", comment: "Type"), action: #selector(toggleColumnVisibility(_:)), keyEquivalent: "")
    typeItem.state = Preference.bool(for: .upnpColumnTypeHidden) ? .off : .on
    typeItem.representedObject = "Type"
    columnMenu.addItem(typeItem)
    
    let columnMenuItem = NSMenuItem(title: NSLocalizedString("upnp.browser.menu.columns", comment: "Columns"), action: nil, keyEquivalent: "")
    columnMenuItem.submenu = columnMenu
    menu.addItem(columnMenuItem)
    
    menu.items.forEach { $0.representedObject = item }
  }
  
  @objc private func toggleColumnVisibility(_ sender: NSMenuItem) {
    guard let columnName = sender.representedObject as? String,
          let outlineView = contentOutlineView else { return }
    
    var key: Preference.Key
    var identifier: NSUserInterfaceItemIdentifier
    
    switch columnName {
    case "Duration":
      key = .upnpColumnDurationHidden
      identifier = NSUserInterfaceItemIdentifier("Duration")
    case "Size":
      key = .upnpColumnSizeHidden
      identifier = NSUserInterfaceItemIdentifier("Size")
    case "Date":
      key = .upnpColumnDateHidden
      identifier = NSUserInterfaceItemIdentifier("Date")
    case "Author":
      key = .upnpColumnAuthorHidden
      identifier = NSUserInterfaceItemIdentifier("Author")
    case "Description":
      key = .upnpColumnDescriptionHidden
      identifier = NSUserInterfaceItemIdentifier("Description")
    case "Type":
      key = .upnpColumnTypeHidden
      identifier = NSUserInterfaceItemIdentifier("Type")
    default:
      return
    }
    
    let isHidden = Preference.bool(for: key)
    Preference.set(!isHidden, for: key)
    
    if let column = outlineView.tableColumn(withIdentifier: identifier) {
      column.isHidden = !isHidden
    }
  }
  
  @objc private func contextMenuPlay(_ sender: NSMenuItem) {
    guard let item = sender.representedObject as? UPnPItem else { return }
    selectedItem = item
    playSelectedItem()
  }
  
  @objc private func selectAllItems(_ sender: NSMenuItem) {
    contentOutlineView?.selectAll(nil)
  }
  
  @objc private func expandAll(_ sender: NSMenuItem) {
    guard let outlineView = contentOutlineView else { return }
    
    func loadAllChildren(for upnpItem: UPnPItem) {
      guard upnpItem.isContainer, let device = selectedDevice else { return }
      
      if contentCache[upnpItem.id] == nil {
        browseContainer(upnpItem, device: device)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          if let children = self.contentCache[upnpItem.id] {
            for child in children {
              loadAllChildren(for: child)
            }
          }
        }
      } else if let children = contentCache[upnpItem.id] {
        for child in children {
          loadAllChildren(for: child)
        }
      }
    }
    
    if let rootItems = contentCache[currentContainerID] {
      for item in rootItems {
        loadAllChildren(for: item)
      }
    }
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      outlineView.expandItem(nil, expandChildren: true)
    }
  }
  
  @objc private func collapseAll(_ sender: NSMenuItem) {
    guard let outlineView = contentOutlineView else { return }
    outlineView.collapseItem(nil, collapseChildren: true)
  }
  
  @objc private func addFavorite(_ sender: NSMenuItem) {
    guard let item = sender.representedObject as? UPnPItem,
          let device = selectedDevice,
          item.isContainer else { return }
    
    let favorite = UPnPFavorite(
      deviceID: device.id,
      deviceName: device.friendlyName,
      containerID: item.id,
      containerTitle: item.title,
      containerPath: buildPath(for: item)
    )
    
    favorites.append(favorite)
    saveFavorites()
    Logger.log("Added favorite: \(favorite.containerTitle)", subsystem: subsystem)
  }
  
  @objc private func removeFavorite(_ sender: NSMenuItem) {
    guard let item = sender.representedObject as? UPnPItem,
          let device = selectedDevice else { return }
    
    favorites.removeAll { fav in
      fav.deviceID == device.id && fav.containerID == item.id
    }
    saveFavorites()
    Logger.log("Removed favorite: \(item.title)", subsystem: subsystem)
  }
  
  private func buildPath(for item: UPnPItem) -> String {
    var path = item.title
    var currentID = item.parentID
    
    while currentID != "0" && currentID != "" {
      for (_, items) in contentCache {
        if let parent = items.first(where: { $0.id == currentID }) {
          path = parent.title + " > " + path
          currentID = parent.parentID
          break
        }
      }
      if currentID == item.parentID { break }
    }
    
    return path
  }
  
  private func loadFavorites() {
    if let data = Preference.data(for: .upnpFavorites),
       let decoded = try? JSONDecoder().decode([UPnPFavorite].self, from: data) {
      favorites = decoded
      favoritesTableView?.reloadData()
    }
  }
  
  private func saveFavorites() {
    if let encoded = try? JSONEncoder().encode(favorites) {
      Preference.set(encoded, for: .upnpFavorites)
      favoritesTableView?.reloadData()
    }
  }
}
