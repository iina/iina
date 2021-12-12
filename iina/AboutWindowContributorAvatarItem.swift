//
//  AboutWindowContributorAvatarItem.swift
//  iina
//
//  Created by Collider LI on 4/11/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa
import Just

class AboutWindowContributorAvatarItem: NSCollectionViewItem {

  static let imageCache = NSCache<NSString, NSImage>()

  override func viewDidLoad() {
    guard let imageView = imageView else { return }
    imageView.wantsLayer = true
    imageView.layer?.shadowColor = NSColor.controlBackgroundColor.cgColor
    imageView.layer?.shadowOffset = CGSize(width: 0, height: 1)
    imageView.layer?.shadowRadius = 2
  }

  override func viewDidLayout() {
    guard let imageView = imageView else { return }
    imageView.layer?.cornerRadius = imageView.frame.width / 2
  }

  var avatarURL: String? {
    didSet {
      guard let url = avatarURL else { return }
      if let data = AboutWindowContributorAvatarItem.imageCache.object(forKey: url as NSString) {
        self.imageView!.image = data
      } else {
        Just.get(url, asyncCompletionHandler: { respond in
          guard let data = respond.content, var image = NSImage(data: data) else { return }
          image = image.rounded()
          DispatchQueue.main.async {
            self.imageView!.image = image
          }
          AboutWindowContributorAvatarItem.imageCache.setObject(image, forKey: url as NSString)
        })
      }
    }
  }
}
