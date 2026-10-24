import Foundation
import JavaScriptCore

// PRODUCTION_HELPERS

enum Permission { case accessFileSystem }
enum Utility {
  static let binariesURL = URL(fileURLWithPath: NSTemporaryDirectory())
  static let exeDirURL = URL(fileURLWithPath: NSTemporaryDirectory())
}
enum Logger { static func log(_ value: String, subsystem: String) {} }
class Plugin {
  let dataURL = Utility.binariesURL
  let tmpURL = Utility.binariesURL
}
class Instance {
  let plugin = Plugin()
  let subsystem = "process-test"
  let queue = DispatchQueue(label: "process-test-wait")
}
class Fixture: NSObject {
  let context = JSContext()!
  let pluginInstance = Instance()
  func permitted(to: Permission) -> Bool { true }
  func throwError(withMessage: String) { fatalError(withMessage) }
  func parsePath(_ value: String) -> (path: String?, local: Bool) { (value, false) }
  func createPromise(_ block: @escaping @convention(block) (JSValue, JSValue) -> Void) -> JSValue {
    context.objectForKeyedSubscript("Promise")!.construct(withArguments: [JSValue(object: block, in: context)!])
  }
// PRODUCTION_EXEC
}

final class Result {
  let lock = NSLock()
  var output = "", errorOutput = ""
  var hooksOnMain = true, completionOnMain = false
  var hooks = 0, completions = 0
  var value: Any?
  var resolved = false
  func record(_ text: String, stderr: Bool) {
    lock.lock(); defer { lock.unlock() }
    hooksOnMain = hooksOnMain && Thread.isMainThread
    hooks += 1
    if stderr { errorOutput += text } else { output += text }
  }
  func finish(_ value: JSValue, resolved: Bool) {
    lock.lock(); defer { lock.unlock() }
    completionOnMain = Thread.isMainThread
    completions += 1
    self.value = value.toObject()
    self.resolved = resolved
  }
  var done: Bool {
    lock.lock(); defer { lock.unlock() }
    return completions > 0
  }
}
var checks = 0
func check(_ value: Bool, _ message: String) {
  if !value { print("FAILED: " + message); exit(1) }; checks += 1
}
func execute(_ fixture: Fixture, file: String = "/bin/sh", args: [String], hooks: Bool = true) -> Result {
  let result = Result()
  let stdout: @convention(block) (String) -> Void = { result.record($0, stderr: false) }
  let stderr: @convention(block) (String) -> Void = { result.record($0, stderr: true) }
  let success: @convention(block) (JSValue) -> Void = { result.finish($0, resolved: true) }
  let failure: @convention(block) (JSValue) -> Void = { result.finish($0, resolved: false) }
  let promise = fixture.exec(file, args, nil,
                            hooks ? JSValue(object: stdout, in: fixture.context) : nil,
                            hooks ? JSValue(object: stderr, in: fixture.context) : nil)!
  promise.invokeMethod("then", withArguments: [success, failure])
  let deadline = Date().addingTimeInterval(10)
  while !result.done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
  check(result.done, "process promise completes without blocking main")
  check(result.completions == 1, "process promise settles once")
  check(result.completionOnMain, "promise continuation runs on main")
  check(result.hooksOnMain, "stdout and stderr callbacks cannot enter JavaScript off main")
  return result
}
let fixture = Fixture()
let system = execute(fixture, file: "printf", args: ["%s", "space 'quote' $literal; & tail"])
check(system.resolved && (system.value as? [String: Any])?["status"] as? Int == 0,
      "unqualified system executable resolves without an empty launch path")
check((system.value as? [String: Any])?["stdout"] as? String == "space 'quote' $literal; & tail",
      "system command arguments remain literal without a shell")
let small = execute(fixture, args: ["-c", "printf 'out-tail'; printf 'err-tail' >&2; exit 7"])
let smallValue = small.value as! [String: Any]
check(small.resolved && smallValue["status"] as? Int == 7, "nonzero exit remains a resolved process result")
check(smallValue["stdout"] as? String == "out-tail" && smallValue["stderr"] as? String == "err-tail",
      "both final output tails are captured")
check(small.output == "out-tail" && small.errorOutput == "err-tail" && small.hooks >= 2,
      "stream callbacks arrive before promise completion")

let count = 15000
let large = execute(fixture, args: ["-c", "i=0; while [ $i -lt 15000 ]; do printf 'O%05d\\n' $i; printf 'E%05d\\n' $i >&2; i=$((i+1)); done"])
let largeValue = large.value as! [String: Any]
let expectedOut = (0..<count).map { String(format: "O%05d\n", $0) }.joined()
let expectedErr = (0..<count).map { String(format: "E%05d\n", $0) }.joined()
check(largeValue["stdout"] as? String == expectedOut, "stdout larger than a pipe buffer drains fully")
check(largeValue["stderr"] as? String == expectedErr, "stderr larger than a pipe buffer drains fully")
check(large.output == expectedOut && large.errorOutput == expectedErr,
      "interleaved streams retain their own ordering and finish before settlement")

let unicode = execute(fixture, args: ["-c", "printf '\\342'; printf '\\202\\254-tail'"], hooks: false)
check((unicode.value as! [String: Any])["stdout"] as? String == "€-tail", "collected UTF-8 survives split writes")
for _ in 0..<3 {
  let empty = execute(fixture, args: ["-c", "exit 0"])
  let value = empty.value as! [String: Any]
  check(value["stdout"] as? String == "" && value["stderr"] as? String == "", "empty streams reach EOF")
}
let missing = execute(fixture, file: "/nonexistent/iina-process-test", args: [])
check(!missing.resolved && missing.value as? Int == -1, "missing binary retains rejection semantics")
for _ in 0..<3 {
  let failure = execute(fixture, file: "/dev/null", args: [])
  check(!failure.resolved, "spawn failure cancels unread pipes and rejects")
}
print("Passed \(checks) plugin process stream and callback checks")
