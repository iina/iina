import Cocoa
import Darwin

// Inert compile dependencies. The probe never calls presenter/session methods,
// creates NSApplication, or instantiates these window classes.
final class SettingsWindow: NSWindow {
  static let `default` = SettingsWindow()
  func saveNavigationLocation() {}
}

enum AppRestartSession {
  static let preferenceKey = "unusedEnvironmentProbeSession"
  static func capture(defaults: UserDefaults) {}
}

enum AccentControls {
  static func styleDefaultButton(in alert: NSAlert) {}
}

struct Configuration: Decodable {
  let token: String
  let output: String
  let pathPrefix: String
  let launchPath: String
  let launchProxy: String?
}

// This must remain the first executed operation, matching the application entry.
// The actual production helper does not return: it waits for the parent, invokes
// /usr/bin/open, then exits. No production source is copied or patched.
if AppRestart.runHelperIfRequested() { exit(EXIT_SUCCESS) }

let configurationURL = Bundle.main.resourceURL!.appendingPathComponent("probe.json")
let configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configurationURL))
let output = URL(fileURLWithPath: configuration.output, isDirectory: true)
let markerKey = "IINA_RESTART_ENVIRONMENT_PARENT"
let proxyMarker = "http://127.0.0.1:9"

func environmentValue(_ name: String) -> String? {
  getenv(name).map { String(cString: $0) }
}

func record(_ stage: String, extra: [String: Any] = [:]) throws {
  // Only booleans for these selected synthetic markers are recorded. Never
  // serialize ProcessInfo.environment, PATH, proxy, or other environment data.
  var event: [String: Any] = [
    "stage": stage,
    "pid": getpid(),
    "parentPID": getppid(),
    "pathMarkerPresent": environmentValue("PATH")?.split(separator: ":")
      .contains(Substring(configuration.pathPrefix)) == true,
    "proxyMarkerPresent": environmentValue("http_proxy") == proxyMarker,
    "parentStageMarkerPresent": environmentValue(markerKey) == configuration.token,
    "pathMatchesLaunchBaseline": environmentValue("PATH") == configuration.launchPath,
    "proxyMatchesLaunchBaseline": environmentValue("http_proxy") == configuration.launchProxy,
  ]
  extra.forEach { event[$0] = $1 }
  var data = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
  data.append(0x0A)
  let descriptor = open(output.appendingPathComponent("events.jsonl").path,
                        O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR)
  guard descriptor >= 0 else { throw POSIXError(.EIO) }
  defer { close(descriptor) }
  try data.withUnsafeBytes { bytes in
    guard write(descriptor, bytes.baseAddress, bytes.count) == bytes.count else {
      throw POSIXError(.EIO)
    }
  }
}

if CommandLine.arguments.dropFirst() == ["--environment-witness"] {
  // Verify Foundation Process's default inheritance after runtime setenv, using
  // the same executable and launch mechanism as the actual helper invocation.
  try record("inherited-child-witness")
  exit(EXIT_SUCCESS)
}

let oneShotURL = output.appendingPathComponent("parent-started.once")
let firstStageMarker = environmentValue(markerKey) == configuration.token
let oneShotDescriptor = firstStageMarker
  ? open(oneShotURL.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR) : -1

if oneShotDescriptor >= 0 {
  close(oneShotDescriptor)
  try record("parent-before-mutation")
  setenv("PATH", configuration.pathPrefix + ":" + (environmentValue("PATH") ?? "/usr/bin:/bin"), 1)
  setenv("http_proxy", proxyMarker, 1)
  try record("parent-after-mutation")

  let witness = Process()
  witness.executableURL = Bundle.main.executableURL!
  witness.arguments = ["--environment-witness"]
  try witness.run()
  witness.waitUntilExit()
  guard witness.terminationStatus == 0 else {
    try record("witness-failed", extra: ["status": witness.terminationStatus])
    exit(EXIT_FAILURE)
  }

  // Exercise the same production environment/executable/argument configuration
  // used by restart(restoring:), without its window/session/NSApp termination.
  let helper = try AppRestart.startRelaunchHelper()
  try record("parent-spawned-actual-helper", extra: ["helperPID": helper.processIdentifier])
  // Normal parent exit lets the unchanged process-exit source trigger relaunch.
  exit(EXIT_SUCCESS)
}

guard FileManager.default.fileExists(atPath: oneShotURL.path) else {
  try record("unexpected-launch-without-parent")
  exit(EXIT_FAILURE)
}

// A surviving parent marker still enters this branch because the exclusive
// one-shot file already exists. This bounds failure to one relaunch.
try record("launch-services-relaunch")
let markerSurvived =
  environmentValue("PATH")?.split(separator: ":").contains(Substring(configuration.pathPrefix)) == true ||
  environmentValue("http_proxy") == proxyMarker
let baselinePreserved = environmentValue("PATH") == configuration.launchPath &&
  environmentValue("http_proxy") == configuration.launchProxy && firstStageMarker
exit(markerSurvived || !baselinePreserved ? EXIT_FAILURE : EXIT_SUCCESS)
