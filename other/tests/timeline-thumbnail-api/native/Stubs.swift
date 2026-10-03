import Cocoa
import JavaScriptCore

// Type dependencies for compiling the production broker without the player target.
final class FFThumbnail: NSObject {
  var image: NSImage?
  var realTime = 0.0
}

final class MPVTrack {
  var id = 1
  var srcId: Int?
  var codec: String?
  var externalFilename: String?
  var ffIndex: Int?
  var demuxW: Int?
  var demuxH: Int?
  var demuxFps: Double?
}

func createUInt8Array(fromData data: Data, in suppliedContext: JSContext? = nil) -> JSValue? {
  fatalError("The native broker tests do not exercise JavaScript transfer")
}
