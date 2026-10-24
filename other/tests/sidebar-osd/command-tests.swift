// These tests drive actual prepareCommandOSD and both native command overloads.
// C calls and engine event production are controlled; no player is opened.
for path in CommandPath.allCases {
  let p=PlayerFixture(),c=Controller(p)
  var armedBeforeNative=false
  c.native.onCommand={_ in armedBeforeNative=p.shouldShowSeekOSD}
  _=path.call(c,["seek","5","relative"])
  check(armedBeforeNative && p.shouldShowSeekOSD,"\(path) explicit seek arms intent before the native command")
  check(c.native.commands.count==1 && c.native.commands[0].onMain,"\(path) reaches exactly one native call")
  check(path == .array ? c.native.commands[0].words==["seek","5","relative"]:c.native.commands[0].raw=="seek 5 relative","\(path) forwards command arguments unchanged")
}
for path in CommandPath.allCases {
  let p=PlayerFixture(),c=Controller(p);c.native.available=false
  let result=path.call(c,["seek","5"])
  check(!p.shouldShowSeekOSD && c.native.commands.isEmpty,"\(path) uninitialized controller does not arm or issue a native command")
  check(path == .array ? result == nil:result == MPV_ERROR_UNINITIALIZED.rawValue,"\(path) preserves its uninitialized return contract")
}
for path in CommandPath.allCases {
  let p=PlayerFixture(),c=Controller(p)
  _=path.call(c,["show-text","fixture"])
  check(!p.shouldShowSeekOSD,"\(path) unrelated command does not arm explicit seek")
  var recorded=false
  c.native.onCommand={_ in recorded=p.osdFeedbackOrigins.origin(for:"speed",value:.number(2)) == .sidebar}
  p.performSidebarChange{_=path.call(c,["set","options/speed","2"])}
  c.observe("speed",.number(2));drain();drain()
  check(recorded,"\(path) property command records typed UI intent before native publication")
  check(p.mainWindow.deliveries.isEmpty && p.info.playSpeed==2 && p.notifications==[.iinaSpeedChanged],"\(path) property acknowledgement stays quiet without skipping cache or notifications")
}
for path in CommandPath.allCases {
  let p=PlayerFixture(),c=Controller(p)
  p.performSidebarChange{c.setDouble("speed",2);c.setInt("brightness",10)}
  _=path.call(c,["set","speed","2"])
  c.observe("speed",.number(2));c.observe("brightness",.integer(10));drain();drain()
  check(p.mainWindow.sidebarOpen && p.mainWindow.deliveries.count==1,"\(path) normal same-value property command is visible while sidebar stays open")
  check(p.info.playSpeed==2 && p.info.brightness==10 && p.notifications.count==2,"\(path) normal command clears only its property and retains the other UI acknowledgement")
}
for path in CommandPath.allCases {
  let p=PlayerFixture(),c=Controller(p)
  p.performSidebarChange{c.setDouble("speed",1);c.setInt("brightness",10)}
  c.native.failNext=true
  p.performSidebarChange{_=path.call(c,["set","speed","2"])}
  c.observe("speed",.number(1));c.observe("brightness",.integer(10));drain();drain()
  check(p.mainWindow.deliveries.isEmpty,"\(path) failed property command retains earlier and unrelated valid UI intents")
  c.observe("speed",.number(2));drain();drain()
  check(p.mainWindow.deliveries.count==1,"\(path) failed command value cannot suppress a later external acknowledgement")
}
for path in CommandPath.allCases {
  let p=PlayerFixture(),c=Controller(p);c.native.failNext=true
  c.native.onCommand={_ in p.performSidebarChange{c.setDouble("speed",3)}}
  p.performSidebarChange{_=path.call(c,["set","speed","2"])}
  c.observe("speed",.number(3));drain();drain()
  check(p.mainWindow.deliveries.isEmpty && p.info.playSpeed==3,"\(path) failed older command cancels only its token after a newer UI write")
}
for path in CommandPath.allCases {
  let p=PlayerFixture(),c=Controller(p);c.native.failNext=true
  _=path.call(c,["seek","5"])
  check(!p.shouldShowSeekOSD,"\(path) failed seek cancels its own intent")
  var newer:UUID?
  c.native.failNext=true;c.native.onCommand={_ in newer=p.userInitiatedSeek()}
  _=path.call(c,["seek","10"])
  check(p.shouldShowSeekOSD && p.testSeekToken==newer,"\(path) failed seek cannot cancel a newer user seek token")
}
do {
  let p=PlayerFixture(),c=Controller(p)
  p.performSidebarChange{c.setInt("brightness",10)}
  // The entire raw command list receives one failure; both preparations must
  // roll back while an unrelated property retains its valid UI attribution.
  c.native.failNext=true
  let result=p.performSidebarChange{c.command(rawString:"set speed 2; seek 5")}
  check(result == -1 && !p.shouldShowSeekOSD,"raw mixed property+seek failure rolls back both prepared intent types")
  c.observe("brightness",.integer(10));c.observe("speed",.number(2));drain();drain()
  check(p.mainWindow.deliveries.count==1,"raw mixed failure retains unrelated UI acknowledgement but exposes failed property's later value")
}
do {
  let p=PlayerFixture(),c=Controller(p);c.native.failNext=true
  var callback:Int32?
  c.command(MPVCommand("seek"),args:["5"],checkError:false,returnValueCallback:{callback=$0})
  check(callback == -1 && c.errors==0 && !p.shouldShowSeekOSD,"array failure cleanup runs even with callback instead of error checking")
  c.native.failNext=true;c.command(MPVCommand("seek"),args:["5"])
  check(c.errors==1 && !p.shouldShowSeekOSD,"array checked failure retains existing error reporting after cleanup")
}
for path in CommandPath.allCases {
  let p=PlayerFixture(),c=Controller(p),done=DispatchSemaphore(value:0)
  var eventSawIntent=false
  c.native.onCommand={call in
    precondition(!call.onMain)
    DispatchQueue.main.async{eventSawIntent=p.shouldShowSeekOSD}
  }
  DispatchQueue.global().async{_=path.call(c,["seek","5"]);done.signal()}
  check(done.wait(timeout:.now()+2) == .success,"\(path) background command returns without blocking main")
  check(!p.shouldShowSeekOSD,"\(path) background preparation defers main-owned seek state")
  drain()
  check(eventSawIntent && p.shouldShowSeekOSD,"\(path) background seek ticket reaches main before resulting event callback")
}
for path in CommandPath.allCases {
  let p=PlayerFixture(),c=Controller(p),done=DispatchSemaphore(value:0)
  c.native.failNext=true
  DispatchQueue.global().async{_=path.call(c,["seek","5"]);done.signal()}
  check(done.wait(timeout:.now()+2) == .success,"\(path) failed background seek returns without blocking main")
  drain()
  check(!p.shouldShowSeekOSD && p.testSeekToken==nil,"\(path) failed background seek cancels the ticket after its queued main arming")
}
for path in CommandPath.allCases {
  let p=PlayerFixture(),c=Controller(p),done=DispatchSemaphore(value:0)
  var newer:UUID?
  c.native.failNext=true
  c.native.onCommand={_ in DispatchQueue.main.async{newer=p.userInitiatedSeek()}}
  DispatchQueue.global().async{_=path.call(c,["seek","5"]);done.signal()}
  check(done.wait(timeout:.now()+2) == .success,"\(path) failed background command returns without blocking main")
  drain()
  check(p.shouldShowSeekOSD && p.testSeekToken==newer,"\(path) queued failure rollback runs after arming and preserves newer main-queue intent")
}
for path in CommandPath.allCases {
  let p=PlayerFixture(),c=Controller(p),done=DispatchSemaphore(value:0)
  p.performSidebarChange{c.setDouble("speed",2)}
  c.native.onCommand={_ in c.observe("speed",.number(2))}
  p.performSidebarChange{
    DispatchQueue.global().async{_=path.call(c,["set","speed","2"]);done.signal()}
    check(done.wait(timeout:.now()+2) == .success,"\(path) background property command completes during an unrelated main sidebar context")
  }
  drain();drain()
  check(p.mainWindow.deliveries.count==1,"\(path) background command clears old UI provenance before its observation and stays visible")
}
print("Sidebar OSD command integration: \(checks) extracted prepare/array/raw/rollback/queue checks; failures=\(failures.count)")
if !failures.isEmpty{exit(1)}
