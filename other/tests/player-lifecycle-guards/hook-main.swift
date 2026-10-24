import Foundation
import JavaScriptCore

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message); checks += 1
}
let owner = JavascriptAPIMpv()
func javascriptHook(_ source: String) -> (JSContext, MPVHookValue) {
  let context = JSContext()!
  let callback = context.evaluateScript(source)!
  return (context, MPVHookValue(withIdentifier: "test", jsContext: context, jsBlock: callback, owner: owner))
}
do {
  let (context, hook) = javascriptHook("(function(next) { savedNext = next; next(); })")
  var calls = 0
  hook.call { calls += 1 }
  check(calls == 1, "synchronous JS next plus automatic continuation calls once")
  context.evaluateScript("savedNext(); savedNext()")
  check(calls == 1, "retained synchronous JS continuation cannot run again")
}
do {
  let (context, hook) = javascriptHook("(function(next) { savedNext = next; })")
  var calls = 0
  hook.call { calls += 1; context.evaluateScript("savedNext()") }
  check(calls == 1, "automatic continuation remains reentrant without holding its lock")
}
do {
  let (context, hook) = javascriptHook("(async function(next) { savedNext = next; })")
  var calls = 0
  hook.call { calls += 1 }
  check(calls == 0, "async JS hook waits for its explicit continuation")
  context.evaluateScript("savedNext(); savedNext()")
  check(calls == 1, "async JS continuation calls once")
}
do {
  var calls = 0
  let hook = MPVHookValue(withBlock: { next in next(); next() })
  hook.call { calls += 1 }
  check(calls == 1, "native synchronous duplicate calls once")
}
do {
  let lock = NSLock()
  var calls = 0
  var retained: (() -> Void)?
  let hook = MPVHookValue(withBlock: { retained = $0 })
  hook.call { lock.lock(); calls += 1; lock.unlock() }
  check(calls == 0, "native asynchronous hook retains pending continuation")
  DispatchQueue.concurrentPerform(iterations: 32) { _ in retained?() }
  check(calls == 1, "parallel native duplicate continuations call once")
}
func deliver(_ controller: HookController, userdata: UInt64 = 1) {
  let event = nativeTestCreateHook(userdata, 17)!
  controller.handle(UnsafePointer(event))
  nativeTestDestroyHook(event)
}
do {
  let controller = HookController()
  controller.hooks[1] = MPVHookValue(withBlock: { next in next(); next() })
  nativeTestReset()
  deliver(controller)
  check(nativeTestCalls() == 1, "actual event continuation reaches C once")
}
do {
  let controller = HookController()
  var retained: (() -> Void)?
  controller.hooks[1] = MPVHookValue(withBlock: { retained = $0 })
  nativeTestReset()
  deliver(controller)
  controller.mpv = nil
  retained?(); retained?()
  check(nativeTestCalls() == 0, "late event continuation after handle removal makes no C calls")
}
do {
  var controller: HookController? = HookController()
  let released = WeakHookController(controller)
  var retained: (() -> Void)?
  controller!.hooks[1] = MPVHookValue(withBlock: { retained = $0 })
  nativeTestReset()
  deliver(controller!)
  controller = nil
  check(released.value == nil, "retained hook continuation does not retain the controller")
  retained?()
  check(nativeTestCalls() == 0, "continuation after controller release makes no C calls")
}
do {
  let controller = HookController()
  nativeTestReset()
  deliver(controller, userdata: 99)
  check(nativeTestCalls() == 1, "unloaded plugin hook still releases native load")
  controller.mpv = nil
  deliver(controller, userdata: 99)
  check(nativeTestCalls() == 1, "missing hook on absent handle makes no additional C call")
}
print("\(checks) hook checks passed with actual JavaScriptCore, native concurrency and C null-handle traps")
