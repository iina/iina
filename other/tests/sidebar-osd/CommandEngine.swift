  // Controlled C command boundary: copy argv while it is alive, then permit
  // acknowledgement or a newer mutation to interleave before returning status.
  struct CommandCall {let words:[String]?;let raw:String?;let onMain:Bool}
  var available=true,commands:[CommandCall]=[]
  var onCommand:((CommandCall)->Void)?
  func command(_ call:CommandCall)->Int32 {
    commands.append(call)
    let fails=failNext;failNext=false
    onCommand?(call)
    return fails ? -1:0
  }
