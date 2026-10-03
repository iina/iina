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

final class PlayerCore: NSObject {
  let timelineThumbnailBroker = TimelineThumbnailBroker()
  func validateTimelineThumbnailSession() { }
}

final class JavascriptPluginInstance: NSObject {
  weak var player: PlayerCore?
}

class JavascriptAPI: NSObject {
  weak var context: JSContext!
  weak var player: PlayerCore?

  init(context: JSContext, pluginInstance: JavascriptPluginInstance) {
    self.context = context
    self.player = pluginInstance.player
  }

  func throwError(withMessage message: String) {
    context.exception = JSValue(newErrorFromMessage: message, in: context)
  }

  func cleanUp(_ instance: JavascriptPluginInstance) { }
}

func createUInt8Array(fromData data: Data, in suppliedContext: JSContext? = nil) -> JSValue? {
  fatalError("The native broker tests do not exercise JavaScript transfer")
}
