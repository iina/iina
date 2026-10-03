import Cocoa
import JavaScriptCore

struct TestFailure: Error, CustomStringConvertible {
  let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  if !condition() { throw TestFailure(description: message) }
}

func makeCGImage(width: Int = 240, height: Int = 135) throws -> CGImage {
  guard let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    throw TestFailure(description: "Cannot create fixture bitmap context")
  }
  context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  guard let image = context.makeImage() else {
    throw TestFailure(description: "Cannot create fixture CGImage")
  }
  return image
}

func makeNoiseImage(width: Int, height: Int) throws -> CGImage {
  var bytes = [UInt8](repeating: 255, count: width * height * 4)
  var random: UInt32 = 0x12345678
  for pixel in 0..<(width * height) {
    for channel in 0..<3 {
      random ^= random << 13
      random ^= random >> 17
      random ^= random << 5
      bytes[pixel * 4 + channel] = UInt8(truncatingIfNeeded: random)
    }
  }
  guard let provider = CGDataProvider(data: Data(bytes) as CFData),
        let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                            bitsPerPixel: 32, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent) else {
    throw TestFailure(description: "Cannot create deterministic noise fixture")
  }
  return image
}

func thumbnail(_ image: NSImage?, timestamp: Double = 12.5) -> FFThumbnail {
  let frame = FFThumbnail()
  frame.image = image
  frame.realTime = timestamp
  return frame
}

func identity(_ id: String = "session-1") -> TimelineThumbnailMediaIdentity {
  TimelineThumbnailMediaIdentity(sessionID: id, url: "file:///fixture.mkv",
                                 fileSize: 100, modificationDate: 200,
                                 fileID: 1, videoTrack: nil)
}

// Subscribe synchronously to flush encoding and capture the current snapshot.
func snapshot(_ broker: TimelineThumbnailBroker) throws -> TimelineThumbnailUpdate {
  var update: TimelineThumbnailUpdate?
  let token = broker.subscribe { update = $0 }
  broker.unsubscribe(token)
  guard let update else { throw TestFailure(description: "Missing broker snapshot") }
  return update
}

func expectRedJPEG(_ encoded: TimelineThumbnailEncoded) throws {
  try expect(encoded.data.starts(with: [0xff, 0xd8]), "Not JPEG bytes")
  guard let bitmap = NSBitmapImageRep(data: encoded.data),
        let color = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else {
    throw TestFailure(description: "Cannot decode exported JPEG")
  }
  try expect(bitmap.pixelsWide == 240 && bitmap.pixelsHigh == 135, "Wrong JPEG dimensions")
  try expect(color.redComponent > 0.9 && color.greenComponent < 0.4 && color.blueComponent < 0.1,
             "Exported JPEG RGB=\(color.redComponent),\(color.greenComponent),\(color.blueComponent)")
  try expect(encoded.timestamp == 12.5, "Timestamp changed")
  try expect(encoded.mimeType == "image/jpeg", "Wrong MIME type")
}

func testFreshCGImagePartialAndReady() throws {
  // This is the constructor used by FFmpegController.saveThumbnail.
  let image = NSImage(cgImage: try makeCGImage(), size: .zero)
  print("Fresh image representations: \(image.representations.map { String(describing: type(of: $0)) })")
  let broker = TimelineThumbnailBroker()
  let session = broker.beginSession(identity(), cacheName: nil)
  broker.publishPartial([thumbnail(image)], progress: 0.5, for: session)
  let partial = try snapshot(broker)
  try expect(partial.state == .partial && partial.progress == 0.5, "Wrong partial state")
  try expect(partial.thumbnails.count == 1, "Fresh CGImage partial thumbnail was dropped")
  try expectRedJPEG(partial.thumbnails[0])

  broker.publishReady([thumbnail(image)], for: session)
  let ready = try snapshot(broker)
  try expect(ready.state == .ready && ready.progress == 1, "Wrong ready state")
  try expect(ready.thumbnails.count == 1, "Fresh CGImage ready thumbnail was dropped")
  try expectRedJPEG(ready.thumbnails[0])
}

func testCacheDecodedImageReady() throws {
  let fresh = NSImage(cgImage: try makeCGImage(), size: .zero)
  // Match ThumbnailCache's TIFF -> JPEG write and NSImage(data:) read path.
  guard let tiff = fresh.tiffRepresentation,
        let jpeg = NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.75]),
        let cached = NSImage(data: jpeg) else {
    throw TestFailure(description: "Cannot prepare cache-decoded fixture")
  }
  let broker = TimelineThumbnailBroker()
  let session = broker.beginSession(identity(), cacheName: "fixture")
  broker.publishReady([thumbnail(cached)], for: session)
  let ready = try snapshot(broker)
  try expect(ready.state == .ready && ready.thumbnails.count == 1, "Cache thumbnail was dropped")
  try expectRedJPEG(ready.thumbnails[0])
}

func testMalformedAndOversizedImages() throws {
  let oversized = NSImage(cgImage: try makeCGImage(width: 4097, height: 2), size: .zero)
  let valid = NSImage(cgImage: try makeCGImage(), size: .zero)
  let broker = TimelineThumbnailBroker()
  let session = broker.beginSession(identity(), cacheName: nil)
  broker.publishReady([thumbnail(nil), thumbnail(oversized), thumbnail(valid)], for: session)
  let ready = try snapshot(broker)
  try expect(ready.thumbnails.count == 1, "Malformed/oversized rejection dropped the valid frame")
  try expectRedJPEG(ready.thumbnails[0])
}

func testCumulativeCountBound() throws {
  let frame = thumbnail(NSImage(cgImage: try makeCGImage(), size: .zero))
  let broker = TimelineThumbnailBroker()
  let session = broker.beginSession(identity(), cacheName: nil)
  broker.publishPartial(Array(repeating: frame, count: 100), progress: 0.5, for: session)
  broker.publishPartial(Array(repeating: frame, count: 100), progress: 0.8, for: session)
  let partial = try snapshot(broker)
  try expect(partial.thumbnails.count == TimelineThumbnailBroker.maxThumbnailCount, "Cumulative count is not bounded")
  try expect(partial.thumbnails.reduce(0) { $0 + $1.data.count } <= TimelineThumbnailBroker.maxBytesPerUpdate,
             "Cumulative bytes exceed the update limit")
}

func testPerImageByteBound() throws {
  let large = try makeNoiseImage(width: 1024, height: 1024)
  guard let jpeg = NSBitmapImageRep(cgImage: large).representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else {
    throw TestFailure(description: "Cannot encode high-entropy fixture")
  }
  try expect(jpeg.count > TimelineThumbnailBroker.maxBytesPerThumbnail, "Noise fixture does not exceed the per-image limit")
  let valid = thumbnail(NSImage(cgImage: try makeCGImage(), size: .zero))
  let broker = TimelineThumbnailBroker()
  let session = broker.beginSession(identity(), cacheName: nil)
  broker.publishReady([thumbnail(NSImage(cgImage: large, size: .zero)), valid], for: session)
  let ready = try snapshot(broker)
  try expect(ready.thumbnails.count == 1, "Oversized JPEG was accepted or suppressed the valid frame")
  try expectRedJPEG(ready.thumbnails[0])
}

func testCumulativeByteBound() throws {
  let noise = thumbnail(NSImage(cgImage: try makeNoiseImage(width: 512, height: 512), size: .zero))
  let broker = TimelineThumbnailBroker()
  let session = broker.beginSession(identity(), cacheName: nil)
  broker.publishPartial([noise], progress: 0.1, for: session)
  let first = try snapshot(broker)
  try expect(first.thumbnails.count == 1, "Noise fixture exceeds the per-image limit")
  let itemBytes = first.thumbnails[0].data.count
  let expectedCount = TimelineThumbnailBroker.maxBytesPerUpdate / itemBytes
  try expect(expectedCount < TimelineThumbnailBroker.maxThumbnailCount, "Fixture does not exercise the total-byte limit")

  let smallImage = try makeCGImage()
  guard let smallJPEG = NSBitmapImageRep(cgImage: smallImage).representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else {
    throw TestFailure(description: "Cannot encode small fixture")
  }
  let smallFits = TimelineThumbnailBroker.maxBytesPerUpdate % itemBytes >= smallJPEG.count
  let small = thumbnail(NSImage(cgImage: smallImage, size: .zero), timestamp: 99)
  broker.publishPartial(Array(repeating: noise, count: 128) + [small], progress: 0.8, for: session)
  let partial = try snapshot(broker)
  try expect(partial.thumbnails.count == expectedCount + (smallFits ? 1 : 0), "Total-byte bound rejected the wrong number of frames")
  try expect(partial.thumbnails.contains { $0.timestamp == 99 } == smallFits,
             "Later small frame did not obey the remaining byte budget")
  try expect(partial.thumbnails.reduce(0) { $0 + $1.data.count } <= TimelineThumbnailBroker.maxBytesPerUpdate,
             "Cumulative JPEG bytes exceed the update limit")
}

func testInvalidationDropsQueuedResults() throws {
  let frame = thumbnail(NSImage(cgImage: try makeCGImage(), size: .zero))
  let broker = TimelineThumbnailBroker()
  let old = broker.beginSession(identity("old"), cacheName: nil)
  broker.invalidate(reason: "video-track-changed")
  let current = broker.beginSession(identity("new"), cacheName: nil)
  broker.publishReady([frame], for: old)
  let generating = try snapshot(broker)
  try expect(generating.media?.sessionID == "new" && generating.thumbnails.isEmpty,
             "Stale encoded results entered the new session")
  broker.publishReady([frame], for: current)
  let ready = try snapshot(broker)
  try expect(ready.thumbnails.count == 1, "Current session did not encode")
}

final class BridgeFixture {
  let context = JSContext()!
  let player = PlayerCore()
  let instance = JavascriptPluginInstance()
  let api: JavascriptAPIThumbnails

  init(_ callback: String = "function(update) { events.push({state: update.state, session: update.media && update.media.sessionId}); }") {
    instance.player = player
    api = JavascriptAPIThumbnails(context: context, pluginInstance: instance)
    context.setObject(api, forKeyedSubscript: "thumbnails" as NSString)
    autoreleasepool {
      _ = context.evaluateScript("var events = []; var subscription = thumbnails.subscribe(\(callback));")
    }
  }

  deinit { api.cleanUp(instance) }

  func drain() {
    autoreleasepool {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
  }

  func states() -> [String] {
    context.evaluateScript("events.map(function(event) { return event.state; })")?.toArray() as? [String] ?? []
  }
}

func testCallbackSurvivesJavaScriptGC() throws {
  let fixture = BridgeFixture()
  fixture.drain()
  for _ in 0..<3 {
    autoreleasepool {
      _ = fixture.context.evaluateScript("(function() { var garbage = []; for (var i = 0; i < 1024; i++) garbage.push(new Array(4096).fill(i)); })();")
    }
  }
  JSGarbageCollect(fixture.context.jsGlobalContextRef)
  let session = fixture.player.timelineThumbnailBroker.beginSession(identity(), cacheName: nil)
  fixture.drain()
  fixture.player.timelineThumbnailBroker.publishReady([], for: session)
  _ = try snapshot(fixture.player.timelineThumbnailBroker)
  fixture.drain()
  try expect(fixture.states().suffix(2) == ["generating", "ready"],
             "Callback was collected while the subscription remained active")
}

func testInvalidationPrecedesReplacementSession() throws {
  let fixture = BridgeFixture()
  fixture.drain()
  _ = fixture.player.timelineThumbnailBroker.beginSession(identity("old"), cacheName: nil)
  fixture.drain()
  fixture.context.evaluateScript("events = [];")
  fixture.player.timelineThumbnailBroker.invalidate(reason: "video-track-changed")
  _ = fixture.player.timelineThumbnailBroker.beginSession(identity("new"), cacheName: nil)
  fixture.drain()
  try expect(fixture.states() == ["invalidated", "generating"], "Invalidation was coalesced away")
  let sessions = fixture.context.evaluateScript("events.map(function(event) { return event.session; })")?.toArray() as? [String]
  try expect(sessions == ["old", "new"], "Invalidation/replacement media identity changed")
}

func testUnsubscribeDuringInvalidationStopsReplacement() throws {
  let fixture = BridgeFixture("function(update) { events.push({state: update.state}); if (update.state === 'invalidated') thumbnails.unsubscribe(subscription); }")
  fixture.drain()
  _ = fixture.player.timelineThumbnailBroker.beginSession(identity("old"), cacheName: nil)
  fixture.drain()
  fixture.context.evaluateScript("events = [];")
  fixture.player.timelineThumbnailBroker.invalidate(reason: "file-changed")
  _ = fixture.player.timelineThumbnailBroker.beginSession(identity("new"), cacheName: nil)
  fixture.drain()
  try expect(fixture.states() == ["invalidated"], "Replacement callback ran after unsubscribe")
}

func testRapidReplacementKeepsOldInvalidationAndLatestSession() throws {
  let fixture = BridgeFixture()
  fixture.drain()
  _ = fixture.player.timelineThumbnailBroker.beginSession(identity("old"), cacheName: nil)
  fixture.drain()
  fixture.context.evaluateScript("events = [];")
  fixture.player.timelineThumbnailBroker.invalidate(reason: "video-track-changed")
  _ = fixture.player.timelineThumbnailBroker.beginSession(identity("intermediate"), cacheName: nil)
  fixture.player.timelineThumbnailBroker.invalidate(reason: "video-track-changed")
  _ = fixture.player.timelineThumbnailBroker.beginSession(identity("latest"), cacheName: nil)
  fixture.drain()
  try expect(fixture.states() == ["invalidated", "generating"], "Rapid replacements emitted extra or missing callbacks")
  let sessions = fixture.context.evaluateScript("events.map(function(event) { return event.session; })")?.toArray() as? [String]
  try expect(sessions == ["old", "latest"], "An intermediate session crossed the invalidation barrier")
}

func testCleanupStopsQueuedJavaScriptDelivery() throws {
  let fixture = BridgeFixture()
  fixture.drain()
  fixture.context.evaluateScript("events = [];")
  _ = fixture.player.timelineThumbnailBroker.beginSession(identity(), cacheName: nil)
  fixture.api.cleanUp(fixture.instance)
  JSGarbageCollect(fixture.context.jsGlobalContextRef)
  fixture.drain()
  try expect(fixture.states().isEmpty, "Queued callback survived plugin cleanup")
}

let tests: [(String, () throws -> Void)] = [
  ("fresh CGImage partial/ready", testFreshCGImagePartialAndReady),
  ("cache-decoded ready", testCacheDecodedImageReady),
  ("malformed/oversized images", testMalformedAndOversizedImages),
  ("cumulative count bound", testCumulativeCountBound),
  ("per-image JPEG byte bound", testPerImageByteBound),
  ("cumulative JPEG byte bound", testCumulativeByteBound),
  ("session invalidation", testInvalidationDropsQueuedResults),
  ("callback survives JavaScript GC", testCallbackSurvivesJavaScriptGC),
  ("invalidation delivery barrier", testInvalidationPrecedesReplacementSession),
  ("unsubscribe during invalidation", testUnsubscribeDuringInvalidationStopsReplacement),
  ("rapid replacement barrier", testRapidReplacementKeepsOldInvalidationAndLatestSession),
  ("queued callback cleanup", testCleanupStopsQueuedJavaScriptDelivery)
]
var failures = 0
for (name, test) in tests {
  do {
    try autoreleasepool { try test() }
    print("PASS: \(name)")
  } catch {
    failures += 1
    print("FAIL: \(name): \(error)")
  }
}
print("Native broker tests: \(tests.count - failures)/\(tests.count) passed")
exit(failures == 0 ? 0 : 1)
