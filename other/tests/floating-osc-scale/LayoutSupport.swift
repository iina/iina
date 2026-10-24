// These collaborators stay inactive so the production resize-end callback must
// settle native UI before its guard, without making any MPV calls.
final class LayoutPlayerStub {
  struct State { let active = false }
  struct Info { let state = State() }
  let info = Info()
}
final class LayoutLiveTextStub { func requestAnalysis() {}
 func clearAnalysis() {} }
struct LayoutInteractiveMode { var isActive = false }
final class LayoutVideoViewStub {
  final class Layer { var inLiveResize = false }
  let videoLayer = Layer()
}
