//
//  SidebarView.swift
//  iina
//
//  Created by Hechen Li on 2026-05-27.
//  Copyright © 2026 lhc. All rights reserved.
//

class SideBarView: TranslucentView {
  weak var mainWindow: MainWindowController!

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow

    super.init(liquidGlassCornerRadius: 12, vevCornerRadius: 0, padding: (0, 0))
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
