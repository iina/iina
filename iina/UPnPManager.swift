//
//  UPnPManager.swift
//  iina
//
//  Created for UPnP/DLNA support
//  Copyright © 2024 Contributors. All rights reserved.
//

import Foundation
import Darwin

/// Manages UPnP device discovery and content browsing
class UPnPManager {
  static let shared = UPnPManager()
  
  private var devices: [String: UPnPDevice] = [:]
  private let devicesLock = NSLock()
  private var discoverySocketFD: Int32 = -1
  private var discoverySource: DispatchSourceRead?
  private var discoveryTimer: Timer?
  private var isActivelySearching = false
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
    setupDiscoverySocketIfNeeded()
    guard discoverySocketFD >= 0 else { return }
    
    isActivelySearching = true
    
    // Send M-SEARCH request every 3 seconds for 15 seconds
    sendMSearch()
    discoveryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
      self?.sendMSearch()
    }
    
    // Stop discovery after 15 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
      self?.stopActiveSearch()
    }
  }
  
  /// Stop device discovery
  func stopDiscovery() {
    stopActiveSearch()
    isActivelySearching = false
    
    discoveryTimer?.invalidate()
    discoveryTimer = nil
    
    discoverySource?.cancel()
    discoverySource = nil
    
    if discoverySocketFD >= 0 {
      close(discoverySocketFD)
      discoverySocketFD = -1
    }
  }
  
  private func stopActiveSearch() {
    isActivelySearching = false
    discoveryTimer?.invalidate()
    discoveryTimer = nil
  }

  /// Ensure the raw UDP socket and read source are set up for SSDP.
  private func setupDiscoverySocketIfNeeded() {
    guard discoverySocketFD < 0 else { return }
    
    let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    if fd < 0 {
      Logger.log("Failed to create SSDP socket: \(errno)", level: .error, subsystem: subsystem)
      return
    }
    
    // Allow address reuse (multiple apps / sockets).
    var yes: Int32 = 1
    if setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes))) < 0 {
      Logger.log("Failed to set SO_REUSEADDR on SSDP socket: \(errno)", level: .warning, subsystem: subsystem)
    }
    if setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout.size(ofValue: yes))) < 0 {
      Logger.log("Failed to set SO_REUSEPORT on SSDP socket: \(errno)", level: .warning, subsystem: subsystem)
    }
    
    // Bind to SSDP port and join multicast group so we can receive NOTIFY packets.
    var bindAddr = sockaddr_in()
    bindAddr.sin_len = UInt8(MemoryLayout.size(ofValue: bindAddr))
    bindAddr.sin_family = sa_family_t(AF_INET)
    bindAddr.sin_port = in_port_t(ssdpPort).bigEndian
    bindAddr.sin_addr = in_addr(s_addr: INADDR_ANY)
    let bindAddrSize = socklen_t(MemoryLayout<sockaddr_in>.size)
    
    let bindResult = withUnsafePointer(to: &bindAddr) { ptr -> Int32 in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        bind(fd, sockPtr, bindAddrSize)
      }
    }
    if bindResult < 0 {
      Logger.log("Failed to bind SSDP socket to port \(ssdpPort): \(errno)", level: .warning, subsystem: subsystem)
    }
    
    var multicastReq = ip_mreq(
      imr_multiaddr: in_addr(s_addr: inet_addr(ssdpAddress)),
      imr_interface: in_addr(s_addr: INADDR_ANY)
    )
    if setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &multicastReq, socklen_t(MemoryLayout.size(ofValue: multicastReq))) < 0 {
      Logger.log("Failed to join SSDP multicast group: \(errno)", level: .warning, subsystem: subsystem)
    }
    
    // Optionally set a small multicast TTL so packets stay on the local network.
    var ttl: UInt8 = 2
    let ttlSize = socklen_t(MemoryLayout<UInt8>.size)
    withUnsafePointer(to: &ttl) { ptr in
      _ = setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, ptr, ttlSize)
    }
    
    discoverySocketFD = fd
    
    // Create a DispatchSource to receive packets asynchronously, similar to VLC's recv loop.
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: discoveryQueue)
    source.setEventHandler { [weak self] in
      guard let self = self else { return }
      
      var addr = sockaddr_storage()
      var addrLen = socklen_t(MemoryLayout.size(ofValue: addr))
      var buffer = [UInt8](repeating: 0, count: 2048)
      
      let bytesRead = withUnsafeMutablePointer(to: &addr) { addrPtr -> ssize_t in
        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
          return recvfrom(fd, &buffer, buffer.count, 0, sockAddrPtr, &addrLen)
        }
      }
      
      if bytesRead > 0 {
        let data = Data(buffer[0..<bytesRead])
        if let response = String(data: data, encoding: .utf8) {
          let snippet = response.prefix(300)
          Logger.log("SSDP raw response (\(data.count) bytes):\n\(snippet)", subsystem: self.subsystem)
          self.parseSSDPMessage(response)
        }
      } else if bytesRead < 0 {
        Logger.log("SSDP recvfrom error: \(errno)", level: .error, subsystem: self.subsystem)
      }
    }
    source.setCancelHandler {
      // The fd is closed in stopDiscovery()
    }
    discoverySource = source
    source.resume()
  }
  
  /// Send SSDP M-SEARCH requests (using several common ST values to maximize compatibility)
  private func sendMSearch() {
    setupDiscoverySocketIfNeeded()
    guard discoverySocketFD >= 0 else { return }
    
    // Common search targets that most DLNA/UPnP media servers understand
    let searchTargets = [
      "ssdp:all",
      "upnp:rootdevice",
      "urn:schemas-upnp-org:device:MediaServer:1",
      "urn:schemas-upnp-org:service:ContentDirectory:1"
    ]
    
    // Destination: 239.255.255.250:1900
    var destAddr = sockaddr_in()
    destAddr.sin_len = UInt8(MemoryLayout.size(ofValue: destAddr))
    destAddr.sin_family = sa_family_t(AF_INET)
    destAddr.sin_port = in_port_t(ssdpPort).bigEndian
    destAddr.sin_addr = in_addr(s_addr: inet_addr(ssdpAddress))
    let destAddrSize = socklen_t(MemoryLayout.size(ofValue: destAddr))
    
    for st in searchTargets {
      let msearch =
        "M-SEARCH * HTTP/1.1\r\n" +
        "HOST: \(ssdpAddress):\(ssdpPort)\r\n" +
        "MAN: \"ssdp:discover\"\r\n" +
        "ST: \(st)\r\n" +
        "MX: 3\r\n" +
        "\r\n"
      
      guard let data = msearch.data(using: .utf8) else { continue }
      
      data.withUnsafeBytes { bufferPtr in
        guard let baseAddress = bufferPtr.baseAddress else { return }
        withUnsafePointer(to: &destAddr) { addrPtr in
          addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
            let sent = sendto(discoverySocketFD, baseAddress, data.count, 0, sockAddrPtr, destAddrSize)
            if sent < 0 {
              Logger.log("Failed to send M-SEARCH (\(st)): \(errno)", level: .error, subsystem: self.subsystem)
            } else {
              Logger.log("M-SEARCH sent (\(st))", subsystem: self.subsystem)
            }
          }
        }
      }
    }
  }
  
  /// Parse SSDP response / notify headers.
  private func parseSSDPMessage(_ response: String) {
    var headers: [String: String] = [:]
    let lines = response.components(separatedBy: "\r\n")
    let startLine = lines.first?.uppercased() ?? ""
    
    for line in lines {
      if line.isEmpty { continue }
      if let colonIndex = line.firstIndex(of: ":") {
        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces).uppercased()
        let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        headers[key] = value
      }
    }
    
    if startLine.hasPrefix("NOTIFY") {
      handleSSDPNotify(headers: headers)
      return
    }
    
    // Basic validity check: require LOCATION / USN headers, but avoid over-filtering by ST / NT.
    guard headers["LOCATION"] != nil else {
      return
    }
    guard headers["USN"] != nil else {
      return
    }
    
    // Create device from response
    if let device = UPnPDevice.from(ssdpResponse: headers) {
      // Fetch full device description
      fetchDeviceDescription(device: device)
    }
  }
  
  private func handleSSDPNotify(headers: [String: String]) {
    let nts = headers["NTS"]?.lowercased() ?? ""
    let usn = headers["USN"] ?? ""
    
    if nts == "ssdp:byebye" {
      removeDevice(withUSN: usn)
      return
    }
    
    // Handle alive/update notifications that include enough data to fetch description.
    guard headers["LOCATION"] != nil,
          headers["USN"] != nil else {
      return
    }
    
    if let device = UPnPDevice.from(ssdpResponse: headers) {
      fetchDeviceDescription(device: device)
    }
  }
  
  private func removeDevice(withUSN usn: String) {
    guard let uuidRange = usn.range(of: #"uuid:[^:]+"#, options: .regularExpression) else { return }
    let deviceID = String(usn[uuidRange]).replacingOccurrences(of: "uuid:", with: "")
    
    devicesLock.lock()
    let removed = devices.removeValue(forKey: deviceID)
    devicesLock.unlock()
    
    guard removed != nil else { return }
    DispatchQueue.main.async {
      self.onDeviceRemoved?(deviceID)
      Logger.log("UPnP device removed via byebye: \(deviceID)", subsystem: self.subsystem)
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
        // Only keep devices that look like real media servers and expose ContentDirectory
        guard fullDevice.supportsContentDirectory,
              fullDevice.deviceType.localizedCaseInsensitiveContains("MediaServer") else {
          Logger.log("Ignoring non-media UPnP device: \(fullDevice.friendlyName) (\(fullDevice.deviceType))", subsystem: self.subsystem)
          return
        }
        
        DispatchQueue.main.async {
          self.upsertDevice(fullDevice)
          self.onDeviceDiscovered?(fullDevice)
          Logger.log("Discovered device: \(fullDevice.friendlyName)", subsystem: self.subsystem)
        }
      }
    }.resume()
  }
  
  /// Parse device description XML
  private func parseDeviceDescription(xml: String, baseDevice: UPnPDevice) -> UPnPDevice? {
    guard let data = xml.data(using: .utf8) else {
      Logger.log("Failed to encode device description XML as UTF-8", level: .error, subsystem: subsystem)
      return nil
    }
    
    let delegate = DeviceDescriptionXMLParserDelegate(baseURL: baseDevice.location)
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    guard parser.parse() else {
      Logger.log("Failed to parse device description XML: \(parser.parserError?.localizedDescription ?? "unknown error")", level: .error, subsystem: subsystem)
      return nil
    }
    
    let friendlyName = delegate.friendlyName?.nonEmpty ?? baseDevice.friendlyName
    let manufacturer = delegate.manufacturer?.nonEmpty
    let modelName = delegate.modelName?.nonEmpty
    let deviceType = delegate.deviceType?.nonEmpty ?? baseDevice.deviceType
    
    return UPnPDevice(
      id: baseDevice.id,
      friendlyName: friendlyName,
      deviceType: deviceType,
      manufacturer: manufacturer,
      modelName: modelName,
      location: baseDevice.location,
      services: delegate.services,
      discoveredAt: baseDevice.discoveredAt
    )
  }
  
  // MARK: - Device Management
  
  /// Get all discovered devices
  func getDevices() -> [UPnPDevice] {
    devicesLock.lock()
    let values = Array(devices.values)
    devicesLock.unlock()
    return values
  }
  
  /// Get device by ID
  func getDevice(id: String) -> UPnPDevice? {
    devicesLock.lock()
    let device = devices[id]
    devicesLock.unlock()
    return device
  }
  
  /// Clear all discovered devices
  func clearDevices() {
    devicesLock.lock()
    devices.removeAll()
    devicesLock.unlock()
  }
  
  // MARK: - Content Browsing
  
  /// Browse content directory of a device
  func browseContent(device: UPnPDevice, objectID: String = "0") async throws -> [UPnPItem] {
    guard let contentDirService = device.contentDirectoryService else {
      throw UPnPError.serviceNotFound
    }
    
    var allItems: [UPnPItem] = []
    var startIndex = 0
    let pageSize = 100
    let maxPages = 1000
    var pageCount = 0
    
    while pageCount < maxPages {
      pageCount += 1
      let page = try await browseContentPage(
        service: contentDirService,
        objectID: objectID,
        startingIndex: startIndex,
        requestedCount: pageSize
      )
      allItems.append(contentsOf: page.items)
      
      let returned = page.numberReturned ?? page.items.count
      if returned <= 0 {
        break
      }
      startIndex += returned
      
      if let total = page.totalMatches, startIndex >= total {
        break
      }
      if returned < pageSize {
        break
      }
    }
    
    return allItems
  }
  
  /// Search in a ContentDirectory using UPnP Search action.
  func searchContent(device: UPnPDevice, objectID: String = "0", searchCriteria: String) async throws -> [UPnPItem] {
    guard let contentDirService = device.contentDirectoryService else {
      throw UPnPError.serviceNotFound
    }
    
    var allItems: [UPnPItem] = []
    var startIndex = 0
    let pageSize = 100
    let maxPages = 1000
    var pageCount = 0
    
    while pageCount < maxPages {
      pageCount += 1
      let page = try await searchContentPage(
        service: contentDirService,
        objectID: objectID,
        searchCriteria: searchCriteria,
        startingIndex: startIndex,
        requestedCount: pageSize
      )
      allItems.append(contentsOf: page.items)
      
      let returned = page.numberReturned ?? page.items.count
      if returned <= 0 {
        break
      }
      startIndex += returned
      
      if let total = page.totalMatches, startIndex >= total {
        break
      }
      if returned < pageSize {
        break
      }
    }
    
    return allItems
  }
  
  private func browseContentPage(service: UPnPDevice.UPnPService, objectID: String, startingIndex: Int, requestedCount: Int) async throws -> BrowsePageResult {
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
          <StartingIndex>\(startingIndex)</StartingIndex>
          <RequestedCount>\(requestedCount)</RequestedCount>
          <SortCriteria></SortCriteria>
        </u:Browse>
      </s:Body>
    </s:Envelope>
    """
    
    // Create HTTP request
    var request = URLRequest(url: service.controlURL)
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
    
    let didlXML = extractDIDLLiteXML(fromSOAPResponse: xmlString)
    
    // Debug: log a snippet of the DIDL-Lite payload we are actually parsing.
    let snippet = didlXML.prefix(800)
    Logger.log("DIDL-Lite payload for objectID=\(objectID), start=\(startingIndex):\n\(snippet)", subsystem: subsystem)
    
    // Parse DIDL-Lite XML response
    let items = try parseDIDLLite(xml: didlXML, baseURL: service.controlURL)
    
    let numberReturned = extractIntTagValue(for: "NumberReturned", in: xmlString)
    let totalMatches = extractIntTagValue(for: "TotalMatches", in: xmlString)
    
    return BrowsePageResult(
      items: items,
      numberReturned: numberReturned,
      totalMatches: totalMatches
    )
  }
  
  private func searchContentPage(service: UPnPDevice.UPnPService, objectID: String, searchCriteria: String, startingIndex: Int, requestedCount: Int) async throws -> BrowsePageResult {
    let soapBody = """
    <?xml version="1.0"?>
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" 
                s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <s:Body>
        <u:Search xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
          <ContainerID>\(objectID)</ContainerID>
          <SearchCriteria>\(xmlEscaped(searchCriteria))</SearchCriteria>
          <Filter>*</Filter>
          <StartingIndex>\(startingIndex)</StartingIndex>
          <RequestedCount>\(requestedCount)</RequestedCount>
          <SortCriteria></SortCriteria>
        </u:Search>
      </s:Body>
    </s:Envelope>
    """
    
    var request = URLRequest(url: service.controlURL)
    request.httpMethod = "POST"
    request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
    request.setValue("\"urn:schemas-upnp-org:service:ContentDirectory:1#Search\"", forHTTPHeaderField: "SOAPAction")
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
    
    let didlXML = extractDIDLLiteXML(fromSOAPResponse: xmlString)
    let items = try parseDIDLLite(xml: didlXML, baseURL: service.controlURL)
    let numberReturned = extractIntTagValue(for: "NumberReturned", in: xmlString)
    let totalMatches = extractIntTagValue(for: "TotalMatches", in: xmlString)
    
    return BrowsePageResult(items: items, numberReturned: numberReturned, totalMatches: totalMatches)
  }
  
  /// Parse DIDL-Lite XML to extract items
  private func parseDIDLLite(xml: String, baseURL: URL) throws -> [UPnPItem] {
    guard let data = xml.data(using: .utf8) else {
      throw UPnPError.invalidResponse
    }
    
    let delegate = DIDLLiteXMLParserDelegate(baseURL: baseURL)
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    
    if parser.parse() {
      return delegate.items
    } else {
      Logger.log("Failed to parse DIDL-Lite XML: \(parser.parserError?.localizedDescription ?? "unknown error")", level: .error, subsystem: subsystem)
      throw UPnPError.xmlParseError
    }
  }
  
  private func extractDIDLLiteXML(fromSOAPResponse xml: String) -> String {
    if let resultRange = xml.range(of: "<Result>([\\s\\S]*?)</Result>", options: .regularExpression) {
      let resultTag = String(xml[resultRange])
      let escaped = resultTag
        .replacingOccurrences(of: "<Result>", with: "")
        .replacingOccurrences(of: "</Result>", with: "")
      return escaped.unescapedXML
    }
    return xml
  }
  
  private func extractIntTagValue(for tag: String, in xml: String) -> Int? {
    guard let range = xml.range(of: "<\(tag)>(.*?)</\(tag)>", options: .regularExpression) else {
      return nil
    }
    let match = String(xml[range])
      .replacingOccurrences(of: "<\(tag)>", with: "")
      .replacingOccurrences(of: "</\(tag)>", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return Int(match)
  }
  
  private func xmlEscaped(_ raw: String) -> String {
    raw.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }
  
  private func upsertDevice(_ device: UPnPDevice) {
    devicesLock.lock()
    devices[device.id] = device
    devicesLock.unlock()
  }
  
  private struct BrowsePageResult {
    let items: [UPnPItem]
    let numberReturned: Int?
    let totalMatches: Int?
  }
}

private extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
  
  var unescapedXML: String {
    replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&amp;", with: "&")
  }
}

private final class DeviceDescriptionXMLParserDelegate: NSObject, XMLParserDelegate {
  private let baseURL: URL
  private var currentElement = ""
  private var currentValue = ""
  
  private var inService = false
  private var serviceType: String?
  private var serviceId: String?
  private var controlURLString: String?
  private var eventSubURLString: String?
  private var scpdURLString: String?
  
  var friendlyName: String?
  var manufacturer: String?
  var modelName: String?
  var deviceType: String?
  var services: [UPnPDevice.UPnPService] = []
  
  init(baseURL: URL) {
    self.baseURL = baseURL
    super.init()
  }
  
  func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
    currentElement = qName ?? elementName
    currentValue = ""
    
    if elementName == "service" {
      inService = true
      serviceType = nil
      serviceId = nil
      controlURLString = nil
      eventSubURLString = nil
      scpdURLString = nil
    }
  }
  
  func parser(_ parser: XMLParser, foundCharacters string: String) {
    currentValue += string
  }
  
  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
    let value = currentValue.nonEmpty
    let name = qName ?? elementName
    
    switch name {
    case "friendlyName":
      friendlyName = value ?? friendlyName
    case "manufacturer":
      manufacturer = value ?? manufacturer
    case "modelName":
      modelName = value ?? modelName
    case "deviceType":
      deviceType = value ?? deviceType
    case "serviceType":
      if inService { serviceType = value }
    case "serviceId":
      if inService { serviceId = value }
    case "controlURL":
      if inService { controlURLString = value }
    case "eventSubURL":
      if inService { eventSubURLString = value }
    case "SCPDURL":
      if inService { scpdURLString = value }
    default:
      break
    }
    
    if elementName == "service" {
      defer { inService = false }
      guard let serviceType, let serviceId, let controlURLString else { return }
      guard let controlURL = URL(string: controlURLString, relativeTo: baseURL)?.absoluteURL else { return }
      
      let eventSubURL = eventSubURLString.flatMap {
        URL(string: $0, relativeTo: baseURL)?.absoluteURL
      }
      let scpdURL = scpdURLString.flatMap {
        URL(string: $0, relativeTo: baseURL)?.absoluteURL
      }
      
      services.append(
        UPnPDevice.UPnPService(
          serviceType: serviceType,
          serviceId: serviceId,
          controlURL: controlURL,
          eventSubURL: eventSubURL,
          scpdURL: scpdURL
        )
      )
    }
  }
}

private final class DIDLLiteXMLParserDelegate: NSObject, XMLParserDelegate {
  private let baseURL: URL
  private var currentElement = ""
  private var currentValue = ""
  private var currentRecord: DIDLRecord?
  
  private struct DIDLRecord {
    let id: String
    let parentID: String
    let itemType: UPnPItem.ItemType
    var title = "Unknown"
    var resourceURL: URL?
    var artist: String?
    var album: String?
    var genre: String?
    var duration: String?
    var size: Int64?
    var mimeType: String?
    var date: String?
    var author: String?
    var description: String?
    var albumArtURL: URL?
  }
  
  var items: [UPnPItem] = []
  
  init(baseURL: URL) {
    self.baseURL = baseURL
    super.init()
  }
  
  func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
    currentElement = qName ?? elementName
    currentValue = ""
    
    if elementName == "item" || elementName == "container" {
      let id = attributeDict["id"] ?? ""
      let parentID = attributeDict["parentID"] ?? "0"
      let itemType: UPnPItem.ItemType = elementName == "container" ? .container : .item
      currentRecord = DIDLRecord(id: id, parentID: parentID, itemType: itemType)
      return
    }
    
    if elementName == "res" {
      if let duration = attributeDict["duration"]?.nonEmpty {
        currentRecord?.duration = duration
      }
      if let sizeString = attributeDict["size"], let size = Int64(sizeString) {
        currentRecord?.size = size
      }
      if let protocolInfo = attributeDict["protocolInfo"]?.nonEmpty {
        let parts = protocolInfo.components(separatedBy: ":")
        if parts.count >= 3 {
          currentRecord?.mimeType = parts[2].nonEmpty
        }
      }
    }
  }
  
  func parser(_ parser: XMLParser, foundCharacters string: String) {
    currentValue += string
  }
  
  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
    guard currentRecord != nil else { return }
    
    let value = currentValue.nonEmpty
    let name = qName ?? elementName
    
    switch name {
    case "dc:title", "title":
      currentRecord?.title = value ?? "Unknown"
    case "dc:creator", "creator":
      currentRecord?.artist = value
      currentRecord?.author = value
    case "upnp:album", "album":
      currentRecord?.album = value
    case "upnp:genre", "genre":
      currentRecord?.genre = value
    case "dc:date", "date":
      currentRecord?.date = value
    case "dc:description", "description":
      currentRecord?.description = value
    case "upnp:duration":
      if currentRecord?.duration == nil {
        currentRecord?.duration = value
      }
    case "upnp:albumArtURI", "albumArtURI":
      if let artString = value {
        currentRecord?.albumArtURL = URL(string: artString, relativeTo: baseURL)?.absoluteURL
      }
    case "res":
      if let resourceString = value,
         let url = URL(string: resourceString, relativeTo: baseURL)?.absoluteURL {
        currentRecord?.resourceURL = url
      }
    default:
      break
    }
    
    if elementName == "item" || elementName == "container" {
      guard let record = currentRecord else { return }
      
      let metadata = UPnPItem.ItemMetadata(
        artist: record.artist,
        album: record.album,
        genre: record.genre,
        duration: record.duration,
        size: record.size,
        mimeType: record.mimeType,
        resolution: nil,
        bitrate: nil,
        date: record.date,
        author: record.author,
        description: record.description,
        albumArtURL: record.albumArtURL
      )
      
      items.append(
        UPnPItem(
          id: record.id,
          title: record.title,
          itemType: record.itemType,
          resourceURL: record.resourceURL,
          parentID: record.parentID,
          metadata: metadata
        )
      )
      currentRecord = nil
    }
  }
}

