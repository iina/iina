//
//  SidebarView.swift
//  iina
//
//  Created by Hechen Li on 2026-05-27.
//  Copyright © 2026 lhc. All rights reserved.
//

class SideBarView: TranslucentView {
  weak var mainWindow: MainWindowController!
  private let prefObserver = Preference.Observer()
  var leadingBorder: NSBox!

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow

    super.init(liquidGlassCornerRadius: 12, vevCornerRadius: 0, padding: (0, 0))

    LayoutValue.panelCornerRadius.use { [weak self] value in
      self?.setCornerRadius(liquidGlass: value, vev: 0)
    }

    // only draw leading border when docked
    prefObserver.addAll(.dockedControlBarAndTitlebar, .edgeToEdgeVideo) { [unowned self] _ in
      leadingBorder?.isHidden = !Preference.isDocked
    }
  }

  override func setStyle(_ newStyle: TranslucentView.Style, force: Bool = false) {
    super.setStyle(newStyle, force: force)

    if let container = container as? NSVisualEffectView {
      leadingBorder = NSBox()
      leadingBorder.translatesAutoresizingMaskIntoConstraints = false
      leadingBorder.boxType = .separator
      container.addSubview(leadingBorder)
      leadingBorder.padding(.vertical, .leading).size(width: 1)
      leadingBorder.isHidden = !Preference.isDocked
    }
  }

  @MainActor required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
