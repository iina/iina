enum Logger {enum Level {case debug,error}}
enum MPVOption {
  enum PlaybackControl {static let speed="speed"}
  enum Video {static let hwdec="hwdec"}
  enum Audio {static let mute="mute",audioDelay="audio-delay"}
  enum Equalizer {static let brightness="brightness"}
}
typealias mpv_format=Int32
let MPV_FORMAT_NONE:mpv_format=0,MPV_FORMAT_FLAG:mpv_format=1,MPV_FORMAT_INT64:mpv_format=2,MPV_FORMAT_DOUBLE:mpv_format=3,MPV_FORMAT_STRING:mpv_format=4,MPV_FORMAT_NODE:mpv_format=5
struct mpv_event_property {var data:UnsafeMutableRawPointer!;let format:mpv_format}
final class NativeEngine {
  var failNext=false,writes:[(String,OSDFeedbackValue)]=[]
  var onWrite:((String,OSDFeedbackValue)->Void)?
  func write(_ name:String,_ value:OSDFeedbackValue)->Int32 {
    writes.append((name,value));let fails=failNext;failNext=false;onWrite?(name,value);return fails ? -1:0
  }
}
func engine(_ handle:OpaquePointer?)->NativeEngine {Unmanaged<NativeEngine>.fromOpaque(UnsafeRawPointer(handle!)).takeUnretainedValue()}
func mpv_set_property(_ handle:OpaquePointer?,_ name:String,_ format:mpv_format,_ data:UnsafeMutableRawPointer)->Int32 {
  let value:OSDFeedbackValue
  switch format {
  case MPV_FORMAT_FLAG:value = .number(data.load(as:Int32.self) != 0 ? 1:0)
  case MPV_FORMAT_INT64:value = .number(Double(data.load(as:Int64.self)))
  case MPV_FORMAT_DOUBLE:value = .number(data.load(as:Double.self))
  default:preconditionFailure("unexpected native write format")
  }
  return engine(handle).write(name,value)
}
func mpv_set_property_string(_ handle:OpaquePointer?,_ name:String,_ value:String)->Int32 {engine(handle).write(name,OSDFeedbackValue(value))}
final class Controller {
  unowned let player:PlayerFixture
  let native=NativeEngine(),queue=DispatchQueue(label:"test.sidebar-osd.observations")
  let observeProperties:[String:mpv_format]=["speed":MPV_FORMAT_DOUBLE,"brightness":MPV_FORMAT_INT64,"mute":MPV_FORMAT_FLAG,"hwdec":MPV_FORMAT_STRING,"audio-delay":MPV_FORMAT_DOUBLE,"vf":MPV_FORMAT_NONE,"af":MPV_FORMAT_NONE,"sub-font":MPV_FORMAT_NONE,"sub-font-size":MPV_FORMAT_NONE,"video-out-params":MPV_FORMAT_NODE]
  var errors=0
  var mpv:OpaquePointer! {OpaquePointer(Unmanaged.passUnretained(native).toOpaque())}
  init(_ player:PlayerFixture){self.player=player}
  func log(_ value:String,level:Logger.Level){}
  func logPropertyValueError(_ name:String,_ format:mpv_format){errors+=1}
  enum Observation {case flag(Bool),integer(Int64),number(Double),text(String),missing}
  func observe(_ name:String,_ value:Observation){
    queue.sync {
      func send<T>(_ value:inout T,_ format:mpv_format){withUnsafeMutablePointer(to:&value){pointer in handlePropertyChange(name,.init(data:UnsafeMutableRawPointer(pointer),format:format))}}
      switch value {
      case .flag(let value):var copy:Int32=value ? 1:0;send(&copy,MPV_FORMAT_FLAG)
      case .integer(let value):var copy=value;send(&copy,MPV_FORMAT_INT64)
      case .number(let value):var copy=value;send(&copy,MPV_FORMAT_DOUBLE)
      case .text(let value):
        let bytes=strdup(value)!
        defer{free(bytes)}
        var copy:UnsafePointer<CChar>?=UnsafePointer(bytes);send(&copy,MPV_FORMAT_STRING)
      case .missing:handlePropertyChange(name,.init(data:nil,format:MPV_FORMAT_NONE))
      }
    }
  }
  // PRODUCTION_MPV_METHODS
}
