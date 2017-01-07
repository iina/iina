# Contributing

Thank you for being interested in IINA.

First of all, please be tolerate. I'm not a professional in Cocoa development or Swift, so my code, especially early parts may contain stupid logic or design flaw (a refactor is in my plan).

If you believe the code structures can be improved, please raise an issue.

## Issues

- Please use English for both the title and the details. 请在标题和正文都使用英文。
- Before opening an issue, please check whether there already exists a similar one.

## Some Guidelines

- IINA is for modern macOS.
  - Stay consistent with the design language of macOS.
  - Stay consistent with behaviors of macOS original Applications.
- User interface and user experiences are important.
  - Use animations for UI items, if possible.
  - Use proper font weight, size and color.
  - Leave margins everywhere.
- IINA is based on mpv.
  - Avoid adding features (especially decoding/playback related) that mpv does not provide.
  - Lua script is also a possible solution for some features.
- Give users more choices.

**Technical tips**

- Use xib for UI if possible, such as positioning of UI elements, whether a view uses layer, cocoa binding, etc.
- Add proper comments.
- Use 2 spaces for tabs.
- For code style, currently there's not a fixed guideline. Maybe later?

**Current structure**

- Only `VideoView` and `MPVController` may call mpv API directly.
- `PlayerCore` encapsulates general playback functions.
  - Setting options/properties directly through `MPVController` is discouraged.
  - `PlayerCore` should only contain logic that controls playback.
- Window related logic should be in `MainWindowController`.
  - `windowDidLoad()`: stuff that should be done once
  - `windowDidOpen()`: stuff that should be done every time when window shown, like resetting some UI components
  - `windowWillClose()`: release / deinitialize 

## How to Contribute

1. Fork and clone the repo
2. Follow [the guide to build with pre-compiled dylibs in README.md](README.md#use-pre-compiled-dylibs)
3. Open `iina.xcworkspace`.
4. Commit changes, test, push, and submit a pull request.

If you want to build libmpv and other depended dylibs on your own, please refer to [the guide in README.md](README.md#build-with-the-lastest-mpv).

**Tips**

- Please set target branch of your pull request to `develop`.
- If you found `develop` has been updated during your change, remember to do a rebase before opening pull request.
