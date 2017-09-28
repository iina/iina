//
//  CacheManager.swift
//  iina
//
//  Created by lhc on 28/9/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class CacheManager {

  static var shared = CacheManager()

  var isJobRunning = false
  var needsRefresh = true

  private var cachedContents: [URL]?

  private func cacheFolderContents() -> [URL]? {
    if needsRefresh {
      cachedContents = try? FileManager.default.contentsOfDirectory(at: Utility.thumbnailCacheURL,
                                                                    includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey],
                                                                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
    }
    return cachedContents
  }

  func getCacheSize() -> Int {
    return cacheFolderContents()?.reduce(0 as Int) { totalSize, url in
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
      return totalSize + size
    } ?? 0
  }

  func clearOldCache() {
    guard !isJobRunning else { return }
    isJobRunning = true

    let maxCacheSize = Preference.integer(for: .maxThumbnailPreviewCacheSize)
    // if full, delete 50% of max cache
    let cacheToDelete = maxCacheSize * FileSize.Unit.mb.rawValue / 2

    // sort by access date
    guard let contents = cacheFolderContents()?.sorted(by: { url1, url2 in
      let date1 = (try? url1.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? Date.distantPast
      let date2 = (try? url2.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? Date.distantPast
      return date1!.compare(date2!) == .orderedAscending
    }) else { return }

    // delete old cache
    var clearedCacheSize = 0
    for url in contents {
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
      if clearedCacheSize < cacheToDelete {
        try? FileManager.default.removeItem(at: url)
        clearedCacheSize += size
      } else {
        break
      }
    }
  }

}
