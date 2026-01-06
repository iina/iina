//
//  UPnPDevice.swift
//  iina
//
//  Created for UPnP/DLNA support
//  Copyright © 2024 Contributors. All rights reserved.
//

import Foundation

/// Represents a UPnP device discovered on the network
struct UPnPDevice: Identifiable, Hashable {
  let id: String // UUID
  let friendlyName: String
  let deviceType: String
  let manufacturer: String?
  let modelName: String?
  let location: URL // URL to device description XML
  let services: [UPnPService]
  let discoveredAt: Date
  
  struct UPnPService: Hashable {
    let serviceType: String
    let serviceId: String
    let controlURL: URL
    let eventSubURL: URL?
    let scpdURL: URL?
  }
  
  /// Check if this device supports ContentDirectory service (required for DLNA)
  var supportsContentDirectory: Bool {
    services.contains { $0.serviceType.contains("ContentDirectory") }
  }
  
  /// Get ContentDirectory service if available
  var contentDirectoryService: UPnPService? {
    services.first { $0.serviceType.contains("ContentDirectory") }
  }
}

extension UPnPDevice {
  /// Parse device from SSDP response headers
  static func from(ssdpResponse: [String: String]) -> UPnPDevice? {
    guard let locationStr = ssdpResponse["LOCATION"] ?? ssdpResponse["location"],
          let location = URL(string: locationStr),
          let usn = ssdpResponse["USN"] ?? ssdpResponse["usn"] else {
      return nil
    }
    
    // Extract UUID from USN (format: uuid:device-UUID::device-type)
    let uuid = extractUUID(from: usn)
    let deviceType = extractDeviceType(from: usn)
    
    return UPnPDevice(
      id: uuid,
      friendlyName: ssdpResponse["SERVER"] ?? "Unknown Device",
      deviceType: deviceType ?? "unknown",
      manufacturer: nil,
      modelName: nil,
      location: location,
      services: [],
      discoveredAt: Date()
    )
  }
  
  private static func extractUUID(from usn: String) -> String {
    // USN format: uuid:device-UUID::device-type or uuid:device-UUID
    if let uuidRange = usn.range(of: #"uuid:[^:]+"#, options: .regularExpression) {
      let uuidStr = String(usn[uuidRange])
      return String(uuidStr.dropFirst(5)) // Remove "uuid:" prefix
    }
    return UUID().uuidString // Fallback
  }
  
  private static func extractDeviceType(from usn: String) -> String? {
    // Extract device type after ::
    if let range = usn.range(of: #"::(.+)"#, options: .regularExpression) {
      return String(usn[range]).replacingOccurrences(of: "::", with: "")
    }
    return nil
  }
}

