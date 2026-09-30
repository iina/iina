//
//  KeyBindingDefaultConfigs.swift
//  iina
//

import Foundation

enum KeyBindingDefaultConfigs {
  /// Builds `[displayName: absolutePath]` from a config map and path resolver.
  /// Skips missing resources instead of force-unwrapping bundle paths.
  static func resolve(
    configMap: KeyValuePairs<String, String>,
    pathForResource: (String) -> String?,
    onMissing: ((String, String) -> Void)? = nil
  ) -> [String: String] {
    var configs: [String: String] = [:]
    for (name, resource) in configMap {
      if let path = pathForResource(resource) {
        configs[name] = path
      } else {
        onMissing?(name, resource)
      }
    }
    return configs
  }
}
