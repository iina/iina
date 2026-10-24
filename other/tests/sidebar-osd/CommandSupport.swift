// MPVCommand's string wrapper and native status are boundaries; routing and
// both real command overloads are extracted unchanged from MPVController.
struct MPVCommand {let rawValue:String;init(_ value:String){rawValue=value}}
struct NativeStatus {let rawValue:Int32}
let MPV_ERROR_UNINITIALIZED=NativeStatus(rawValue:-3)
func mpv_command(_ handle:OpaquePointer?,_ args:inout [UnsafePointer<CChar>?])->Int32 {
  let words=args.prefix(while:{$0 != nil}).map{String(cString:$0!)}
  return engine(handle).command(.init(words:words,raw:nil,onMain:Thread.isMainThread))
}
func mpv_command_string(_ handle:OpaquePointer?,_ raw:String)->Int32 {
  engine(handle).command(.init(words:nil,raw:raw,onMain:Thread.isMainThread))
}
enum CommandPath:CaseIterable,Equatable {
  case array,raw
  func call(_ c:Controller,_ words:[String],checkError:Bool=true,callback:((Int32)->Void)?=nil)->Int32? {
    switch self {
    case .array:
      c.command(MPVCommand(words[0]),args:Array(words.dropFirst()).map{Optional($0)},checkError:checkError,returnValueCallback:callback)
      return nil
    case .raw:return c.command(rawString:words.joined(separator:" "))
    }
  }
}
