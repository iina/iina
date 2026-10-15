import Cocoa
import JavaScriptCore

// Runs through the real HTTP API, session, Promise tokens and writer.
enum LifecycleFileReviewTests {
  static func run(plugin: JavascriptPlugin, mode: String) {
    let env = ProcessInfo.processInfo.environment
    let base = env["IINA_LIFECYCLE_HTTP_URL"]!
    let folder = URL(fileURLWithPath: env["IINA_LIFECYCLE_REVIEW_RUN"]!)
    let instance = plugin.globalInstance!
    let js = instance.js
    let staging = plugin.tmpURL
    func staged() -> Set<String> {
      Set((try! FileManager.default.contentsOfDirectory(atPath: staging.path)).filter { $0.hasPrefix(".iina-download-") })
    }
    let originalStaging = staged()
    func request(_ suffix: String, to destination: URL) {
      js.evaluateScript("var successes=0, failures=0, successType='', failure=null; iina.http.download('\(base)/\(suffix)', '\(destination.path)', {}).then(function(value){successes++; successType=typeof value},function(error){failures++; failure=error})")
    }
    func settled() {
      LifecycleReviewTests.until { js.objectForKeyedSubscript("successes").toInt32() + js.objectForKeyedSubscript("failures").toInt32() > 0 }
    }
    func success() {
      settled()
      precondition(js.objectForKeyedSubscript("successes").toInt32() == 1)
      precondition(js.objectForKeyedSubscript("failures").toInt32() == 0)
      precondition(js.objectForKeyedSubscript("successType").toString() == "undefined")
      precondition(staged() == originalStaging)
    }
    func metadata(_ url: URL) -> stat {
      var result = stat()
      precondition(lstat(url.path, &result) == 0)
      return result
    }
    if mode == "file-exit" {
      let destination = folder.appendingPathComponent("cancelled-target")
      LifecycleDownloadProbe.arm()
      request("body", to: destination)
      LifecycleReviewTests.until { LifecycleDownloadProbe.isPaused }
      let names = staged().subtracting(originalStaging)
      precondition(names.count == 1, "writer must actually own a staging file before teardown")
      let paths = names.map { staging.appendingPathComponent($0).path }
      let record: [String: Any] = ["stagingPaths": paths, "target": destination.path, "writerPaused": true]
      try! JSONSerialization.data(withJSONObject: record).write(to: folder.appendingPathComponent("exit-check.json"))
      // This is the real global-plugin disable/teardown path. Do NOT release the
      // semaphore, pump the run loop or wait for the writer before normal exit.
      plugin.enabled = false
      precondition(!LifecycleDownloadProbe.finished)
      print("FILE EXIT: teardown returned while writer remains paused; normal exit(0)")
      exit(0)
    }

    let existing = folder.appendingPathComponent("existing")
    try! Data("old".utf8).write(to: existing)
    precondition(chmod(existing.path, 0o755) == 0)
    let inode = metadata(existing).st_ino
    let hard = folder.appendingPathComponent("hard-link")
    precondition(link(existing.path, hard.path) == 0)
    request("held", to: existing); success()
    precondition(metadata(existing).st_mode & 0o7777 == 0o755 && metadata(existing).st_ino == inode)
    let body = Data(repeating: 120, count: 20)
    precondition(try! Data(contentsOf: existing) == body)
    precondition(try! Data(contentsOf: hard) == body)
    print("PASS file 0755 and inode/hard-link semantics, exact body, success(undefined)=1/error=0")

    let target = folder.appendingPathComponent("symlink-target")
    try! Data("original target".utf8).write(to: target)
    precondition(chmod(target.path, 0o754) == 0)
    let sym = folder.appendingPathComponent("symlink")
    precondition(symlink("symlink-target", sym.path) == 0)
    let symlinkInode = metadata(sym).st_ino, targetInode = metadata(target).st_ino
    request("held", to: sym); success()
    precondition(metadata(sym).st_mode & S_IFMT == S_IFLNK && metadata(sym).st_ino == symlinkInode)
    precondition(try! FileManager.default.destinationOfSymbolicLink(atPath: sym.path) == "symlink-target")
    precondition(metadata(target).st_ino == targetInode && metadata(target).st_mode & 0o7777 == 0o754)
    precondition(try! Data(contentsOf: target) == body)
    print("PASS relative destination symlink preserved; target inode/mode/body preserved or updated correctly")

    let control = folder.appendingPathComponent("data-write-control")
    try! body.write(to: control)
    let new = folder.appendingPathComponent("new-file")
    request("held", to: new); success()
    precondition(metadata(new).st_mode & 0o7777 == metadata(control).st_mode & 0o7777)
    precondition(try! Data(contentsOf: new) == body)
    print("PASS new-file mode matches native Data.write under the same umask; exact body and successful result")

    let dangling = folder.appendingPathComponent("dangling-link")
    precondition(symlink("new-target", dangling.path) == 0)
    request("held", to: dangling); success()
    precondition(metadata(dangling).st_mode & S_IFMT == S_IFLNK)
    precondition(try! Data(contentsOf: folder.appendingPathComponent("new-target")) == body)
    print("PASS dangling destination symlink preserved; target created")

    let directory = folder.appendingPathComponent("no-directory-write")
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let inside = directory.appendingPathComponent("writable-file")
    try! Data("old".utf8).write(to: inside)
    precondition(chmod(directory.path, 0o555) == 0)
    request("held", to: inside); success()
    precondition(try! Data(contentsOf: inside) == body)
    precondition(chmod(directory.path, 0o755) == 0)
    print("PASS existing writable file in a non-writable directory (staging uses private plugin temp)")

    // Filesystem failure must reject, without being mistaken for success.
    let invalid = folder.appendingPathComponent("absent-parent/file")
    request("held", to: invalid); settled()
    precondition(js.objectForKeyedSubscript("successes").toInt32() == 0 && js.objectForKeyedSubscript("failures").toInt32() == 1)
    precondition(js.objectForKeyedSubscript("failure").toString() == "Unable to write to the destination.")
    precondition(!FileManager.default.fileExists(atPath: invalid.path))
    precondition(staged() == originalStaging)
    print("PASS filesystem failure: success=0/error=1, exact error, target absent, staging removed")

    // HTTP failure must preserve the server result and leave the old target intact.
    request("error", to: existing); settled()
    precondition(js.objectForKeyedSubscript("successes").toInt32() == 0 && js.objectForKeyedSubscript("failures").toInt32() == 1)
    precondition(js.evaluateScript("failure.statusCode === 503 && failure.text === '{\"error\":\"download-failed\"}' && failure.data.error === 'download-failed'")!.toBool())
    precondition(try! Data(contentsOf: existing) == body)
    precondition(metadata(existing).st_mode & 0o7777 == 0o755)
    precondition(staged() == originalStaging)
    print("PASS HTTP error: success=0/error=1, exact status/text/JSON, existing target untouched")
    // Data.write is in-place, not an atomic replacement. If cancellation starts
    // after publication, already written bytes remain but cannot change later.
    let partial = folder.appendingPathComponent("partial-publication")
    LifecyclePublicationProbe.armed = true
    request("body", to: partial)
    LifecycleReviewTests.until { LifecyclePublicationProbe.isPaused }
    let beforeCancel = try! Data(contentsOf: partial)
    precondition(beforeCancel.count == 256 * 1024 && beforeCancel.allSatisfy { $0 == 120 })
    plugin.enabled = false
    precondition(staged() == originalStaging)
    LifecyclePublicationProbe.release.signal()
    LifecycleReviewTests.until { LifecyclePublicationProbe.finished }
    LifecycleReviewTests.pump(0.05)
    precondition(try! Data(contentsOf: partial) == beforeCancel)
    precondition(js.objectForKeyedSubscript("successes").toInt32() == 0 && js.objectForKeyedSubscript("failures").toInt32() == 0)
    print("PASS cancel during in-place publication: pre-cancel bytes retained, zero later mutation or JS settlement, staging immediately absent")
  }
}

// Observation seam only; production has no semaphore or test-specific branch.
enum LifecyclePublicationProbe {
  private static let lock = NSLock()
  private static var enabled = false, paused = false, done = false
  static let release = DispatchSemaphore(value: 0)
  static var armed: Bool {
    get { lock.lock(); defer { lock.unlock() }; return enabled }
    set { lock.lock(); enabled = newValue; lock.unlock() }
  }
  static var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }
  static var finished: Bool { lock.lock(); defer { lock.unlock() }; return done }
  static func afterBlock() {
    lock.lock()
    let wait = enabled
    if wait { enabled = false; paused = true }
    lock.unlock()
    if wait {
      precondition(!Thread.isMainThread)
      precondition(release.wait(timeout: .now()+3) == .success)
      lock.lock(); done = true; lock.unlock()
    }
  }
}
