import Foundation
class Window { var isFullscreenTransitionInProgress = false }
class Player {
  let mainWindow = Window()
  var isRefreshingPausedCrop = false
  var polls = 0
  func pollTime() {
    // PRODUCTION_TIME_GUARD
    polls += 1
  }
}
let player = Player()
player.mainWindow.isFullscreenTransitionInProgress = true
player.pollTime()
precondition(player.polls == 0, "fullscreen animation must defer synchronous engine polling")
player.mainWindow.isFullscreenTransitionInProgress = false
player.pollTime()
precondition(player.polls == 1, "normal time polling resumes after fullscreen")
player.isRefreshingPausedCrop = true
player.pollTime()
precondition(player.polls == 1, "paused crop refresh keeps its existing deferral")
print("Passed 3 fullscreen time-poll checks")
