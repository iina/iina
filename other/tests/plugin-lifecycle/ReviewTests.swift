import Cocoa
import JavaScriptCore

// Compiled into the disposable laboratory executable only.
enum LifecycleReviewTests {
  static func run(plugin: JavascriptPlugin, root: String, red: Bool) {
    let env = ProcessInfo.processInfo.environment
    let url = env["IINA_LIFECYCLE_HTTP_URL"]!
    let folder = env["IINA_LIFECYCLE_REVIEW_RUN"]!
    func pump(_ seconds: Double) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
    func fresh() -> JavascriptPluginInstance { JavascriptPluginInstance(player: nil, plugin: plugin) }
    var findings = 0
    for kind in ["timer", "http", "exec"] {
      for cancel in [false, true] {
        let instance = fresh(), js = instance.js
        let api = JavascriptAPIMpv(context: js, pluginInstance: instance)
        var nextCount = 0
        let stem = folder + "/hook-\(kind)-\(cancel)"
        let awaited: String
        switch kind {
        case "timer": awaited = "new Promise(r => setTimeout(r, 150))"
        case "http": awaited = "iina.http.get('\(url)/held', {})"
        default: awaited = "iina.utils.exec('\(root)/exec-probe', ['\(stem)-gate', '\(stem)-pid', 'normal'])"
        }
        js.evaluateScript("var entered = 0, delivered = 0; var mainThread = false; var savedNext;")
        let threadCheck: @convention(block) () -> Bool = { Thread.isMainThread }
        js.setObject(threadCheck, forKeyedSubscript: "isMainThread" as NSString)
        let callback = js.evaluateScript("(async function(next) { entered++; savedNext=next; mainThread = isMainThread(); await \(awaited); delivered++; next(); next(); })")!
        let hook = MPVHookValue(withIdentifier: "review", jsContext: js, jsBlock: callback, owner: api)
        // Same ingress as MPV_EVENT_HOOK; no other queue touches this JSContext.
        DispatchQueue.global().async { hook.call { nextCount += 1 } }
        pump(0.08)
        let entered = js.objectForKeyedSubscript("entered").toInt32()
        precondition(entered == 1)
        let onMain = js.objectForKeyedSubscript("mainThread").toBool()
        if cancel { instance.tearDown(); instance.tearDown() }
        try! Data([1]).write(to: URL(fileURLWithPath: stem + "-gate"))
        until { nextCount == 1 }
        pump(cancel ? 0.35 : 0.05)
        let delivered = js.objectForKeyedSubscript("delivered").toInt32()
        let good = nextCount == 1 && delivered == (cancel ? 0 : 1) && onMain
        print("REVIEW hook \(kind) cancel=\(cancel) main=\(onMain) next=\(nextCount) JS=\(delivered) \(good ? "PASS" : "FINDING")")
        if !good { findings += 1 }
        instance.tearDown()
        if !red {
          precondition(good)
          js.evaluateScript("savedNext()")
          precondition(nextCount == 1, "retained late next advanced twice")
        }
        withExtendedLifetime(api) {}
      }
    }
    let instance = fresh(), js = instance.js
    let ws = instance.apis["ws"] as! JavascriptAPIWebSocketController
    let disable: @convention(block) () -> Void = { instance.tearDown() }
    js.setObject(disable, forKeyedSubscript: "disableNow" as NSString)
    let port = Int(env["IINA_LIFECYCLE_WS_PORT"]!)!
    js.evaluateScript("(function(){ disableNow(); iina.ws.createServer({port:\(port)}); iina.ws.startServer(); })()")
    pump(0.08)
    let noListener = ws.server == nil
    print("REVIEW reentrant WebSocket absent=\(noListener) \(noListener ? "PASS" : "FINDING")")
    if !noListener { findings += 1 }
    // Explicit laboratory cleanup of the confirmed pre-fix leaked server.
    ws.cleanUp(instance); ws.cleanUp(instance)
    pump(0.08)
    if !red { precondition(noListener) }
    let download = fresh()
    download.js.evaluateScript("iina.http.download('\(url)/body', '\(folder)/download-control', {})")
    pump(0.4)
    download.tearDown()
    print("REVIEW \(red ? "RED" : "GREEN") findings=\(findings)")
    if red { precondition(findings == 7) }
    else {
      concurrentCallbacks(plugin: plugin)
      slowDownloads(plugin: plugin, url: url, folder: folder)
      realMpvHooks(plugin: plugin, root: root, url: url, folder: folder)
      twoPlayers(plugin: plugin)
    }
  }
  static func pump(_ seconds: Double) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
  static func until(_ check: () -> Bool) {
    let deadline = Date(timeIntervalSinceNow: 3)
    while !check() && Date() < deadline { pump(0.01) }
    precondition(check(), "bounded condition did not complete")
  }

  static func concurrentCallbacks(plugin: JavascriptPlugin) {
    for cancel in [false, true] {
      let instance = JavascriptPluginInstance(player: nil, plugin: plugin)
      let js = instance.js, api = instance.apis["utils"]!
      js.evaluateScript("var deliveries = 0")
      var registrations = 0
      let release = DispatchSemaphore(value: 0)
      let jobs = DispatchGroup()
      for _ in 0..<64 {
        jobs.enter()
        DispatchQueue.global().async {
          // Producers never enter JSC from a worker, just like mpv hook ingress.
          DispatchQueue.main.async {
            let promise = api.createPromise { token in
              DispatchQueue.global().async {
                release.wait()
                token.resolve([]); token.reject([]); token.resolve([])
                jobs.leave()
              }
            }
            let delivered = js.evaluateScript("(function(){deliveries++})")!
            promise.invokeMethod("then", withArguments: [delivered, delivered])
            registrations += 1
          }
        }
      }
      until { registrations == 64 }
      // Completions race with teardown but can only consume values on main.
      for _ in 0..<64 { release.signal() }
      if cancel { instance.tearDown() }
      until { jobs.wait(timeout: .now()) == .success }
      pump(0.05)
      let count = js.objectForKeyedSubscript("deliveries").toInt32()
      precondition(count == (cancel ? 0 : 64))
      instance.tearDown()
      var resurrected = false
      _ = api.createPromise { _ in resurrected = true }
      precondition(!resurrected)
      print("PASS concurrent createPromise/completion/teardown: 64 producers, duplicate completions, cancel=\(cancel), delivered=\(count)")
    }
    let instance = JavascriptPluginInstance(player: nil, plugin: plugin)
    let api = JavascriptAPIMpv(context: instance.js, pluginInstance: instance)
    let callback = instance.js.evaluateScript("(async function(next){await new Promise(r => setTimeout(r,100)); next()})")!
    let hook = MPVHookValue(withIdentifier: "race", jsContext: instance.js, jsBlock: callback, owner: api)
    var advances = 0
    for _ in 0..<128 {
      DispatchQueue.global().async { hook.call { advances += 1 } }
    }
    instance.tearDown()
    until { advances == 128 }
    pump(0.15)
    precondition(advances == 128)
    print("PASS 128 concurrent mpv hook ingress/teardown: every continuation released once, no JS entry")
  }

  static func slowDownloads(plugin: JavascriptPlugin, url: String, folder: String) {
    for shutdown in [false, true] {
      let player: PlayerCore? = shutdown ? PlayerCore() : nil
      if let player {
        player.label = "download-shutdown"
        HardwareDecodeCapabilities.shared.checkCapabilities()
        player.startMPV()
      }
      let instance = JavascriptPluginInstance(player: player, plugin: plugin)
      if let player { player.plugins = [instance] }
      let destination = URL(fileURLWithPath: folder + "/slow-\(shutdown)")
      if shutdown { try! Data("old-file".utf8).write(to: destination) }
      LifecycleDownloadProbe.arm()
      instance.js.evaluateScript("var downloadReplies=0; iina.http.download('\(url)/body', '\(destination.path)', {}).then(()=>downloadReplies++, ()=>downloadReplies++)")
      until { LifecycleDownloadProbe.isPaused }
      let start = Date()
      if let player { player.shutdown() } else { instance.tearDown() }
      precondition(Date().timeIntervalSince(start) < 0.2, "teardown waited for blocked body IO")
      var mainResponsive = false
      DispatchQueue.main.async { mainResponsive = true }
      pump(0.03)
      precondition(mainResponsive)
      let stagingBeforeResume = try! FileManager.default.contentsOfDirectory(atPath: plugin.tmpURL.path).filter { $0.hasPrefix(".iina-download-") }
      precondition(stagingBeforeResume.isEmpty, "teardown must unlink without waiting for writer")
      LifecycleDownloadProbe.release.signal()
      until { LifecycleDownloadProbe.finished }
      pump(0.15)
      if shutdown { precondition(try! Data(contentsOf: destination) == Data("old-file".utf8)) }
      else { precondition(!FileManager.default.fileExists(atPath: destination.path)) }
      precondition(instance.js.objectForKeyedSubscript("downloadReplies").toInt32() == 0)
      let temporary = try! FileManager.default.contentsOfDirectory(atPath: plugin.tmpURL.path).filter { $0.hasPrefix(".iina-download-") }
      precondition(temporary.isEmpty)
      print("PASS 8 MiB HTTP body paused after first 256 KiB, main responsive, \(shutdown ? "shutdown preserved existing file" : "disable left destination absent"), late replies=0, staging files=0")
    }
  }

  static func realMpvHooks(plugin: JavascriptPlugin, root: String, url: String, folder: String) {
    for kind in ["timer", "http", "exec"] {
    for cancel in [false, true] {
      let handle = mpv_create()!
      for (name, value) in [("config","no"),("vo","null"),("ao","null"),("pause","yes")] {
        precondition(mpv_set_option_string(handle, name, value) >= 0)
      }
      precondition(mpv_initialize(handle) >= 0)
      precondition(mpv_hook_add(handle, 1, "on_load", 0) >= 0)
      let instance = JavascriptPluginInstance(player: nil, plugin: plugin)
      let api = JavascriptAPIMpv(context: instance.js, pluginInstance: instance)
      let stem = folder + "/real-\(kind)-\(cancel)"
      let awaited: String
      if kind == "timer" { awaited = "new Promise(r => setTimeout(r,100))" }
      else if kind == "http" { awaited = "iina.http.get('\(url)/held', {})" }
      else { awaited = "iina.utils.exec('\(root)/exec-probe', ['\(stem)-gate', '\(stem)-pid', 'normal'])" }
      let callback = instance.js.evaluateScript("(async function(next){await \(awaited); next(); next()})")!
      let hook = MPVHookValue(withIdentifier: "native-mpv", jsContext: instance.js, jsBlock: callback, owner: api)
      precondition(mpv_command_string(handle, "loadfile \"\(root)/lifecycle-test.mp4\"") >= 0)
      var received = false, loaded = false, nextCount = 0
      let deadline = Date(timeIntervalSinceNow: 2)
      while !loaded && Date() < deadline {
        let event = mpv_wait_event(handle, 0)!.pointee
        if event.event_id == MPV_EVENT_HOOK {
          received = true
          let id = event.data.assumingMemoryBound(to: mpv_event_hook.self).pointee.id
          DispatchQueue.global().async { hook.call { nextCount += 1; precondition(mpv_hook_continue(handle, id) >= 0) } }
          pump(0.02)
          if cancel { instance.tearDown() }
          try! Data([1]).write(to: URL(fileURLWithPath: stem + "-gate"))
        } else if event.event_id == MPV_EVENT_FILE_LOADED { loaded = true }
        pump(0.01)
      }
      precondition(received && loaded && nextCount == 1)
      instance.tearDown()
      mpv_terminate_destroy(handle)
      print("PASS actual libmpv \(kind) on_load unblocked to FILE_LOADED, cancel=\(cancel), next=1, null audio/video output")
    }
  }

  }

  static func twoPlayers(plugin: JavascriptPlugin) {
    let witness = JavascriptPlugin(filename: "witness.iinaplugin")!
    JavascriptPlugin.plugins = [plugin, witness]
    witness.enabled = true
    let players = [PlayerCore(), PlayerCore()]
    PlayerCore.playerCores = players
    for (index, player) in players.enumerated() {
      player.label = "review-\(index)"
      player.startMPV(); player.loadPlugins()
    }
    let retained = players.flatMap { $0.plugins }
    let disabledOwners = players.map { player in
      player.plugins.first { $0.plugin.identifier == plugin.identifier }!
    }
    let cleanupProbes = disabledOwners.map { owner in
      let probe = LifecycleReviewCleanupProbe(context: owner.js, pluginInstance: owner)
      owner.apis["lifecycleReviewCleanup"] = probe
      owner.js.evaluateScript("var eventDeliveries=0; iina.event.on('iina.window-will-close', function(){eventDeliveries++})")
      return probe
    }
    players.forEach { $0.events.emit(.windowWillClose) }
    precondition(disabledOwners.allSatisfy {
      $0.js.objectForKeyedSubscript("eventDeliveries").toInt32() == 1
    })
    plugin.enabled = false
    precondition(players.allSatisfy { $0.plugins.count == 1 && $0.plugins[0].plugin === witness })
    precondition(retained.filter { $0.plugin === plugin }.allSatisfy { !$0.isActive })
    precondition(cleanupProbes.allSatisfy { $0.count == 1 })
    disabledOwners.forEach { $0.tearDown(); $0.tearDown() }
    players.forEach { $0.events.emit(.windowWillClose) }
    precondition(cleanupProbes.allSatisfy { $0.count == 1 })
    precondition(disabledOwners.allSatisfy {
      $0.js.objectForKeyedSubscript("eventDeliveries").toInt32() == 1
    })
    print("PASS retained instances: event delivery stopped after disable and repeated teardown cleaned exactly once")
    pump(0.2)
    precondition(players.allSatisfy { $0.plugins[0].js.objectForKeyedSubscript("lifecycleTicks").toInt32() > 0 })
    plugin.enabled = true
    precondition(players.allSatisfy { $0.plugins.count == 2 })
    let beforeReload = players.flatMap { $0.plugins }
    // Execute the same host reload operations without constructing the menu nib.
    // The actual menu action is covered separately by the bounded GUI check.
    players.forEach { $0.clearPlugins() }
    JavascriptPlugin.recreateAllPlugins()
    JavascriptPlugin.loadGlobalInstances()
    players.forEach { player in
      JavascriptPlugin.plugins.forEach { player.reloadPlugin($0, forced: true) }
    }
    precondition(beforeReload.allSatisfy { !$0.isActive })
    precondition(players.allSatisfy { $0.plugins.count == 2 && $0.plugins.allSatisfy { $0.isActive } })
    let beforeShutdown = players.flatMap { $0.plugins }
    let owners = players.map { player in player.plugins.first { $0.plugin.identifier == plugin.identifier }! }
    let identifier = plugin.identifier
    for owner in owners {
      owner.js.evaluateScript("var hookEntries=0, hookCompletions=0; iina.mpv.addHook('on_load',0,async function(next){hookEntries++; await new Promise(r=>setTimeout(r,200)); hookCompletions++; next()})")
    }
    var firstNext = 0, secondNext = 0
    DispatchQueue.global().async { players[0].mpv.lifecycleInvokeHook(identifier) { firstNext += 1 } }
    DispatchQueue.global().async { players[1].mpv.lifecycleInvokeHook(identifier) { secondNext += 1 } }
    until { owners.allSatisfy { $0.js.objectForKeyedSubscript("hookEntries").toInt32() == 1 } }
    let survivorTicks = owners[1].js.objectForKeyedSubscript("lifecycleTicks").toInt32()
    players[0].shutdown(); players[0].shutdown()
    precondition(!owners[0].isActive && owners[1].isActive)
    precondition(firstNext == 1 && secondNext == 0)
    precondition(players[0].mpv.lifecycleHookCount(identifier) == 0)
    precondition(players[1].mpv.lifecycleHookCount(identifier) == 1)
    until { secondNext == 1 }
    precondition(owners[0].js.objectForKeyedSubscript("hookCompletions").toInt32() == 0)
    precondition(owners[1].js.objectForKeyedSubscript("hookCompletions").toInt32() == 1)
    precondition(owners[1].js.objectForKeyedSubscript("lifecycleTicks").toInt32() > survivorTicks)
    precondition(players[1].plugins.allSatisfy { $0.isActive })
    print("PASS isolated PlayerCore shutdown: first hook released without JS, second registered hook completed normally, survivor instance and timers remained active")
    players[1].shutdown(); players[1].shutdown()
    precondition(firstNext == 1 && secondNext == 1)
    precondition(beforeShutdown.allSatisfy { !$0.isActive })
    pump(0.25)
    precondition(players.allSatisfy { $0.plugins.isEmpty })
    PlayerCore.playerCores = []
    JavascriptPlugin.plugins.forEach { $0.enabled = false }
    plugin.enabled = false; witness.enabled = false
    print("PASS two real PlayerCore instances: disable/survivor/re-enable/Reload All Plugins/repeated shutdown")
  }
}

private final class LifecycleReviewCleanupProbe: JavascriptAPI {
  var count = 0

  override func cleanUp(_ instance: JavascriptPluginInstance) {
    count += 1
  }
}

// Deterministic observation seam injected only into the laboratory HTTP writer.
// The semaphore deliberately blocks body IO while main performs teardown.
enum LifecycleDownloadProbe {
  private static let lock = NSLock()
  private static var armed = false, paused = false, done = false
  static let release = DispatchSemaphore(value: 0)
  static var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }
  static var finished: Bool { lock.lock(); defer { lock.unlock() }; return done }
  static func arm() { lock.lock(); armed = true; paused = false; done = false; lock.unlock() }
  static func afterChunk() {
    lock.lock()
    let wait = armed
    if wait { armed = false; paused = true }
    lock.unlock()
    if wait {
      precondition(!Thread.isMainThread)
      precondition(release.wait(timeout: .now() + 3) == .success)
      lock.lock(); done = true; lock.unlock()
    }
  }
}
