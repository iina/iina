import Cocoa

final class ResetFilter {let label:String;init(_ label:String){self.label=label}}
typealias PlayerCore=PlayerFixture
extension Notification.Name {static let iinaVideoParamsChanged=Self("IINAVideoParamsChanged")}
extension PlayerFixture {
  func performSidebarChange<T>(_ action:()->T)->T {action()}
  func neutralizeTrackAudioEQ(_ profiles:[Int:AudioTrackProcessing],restoring:Bool=false)->Bool {true}
  func refreshTrackProcessing(_ type:TrackType,audioRollback:[Int:AudioTrackProcessing]=[:])->Bool {true}
  func setAudioDelay(_ value:Double){}
  func setAudioEq(fromGains values:[Double]){}
  func setVideoEqualizer(forOption:VideoEqualizerType,value:Int){}
  func removeVideoFilter(_ filter:String)->Bool {true}
  func removeVideoFilter(_ filter:ResetFilter)->Bool {
    cropRemovals+=1;mpv.filters.removeAll{$0.label==filter.label};return true
  }
  func beginPausedCropRefresh(){beginCropRefreshes+=1}
  func setScopedVideoRotate(_ value:Int){setVideoRotate(value)}
  func sendOSD(_ message:OSDMessage){settingOSDs+=1}
  // PRODUCTION_PLAYER_METHODS
}
enum PaddingDirection {case all}
extension NSView {
  func padding(_ edge:PaddingDirection){
    guard let parent=superview else{return}
    NSLayoutConstraint.activate([leadingAnchor.constraint(equalTo:parent.leadingAnchor,constant:8),trailingAnchor.constraint(equalTo:parent.trailingAnchor,constant:-8),topAnchor.constraint(equalTo:parent.topAnchor,constant:8),bottomAnchor.constraint(equalTo:parent.bottomAnchor,constant:-8)])
  }
}
struct NativeProperty {var data:UnsafeMutableRawPointer?;let format:Int}
final class RotationObserver {
  unowned let player:PlayerFixture
  var errors=0
  init(_ player:PlayerFixture){self.player=player}
  func logPropertyValueError(_ property:String,_ format:Int){errors+=1}
  func receive(_ value:Int64){
    var value=value
    withUnsafeMutablePointer(to:&value){pointer in
      handleProperty(NativeProperty(data:UnsafeMutableRawPointer(pointer),format:4))
    }
  }
  func handleProperty(_ property:NativeProperty){
    // OBSERVER_DISPATCH
    switch MPVOption.Video.videoRotate {
      // PRODUCTION_ROTATION_OBSERVER
    default:break
    }
  }
}
