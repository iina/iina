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
      Just.get(url) { respond in
        guard let data = respond.content, let image = NSImage(data: data) else { return }
        DispatchQueue.main.async {
          self.imageView!.image = image.rounded()
        }
      }
    }
  }
}
