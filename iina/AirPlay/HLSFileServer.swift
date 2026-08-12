import Foundation
import Network

/// Minimal HTTP/1.1 static-file server over NWListener, bound to all interfaces,
/// used to serve a directory of HLS files to an AirPlay receiver on the LAN.
/// Supports GET and HEAD with optional byte-range requests (needed for fMP4 seeking).
/// Validated against an LG webOS TV via the scratch spike before integration.
enum HLSServerError: Error { case noLANAddress, noPort }

final class HLSFileServer {
  private var listener: NWListener?
  private let queue = DispatchQueue(label: "iina.airplay.hlsserver")
  private var rootDir = URL(fileURLWithPath: "/")

  /// Starts serving `dir`; returns the master playlist URL on the Mac's LAN IPv4.
  func start(servingFrom dir: URL, playlist: String = "out.m3u8") throws -> URL {
    stop()  // release any previous listener/port before rebinding
    rootDir = dir
    let listener = try NWListener(using: .tcp, on: .any)   // OS-assigned ephemeral port
    self.listener = listener
    listener.newConnectionHandler = { [weak self] conn in
      // Each connection gets its own queue: AVPlayer keeps several connections open at once
      // (playlist + segments, and a second player during the VOD reload). A single shared
      // serial queue would serialize them and stall later sessions.
      let connQueue = DispatchQueue(label: "iina.airplay.hlsconn")
      conn.start(queue: connQueue)
      self?.receive(conn, buffer: Data())
    }
    listener.start(queue: queue)
    let port = try Self.awaitPort(listener)
    guard let ip = Self.lanIPv4() else { throw HLSServerError.noLANAddress }
    return URL(string: "http://\(ip):\(port)/\(playlist)")!
  }

  func stop() { listener?.cancel(); listener = nil }

  private func receive(_ conn: NWConnection, buffer: Data) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, err in
      guard let self = self else { return }
      var buf = buffer
      if let data = data { buf.append(data) }
      let sep = Data("\r\n\r\n".utf8)
      if let r = buf.range(of: sep) {
        let header = String(data: buf.subdata(in: 0..<r.lowerBound), encoding: .utf8) ?? ""
        self.respond(conn, header: header)
      } else if err == nil && !done && buf.count < 16384 {
        self.receive(conn, buffer: buf)
      } else { conn.cancel() }
    }
  }

  private func respond(_ conn: NWConnection, header: String) {
    let lines = header.components(separatedBy: "\r\n")
    let parts = (lines.first ?? "").split(separator: " ")
    guard parts.count >= 2 else { return status(conn, 400) }
    let method = String(parts[0])
    guard method == "GET" || method == "HEAD" else { return status(conn, 405) }
    var path = String(parts[1])
    if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
    path = path.removingPercentEncoding ?? path
    let name = (path as NSString).lastPathComponent
    guard !name.isEmpty, !name.contains("..") else { return status(conn, 400) }
    guard let body = try? Data(contentsOf: rootDir.appendingPathComponent(name), options: .mappedIfSafe) else {
      NSLog("AirPlay/server: 404 %@ (dir=%@)", name, rootDir.path)
      return status(conn, 404)
    }
    let type = Self.contentType(for: name)
    let rangeLine = lines.first { $0.lowercased().hasPrefix("range:") }
    // HLS playlists change as the remux progresses (live → complete VOD); never let the
    // client cache them, or it keeps treating a completed stream as live (no duration/seek).
    let noCache = "Cache-Control: no-cache, no-store, must-revalidate\r\n"
    if let rl = rangeLine,
       let (s, e) = Self.parseRange(String(rl.dropFirst(6)).trimmingCharacters(in: .whitespaces), total: body.count) {
      let slice = body.subdata(in: s..<(e + 1))
      let head = "HTTP/1.1 206 Partial Content\r\nContent-Type: \(type)\r\n\(noCache)"
        + "Content-Range: bytes \(s)-\(e)/\(body.count)\r\nContent-Length: \(slice.count)\r\n"
        + "Accept-Ranges: bytes\r\nConnection: close\r\n\r\n"
      send(conn, Data(head.utf8) + (method == "HEAD" ? Data() : slice))
    } else {
      let head = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\n\(noCache)Content-Length: \(body.count)\r\n"
        + "Accept-Ranges: bytes\r\nConnection: close\r\n\r\n"
      send(conn, Data(head.utf8) + (method == "HEAD" ? Data() : body))
    }
  }

  private func status(_ conn: NWConnection, _ code: Int) {
    send(conn, Data("HTTP/1.1 \(code)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
  }
  private func send(_ conn: NWConnection, _ data: Data) {
    conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
  }

  static func contentType(for name: String) -> String {
    if name.hasSuffix(".m3u8") { return "application/vnd.apple.mpegurl" }
    if name.hasSuffix(".m4s") || name.hasSuffix(".mp4") { return "video/mp4" }
    if name.hasSuffix(".vtt") { return "text/vtt" }
    return "application/octet-stream"
  }
  static func parseRange(_ h: String, total: Int) -> (Int, Int)? {
    guard h.hasPrefix("bytes=") else { return nil }
    let c = h.dropFirst(6).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    guard let s = Int(c[0]) else { return nil }
    let e = (c.count > 1 ? Int(c[1]) : nil).map { min($0, total - 1) } ?? total - 1
    guard s >= 0, s <= e, e < total else { return nil }
    return (s, e)
  }
  static func awaitPort(_ l: NWListener) throws -> UInt16 {
    for _ in 0..<200 { if let p = l.port?.rawValue, p != 0 { return p }; usleep(10_000) }
    throw HLSServerError.noPort
  }
  static func lanIPv4() -> String? {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }
    for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let flags = Int32(ptr.pointee.ifa_flags)
      guard (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING), (flags & IFF_LOOPBACK) == 0 else { continue }
      guard ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
      let name = String(cString: ptr.pointee.ifa_name)
      guard name == "en0" || name == "en1" else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                  &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
      return String(cString: host)
    }
    return nil
  }
}
