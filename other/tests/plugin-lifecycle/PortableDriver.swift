import Cocoa
import JavaScriptCore

// Entry point for the generated test build. This file is never added to IINA.
@main
struct PluginLifecyclePortableDriver {
  static func main() {
    let environment = ProcessInfo.processInfo.environment
    guard let root = environment["IINA_LIFECYCLE_TEST_ROOT"],
          Bundle.main.bundleIdentifier == "org.iina.lifecycle-tests",
          NSHomeDirectory() == root + "/home",
          Utility.pluginsURL.path.hasPrefix(root + "/home/"),
          Utility.cacheURL.path.hasPrefix(root + "/home/"),
          Utility.tempDirURL.path == root + "/tmp" else {
      fatalError("Plugin lifecycle test isolation failed")
    }
    guard CommandLine.arguments.count == 2 else { exit(64) }

    setbuf(stdout, nil)
    _ = NSApplication.shared
    let delegate = AppDelegate()
    NSApp.delegate = delegate
    for (key, value) in Preference.defaultPreference {
      UserDefaults.standard.register(defaults: [key.rawValue: value])
    }
    UserDefaults.standard.set(false, forKey: "useMediaKeys")
    UserDefaults.standard.set(false, forKey: "recordRecentFiles")
    UserDefaults.standard.set(false, forKey: "SUEnableAutomaticChecks")
    UserDefaults.standard.set(false, forKey: "SUAutomaticallyUpdate")
    URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)

    guard let plugin = JavascriptPlugin(filename: "lifecycle.iinaplugin") else {
      fatalError("Cannot load lifecycle test fixture")
    }
    plugin.enabled = true

    switch CommandLine.arguments[1] {
    case "lifecycle":
      LifecycleReviewTests.run(plugin: plugin, root: root, red: false)
      plugin.enabled = false
    case "files", "file-exit":
      LifecycleFileReviewTests.run(plugin: plugin, mode: CommandLine.arguments[1] == "files" ? "file-semantics" : "file-exit")
      plugin.enabled = false
    default:
      exit(64)
    }
    withExtendedLifetime(delegate) {}
  }
}
