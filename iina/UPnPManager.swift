//
//  UPnPManager.swift
//  iina
//
//  Created for UPnP/DLNA support
//  Copyright © 2024 Contributors. All rights reserved.
//

import Foundation
import Network

/// Manages UPnP device discovery and content browsing
class UPnPManager {
  static let shared = UPnPManager()
  
  private var devices: [String: UPnPDevice] = [:]
  private var discoverySocket: NWConnection?
  private var discoveryTimer: Timer?
  private let discoveryQueue = DispatchQueue(label: "com.iina.upnp.discovery")
  private let subsystem = Logger.makeSubsystem("upnp")
  
  // SSDP multicast address and port
  private let ssdpAddress = "239.255.255.250"
  private let ssdpPort: UInt16 = 1900
  
  // Callbacks
  var onDeviceDiscovered: ((UPnPDevice) -> Void)?
  var onDeviceRemoved: ((String) -> Void)?
  
  private init() {}
  
  // MARK: - Device Discovery
  
  /// Start discovering UPnP devices on the local network
  func startDiscovery() {
    stopDiscovery()
    
    Logger.log("Starting UPnP device discovery", subsystem: subsystem)
    
    // Send M-SEARCH request every 3 seconds for 15 seconds
    sendMSearch()
    discoveryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
      self?.sendMSearch()
    }
    
    // Stop discovery after 15 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
      self?.stopDiscovery()
    }
  }
  
  /// Stop device discovery
  func stopDiscovery() {
    discoveryTimer?.invalidate()
    discoveryTimer = nil
    discoverySocket?.cancel()
    discoverySocket = nil
  }
  
  /// Send SSDP M-SEARCH request
  private func sendMSearch() {
    let msearch = """
    M-SEARCH * HTTP/1.1\r
    HOST: \(ssdpAddress):\(ssdpPort)\r
    MAN: "ssdp:discover"\r
    ST: ssdp:all\r
    MX: 3\r
    \r\n
    """
    
    guard let data = msearch.data(using: .utf8) else { return }
    
    // Create UDP connection for multicast
    let multicastEndpoint = NWEndpoint.hostPort(
      host: NWEndpoint.Host(ssdpAddress),
      port: NWEndpoint.Port(integerLiteral: ssdpPort)
    )
    
    let parameters = NWParameters.udp
    parameters.allowLocalEndpointReuse = true
    parameters.includePeerToPeer = true
    
    // For multicast, we'll use a UDP listener approach instead
    // Create connection directly to multicast endpoint
    let connection = NWConnection(to: multicastEndpoint, using: parameters)
    
    connection.stateUpdateHandler = { [weak self] state in
      guard let self = self else { return }
      switch state {
      case .ready:
        Logger.log("SSDP connection ready", subsystem: self.subsystem)
        // Send M-SEARCH
        connection.send(content: data, completion: .contentProcessed { error in
          if let error = error {
            Logger.log("Failed to send M-SEARCH: \(error)", level: .error, subsystem: self.subsystem)
          } else {
            Logger.log("M-SEARCH sent", subsystem: self.subsystem)
            // Start receiving responses
            self.receiveSSDPResponse(connection: connection)
          }
        })
      case .failed(let error):
        Logger.log("SSDP connection failed: \(error)", level: .error, subsystem: self.subsystem)
      default:
        break
      }
    }
    
    connection.start(queue: discoveryQueue)
    discoverySocket = connection
  }
  
  /// Receive SSDP responses
  private func receiveSSDPResponse(connection: NWConnection) {
    connection.receiveMessage { [weak self] data, context, isComplete, error in
      guard let self = self else { return }
      
      if let error = error {
        Logger.log("SSDP receive error: \(error)", level: .error, subsystem: self.subsystem)
        return
      }
      
      guard let data = data,
            let response = String(data: data, encoding: .utf8) else {
        return
      }
      
      self.parseSSDPResponse(response)
      
      // Continue receiving
      if connection.state == .ready {
        self.receiveSSDPResponse(connection: connection)
      }
    }
  }
  
  /// Parse SSDP response headers
  private func parseSSDPResponse(_ response: String) {
    var headers: [String: String] = [:]
    let lines = response.components(separatedBy: "\r\n")
    
    for line in lines {
      if line.isEmpty { continue }
      if let colonIndex = line.firstIndex(of: ":") {
        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces).uppercased()
        let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        headers[key] = value
      }
    }
    
    // Check if this is a valid response (M-SEARCH reply or NOTIFY)
    guard response.contains("HTTP/1.1 200") || response.contains("NOTIFY") else {
      return
    }
    
    // Many devices use a variety of ST / NT values (MediaServer, upnp:rootdevice, etc.)
    // Don't over-filter here; rely on later parsing to determine if the device exposes
    // a ContentDirectory service.
    
    // Create device from response
    if let device = UPnPDevice.from(ssdpResponse: headers) {
      // Fetch full device description
      fetchDeviceDescription(device: device)
    }
  }
  
  /// Fetch full device description XML
  private func fetchDeviceDescription(device: UPnPDevice) {
    guard let url = URL(string: device.location.absoluteString) else { return }
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("IINA/1.0", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 5.0
    
    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      guard let self = self else { return }
      
      if let error = error {
        Logger.log("Failed to fetch device description: \(error)", level: .error, subsystem: self.subsystem)
        return
      }
      
      guard let data = data,
            let xmlString = String(data: data, encoding: .utf8) else {
        Logger.log("Invalid device description data", level: .error, subsystem: self.subsystem)
        return
      }
      
      // Parse device description
      if let fullDevice = self.parseDeviceDescription(xml: xmlString, baseDevice: device) {
        DispatchQueue.main.async {
          self.devices[fullDevice.id] = fullDevice
          self.onDeviceDiscovered?(fullDevice)
          Logger.log("Discovered device: \(fullDevice.friendlyName)", subsystem: self.subsystem)
        }
      }
    }.resume()
  }
  
  /// Parse device description XML
  private func parseDeviceDescription(xml: String, baseDevice: UPnPDevice) -> UPnPDevice? {
    // Simple XML parsing (could be improved with XMLParser)
    // For now, extract key information using regex/string matching
    
    var friendlyName = baseDevice.friendlyName
    var manufacturer: String?
    var modelName: String?
    var services: [UPnPDevice.UPnPService] = []
    
    // Extract friendly name
    if let range = xml.range(of: #"<friendlyName>(.*?)</friendlyName>"#, options: .regularExpression) {
      let match = String(xml[range])
      friendlyName = match.replacingOccurrences(of: "<friendlyName>", with: "")
        .replacingOccurrences(of: "</friendlyName>", with: "")
        .trimmingCharacters(in: .whitespaces)
    }
    
    // Extract manufacturer
    if let range = xml.range(of: #"<manufacturer>(.*?)</manufacturer>"#, options: .regularExpression) {
      let match = String(xml[range])
      manufacturer = match.replacingOccurrences(of: "<manufacturer>", with: "")
        .replacingOccurrences(of: "</manufacturer>", with: "")
        .trimmingCharacters(in: .whitespaces)
    }
    
    // Extract model name
    if let range = xml.range(of: #"<modelName>(.*?)</modelName>"#, options: .regularExpression) {
      let match = String(xml[range])
      modelName = match.replacingOccurrences(of: "<modelName>", with: "")
        .replacingOccurrences(of: "</modelName>", with: "")
        .trimmingCharacters(in: .whitespaces)
    }
    
    // Extract services (simplified - would need proper XML parsing for production)
    // Look for serviceList and extract service entries
    // TODO: Implement proper XML parsing for service extraction
    let _ = #"<service>[\s\S]*?<serviceType>(.*?)</serviceType>[\s\S]*?<serviceId>(.*?)</serviceId>[\s\S]*?<controlURL>(.*?)</controlURL>"#
    
    // For now, create a basic service entry if ContentDirectory is mentioned
    if xml.contains("ContentDirectory") {
      // Try to extract control URL
      var controlURL = baseDevice.location
      if let range = xml.range(of: #"<controlURL>(.*?)</controlURL>"#, options: .regularExpression) {
        let match = String(xml[range])
        let urlStr = match.replacingOccurrences(of: "<controlURL>", with: "")
          .replacingOccurrences(of: "</controlURL>", with: "")
          .trimmingCharacters(in: .whitespaces)
        
        if let url = URL(string: urlStr, relativeTo: baseDevice.location) {
          controlURL = url
        }
      }
      
      let service = UPnPDevice.UPnPService(
        serviceType: "urn:schemas-upnp-org:service:ContentDirectory:1",
        serviceId: "ContentDirectory",
        controlURL: controlURL,
        eventSubURL: nil,
        scpdURL: nil
      )
      services.append(service)
    }
    
    return UPnPDevice(
      id: baseDevice.id,
      friendlyName: friendlyName,
      deviceType: baseDevice.deviceType,
      manufacturer: manufacturer,
      modelName: modelName,
      location: baseDevice.location,
      services: services,
      discoveredAt: baseDevice.discoveredAt
    )
  }
  
  // MARK: - Device Management
  
  /// Get all discovered devices
  func getDevices() -> [UPnPDevice] {
    Array(devices.values)
  }
  
  /// Get device by ID
  func getDevice(id: String) -> UPnPDevice? {
    devices[id]
  }
  
  /// Clear all discovered devices
  func clearDevices() {
    devices.removeAll()
  }
  
  // MARK: - Content Browsing
  
  /// Browse content directory of a device
  func browseContent(device: UPnPDevice, objectID: String = "0") async throws -> [UPnPItem] {
    guard let contentDirService = device.contentDirectoryService else {
      throw UPnPError.serviceNotFound
    }
    
    // Create SOAP request
    let soapBody = """
    <?xml version="1.0"?>
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" 
                s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <s:Body>
        <u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
          <ObjectID>\(objectID)</ObjectID>
          <BrowseFlag>BrowseDirectChildren</BrowseFlag>
          <Filter>*</Filter>
          <StartingIndex>0</StartingIndex>
          <RequestedCount>100</RequestedCount>
          <SortCriteria></SortCriteria>
        </u:Browse>
      </s:Body>
    </s:Envelope>
    """
    
    // Create HTTP request
    var request = URLRequest(url: contentDirService.controlURL)
    request.httpMethod = "POST"
    request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
    request.setValue("\"urn:schemas-upnp-org:service:ContentDirectory:1#Browse\"", forHTTPHeaderField: "SOAPAction")
    request.httpBody = soapBody.data(using: .utf8)
    request.timeoutInterval = 10.0
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
      throw UPnPError.browseFailed("HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
    }
    
    guard let xmlString = String(data: data, encoding: .utf8) else {
      throw UPnPError.invalidResponse
    }
    
    // Parse DIDL-Lite XML response
    return try parseDIDLLite(xml: xmlString, baseURL: contentDirService.controlURL)
  }
  
  /// Parse DIDL-Lite XML to extract items
  private func parseDIDLLite(xml: String, baseURL: URL) throws -> [UPnPItem] {
    var items: [UPnPItem] = []
    
    // Extract items and containers using regex (simplified - proper XML parsing would be better)
    // TODO: Implement proper XML parsing for item extraction
    let _ = #"<(item|container)[\s\S]*?id="([^"]+)"[\s\S]*?parentID="([^"]+)"[\s\S]*?>(.*?)</(item|container)>"#
    
    // For a more robust implementation, we'd use XMLParser
    // This is a simplified version for initial implementation
    
    // Split by item/container tags
    let components = xml.components(separatedBy: "<item")
    for component in components {
      if component.contains("</item>") {
        // Parse item
        if let item = parseItem(from: component, baseURL: baseURL) {
          items.append(item)
        }
      }
    }
    
    // Also check for containers
    let containerComponents = xml.components(separatedBy: "<container")
    for component in containerComponents {
      if component.contains("</container>") {
        // Parse container
        if let container = parseContainer(from: component, baseURL: baseURL) {
          items.append(container)
        }
      }
    }
    
    return items
  }
  
  /// Parse a single item from XML
  private func parseItem(from xml: String, baseURL: URL) -> UPnPItem? {
    // Extract ID
    guard let idRange = xml.range(of: #"id="([^"]+)""#, options: .regularExpression) else {
      return nil
    }
    let idMatch = String(xml[idRange])
    let id = idMatch.replacingOccurrences(of: "id=\"", with: "").replacingOccurrences(of: "\"", with: "")
    
    // Extract parentID
    var parentID = "0"
    if let parentRange = xml.range(of: #"parentID="([^"]+)""#, options: .regularExpression) {
      let parentMatch = String(xml[parentRange])
      parentID = parentMatch.replacingOccurrences(of: "parentID=\"", with: "").replacingOccurrences(of: "\"", with: "")
    }
    
    // Extract title
    var title = "Unknown"
    if let titleRange = xml.range(of: #"<dc:title>(.*?)</dc:title>"#, options: .regularExpression) {
      let titleMatch = String(xml[titleRange])
      title = titleMatch.replacingOccurrences(of: "<dc:title>", with: "")
        .replacingOccurrences(of: "</dc:title>", with: "")
        .trimmingCharacters(in: .whitespaces)
    }
    
    // Extract resource URL
    var resourceURL: URL?
    if let resRange = xml.range(of: #"<res[^>]*>(.*?)</res>"#, options: .regularExpression) {
      let resMatch = String(xml[resRange])
      let urlStr = resMatch.replacingOccurrences(of: "<res[^>]*>", with: "", options: .regularExpression)
        .replacingOccurrences(of: "</res>", with: "")
        .trimmingCharacters(in: .whitespaces)
      resourceURL = URL(string: urlStr)
    }
    
    // Extract metadata
    var artist: String?
    if let artistRange = xml.range(of: #"<dc:creator>(.*?)</dc:creator>"#, options: .regularExpression) {
      let artistMatch = String(xml[artistRange])
      artist = artistMatch.replacingOccurrences(of: "<dc:creator>", with: "")
        .replacingOccurrences(of: "</dc:creator>", with: "")
        .trimmingCharacters(in: .whitespaces)
    }
    
    var duration: String?
    if let durRange = xml.range(of: #"duration="([^"]+)""#, options: .regularExpression) {
      let durMatch = String(xml[durRange])
      duration = durMatch.replacingOccurrences(of: "duration=\"", with: "").replacingOccurrences(of: "\"", with: "")
    }
    
    let metadata = UPnPItem.ItemMetadata(
      artist: artist,
      album: nil,
      genre: nil,
      duration: duration,
      size: nil,
      mimeType: nil,
      resolution: nil,
      bitrate: nil
    )
    
    return UPnPItem(
      id: id,
      title: title,
      itemType: .item,
      resourceURL: resourceURL,
      parentID: parentID,
      metadata: metadata
    )
  }
  
  /// Parse a container from XML
  private func parseContainer(from xml: String, baseURL: URL) -> UPnPItem? {
    // Similar to parseItem but for containers
    guard let idRange = xml.range(of: #"id="([^"]+)""#, options: .regularExpression) else {
      return nil
    }
    let idMatch = String(xml[idRange])
    let id = idMatch.replacingOccurrences(of: "id=\"", with: "").replacingOccurrences(of: "\"", with: "")
    
    var parentID = "0"
    if let parentRange = xml.range(of: #"parentID="([^"]+)""#, options: .regularExpression) {
      let parentMatch = String(xml[parentRange])
      parentID = parentMatch.replacingOccurrences(of: "parentID=\"", with: "").replacingOccurrences(of: "\"", with: "")
    }
    
    var title = "Unknown"
    if let titleRange = xml.range(of: #"<dc:title>(.*?)</dc:title>"#, options: .regularExpression) {
      let titleMatch = String(xml[titleRange])
      title = titleMatch.replacingOccurrences(of: "<dc:title>", with: "")
        .replacingOccurrences(of: "</dc:title>", with: "")
        .trimmingCharacters(in: .whitespaces)
    }
    
    let metadata = UPnPItem.ItemMetadata(
      artist: nil,
      album: nil,
      genre: nil,
      duration: nil,
      size: nil,
      mimeType: nil,
      resolution: nil,
      bitrate: nil
    )
    
    return UPnPItem(
      id: id,
      title: title,
      itemType: .container,
      resourceURL: nil,
      parentID: parentID,
      metadata: metadata
    )
  }
}

