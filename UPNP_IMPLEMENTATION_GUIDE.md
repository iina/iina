# UPnP/DLNA Implementation Quick Start Guide

This guide provides a practical starting point for implementing UPnP/DLNA support in IINA.

## Quick Implementation Strategy

### Minimal Viable Implementation

Start with a minimal SSDP client and basic content browsing. This avoids external dependencies and licensing issues.

## Step-by-Step Implementation

### Step 1: SSDP Discovery (BSD sockets, VLC-style)

`iina/UPnPManager.swift` implements SSDP discovery using a **plain UDP socket**, closely mirroring how VLC’s libupnp-based discovery works. The key ideas:

- Open a UDP socket (`socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)`).
- Set `SO_REUSEADDR` and a small multicast TTL so packets stay on the local LAN.
- Use `sendto()` to send multiple `M-SEARCH` queries to `239.255.255.250:1900` with common `ST` values (`ssdp:all`, `upnp:rootdevice`, media server and ContentDirectory URNs).
- Use a `DispatchSourceRead` wrapping the socket and call `recvfrom()` in the handler to receive every SSDP reply.
- For each reply, log a short snippet (for debugging) and feed the raw response string into `parseSSDPResponse(_:)`, which:
  - parses headers (`LOCATION`, `USN`, `ST`, `NT`, etc.),
  - then fetches and parses the device description XML to decide whether it exposes a `ContentDirectory` service.

This approach avoids the `NWConnection` quirks on some macOS setups and matches the robustness of VLC’s discovery: if VLC can see a UPnP/DLNA server, the BSD-socket-based discovery should see it as well.

### Step 2: Device Model

Create `iina/UPnPDevice.swift`:

```swift
import Foundation

struct UPnPDevice {
  let uuid: String
  let friendlyName: String
  let deviceType: String
  let location: URL  // URL to device description XML
  let services: [UPnPService]
  
  struct UPnPService {
    let serviceType: String
    let controlURL: URL
    let eventSubURL: URL
  }
}

extension UPnPDevice {
  // Parse from SSDP response
  static func from(ssdpResponse: String) -> UPnPDevice? {
    // Parse SSDP headers
    // Extract LOCATION header
    // Fetch and parse device description XML
    return nil
  }
}
```

### Step 3: Content Directory Service

Add to `UPnPManager.swift`:

```swift
extension UPnPManager {
  func browseContent(device: UPnPDevice, objectID: String = "0") async throws -> [UPnPItem] {
    guard let contentDirService = device.services.first(where: { 
      $0.serviceType.contains("ContentDirectory") 
    }) else {
      throw UPnPError.serviceNotFound
    }
    
    // SOAP action to browse
    let soapAction = """
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
    
    // Make SOAP request
    var request = URLRequest(url: contentDirService.controlURL)
    request.httpMethod = "POST"
    request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
    request.setValue("\"urn:schemas-upnp-org:service:ContentDirectory:1#Browse\"", 
                     forHTTPHeaderField: "SOAPAction")
    request.httpBody = soapAction.data(using: .utf8)
    
    let (data, _) = try await URLSession.shared.data(for: request)
    
    // Parse SOAP response and extract DIDL-Lite XML
    return try parseDIDLLite(data: data)
  }
  
  private func parseDIDLLite(data: Data) throws -> [UPnPItem] {
    // Use XMLParser to parse DIDL-Lite
    // Extract items with res (resource) URLs
    return []
  }
}
```

### Step 4: Media Item Model

Create `iina/UPnPItem.swift`:

```swift
import Foundation

struct UPnPItem {
  let id: String
  let title: String
  let itemType: ItemType
  let resourceURL: URL?  // Direct playback URL
  let parentID: String
  
  enum ItemType {
    case container  // Folder/directory
    case item       // Media file
  }
  
  var isPlayable: Bool {
    itemType == .item && resourceURL != nil
  }
}
```

### Step 5: UI Integration

Create `iina/UPnPBrowserWindowController.swift`:

```swift
import Cocoa

class UPnPBrowserWindowController: NSWindowController {
  
  @IBOutlet weak var deviceTableView: NSTableView!
  @IBOutlet weak var contentOutlineView: NSOutlineView!
  
  private var devices: [UPnPDevice] = []
  private var contentCache: [String: [UPnPItem]] = [:]  // objectID -> items
  
  override func windowDidLoad() {
    super.windowDidLoad()
    startDiscovery()
  }
  
  private func startDiscovery() {
    UPnPManager.shared.startDiscovery()
    // Observe device updates
  }
  
  @IBAction func refreshDevices(_ sender: Any) {
    UPnPManager.shared.startDiscovery()
  }
  
  // Handle device selection
  // Handle content browsing
  // Handle play action
}
```

### Step 6: Menu Integration

Modify `iina/AppDelegate.swift`:

```swift
@IBAction func openUPnP(_ sender: AnyObject) {
  let browser = UPnPBrowserWindowController()
  browser.showWindow(nil)
}
```

Add to `iina/Base.lproj/MainMenu.xib`:
- New menu item: "Open from UPnP/DLNA Server..."
- Connect to `openUPnP:` action

### Step 7: Playback Integration

Modify `iina/PlayerCore.swift`:

```swift
// In openURL or similar method
func openUPnPItem(_ item: UPnPItem) {
  guard let url = item.resourceURL else { return }
  openURL(url)  // Existing method handles network URLs
}
```

## Key Implementation Details

### SSDP Protocol

1. **M-SEARCH Request**:
   - Send UDP multicast to `239.255.255.250:1900`
   - Search target: `urn:schemas-upnp-org:device:MediaServer:1`
   - Wait for responses (typically 1-3 seconds)

2. **SSDP Response**:
   - Contains `LOCATION` header with device description URL
   - Fetch device description XML
   - Parse services and capabilities

### ContentDirectory Service

1. **Browse Action**:
   - SOAP request to `ContentDirectory` service
   - Browse flag: `BrowseDirectChildren` or `BrowseMetadata`
   - Returns DIDL-Lite XML

2. **DIDL-Lite Parsing**:
   - XML format describing media items
   - Extract `<item>` or `<container>` elements
   - Get `<res>` (resource) URL for playback

### URL Handling

- UPnP items provide direct HTTP URLs
- These can be passed directly to `PlayerCore.openURL()`
- mpv handles HTTP streaming natively

## Testing

### Test Servers

1. **Plex Media Server** (if DLNA enabled)
2. **Kodi** (with UPnP enabled)
3. **Universal Media Server**
4. **Simple DLNA server** (for development)

### Test Checklist

- [ ] Device discovery works
- [ ] Device list populates
- [ ] Content browsing works
- [ ] Video playback works
- [ ] Audio playback works
- [ ] Error handling for offline devices
- [ ] UI is responsive during network operations

## Performance Considerations

1. **Async Operations**:
   - Use async/await for network operations
   - Don't block main thread

2. **Caching**:
   - Cache device descriptions
   - Cache content listings
   - Refresh on demand

3. **Connection Management**:
   - Reuse connections where possible
   - Handle network errors gracefully

## Error Handling

```swift
enum UPnPError: Error {
  case discoveryFailed
  case deviceNotFound
  case serviceNotFound
  case browseFailed
  case invalidResponse
  case networkError(Error)
}
```

## Next Steps After MVP

1. **Add Search Functionality**
2. **Add Favorites/Bookmarks**
3. **Add Thumbnail Support**
4. **Add Metadata Display**
5. **Add Playlist Integration**
6. **Add Preferences Panel**

## Resources

- **SSDP Specification**: RFC 2608
- **UPnP Device Architecture**: http://upnp.org/specs/arch/
- **DLNA Guidelines**: http://www.dlna.org/
- **DIDL-Lite Schema**: Part of UPnP AV specification

## License Considerations

- IINA uses GPL v3 (check LICENSE file)
- Any libraries you use must be compatible
- Custom implementation avoids licensing issues
- If using external libraries, ensure GPL compatibility

---

This is a starting point. The actual implementation will require more detail, but this provides the core structure needed to get UPnP/DLNA working in IINA.

