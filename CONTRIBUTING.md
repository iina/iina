# Contributing

Thank you for being interested in IINA.

First of all, please be tolerant. I'm not a professional in Cocoa development or Swift, so my code, especially early parts may contain stupid logic or design flaws (a refactor is in my plans).

If you believe the code structures can be improved, please raise an issue.

## Issues

- Please use English for both the title and the details. 请在标题和正文都使用英文。
- Before opening an issue, please check whether a similar one already exists.

## Some Guidelines

- IINA is for modern macOS.
  - Stay consistent with the design language of macOS.
  - Stay consistent with behaviors of macOS original Applications.
- User interface and user experience is important.
  - Use animations for UI items, if possible.
  - Use proper font weight, size and color.
  - Leave margins everywhere.
- IINA is based on mpv.
  - Avoid adding features (especially decoding/playback related) that mpv does not provide.
  - Lua scripts are also a possible solution for some features.
- Give users more choices.

**Technical tips**

- Use a XIB for UI if possible for things like as positioning of UI elements, whether a view uses layer, Cocoa bindings, etc.
- Add proper comments.
- Use 2 spaces for indentation.
- There's no fixed guidelines for code style. Maybe later?

**Current structure**

- Only `VideoView` and `MPVController` may call mpv APIs directly.
- `PlayerCore` encapsulates general playback functions.
  - Setting options/properties directly through `MPVController` is discouraged.
  - `PlayerCore` should only contain logic that controls playback.
- Window related logic should be in `MainWindowController`.
  - `windowDidLoad()`: stuff that should be done once
  - `windowDidOpen()`: stuff that should be done every time when window shown, like resetting some UI components. Note that window is not necessarily loaded here.
  - `windowWillClose()`: release / deinitialize 

## How to Contribute

**Please open an issue and ask for permission from the author before actually starting doing something** to make sure that there's not someone else working on the same feature.

1. Fork and clone the repository
2. Follow [the guide to build with pre-compiled dylibs in README.md](README.md#use-pre-compiled-dylibs)
3. Open `iina.xcworkspace`.
4. Commit changes, test, push, and submit a pull request.

If you want to build libmpv and other depended dylibs on your own, please refer to [the guide in README.md](README.md#build-with-the-lastest-mpv).

**Pull requests**

- Please set base branch of your pull request to `develop`.
- If you found `develop` has been updated during your change, remember to do a rebase before opening a pull request:

  ```
  git rebase upstream/develop
  ```
- Please submit separate pull requests for different features.
- Please make sure the pull request only contains changes made by yourself *intentionally*. Here are some examples:
  - `Podfile.lock`: This file may change if you have a different Cocoapods version installed. We suggest updating to the latest beta release by `sudo gem install cocoapods --pre`.
  - `project.pbxproj`: This file may change if you sign the project with a different developer account.
  - `xib` files: Please discard changes to an `xib` file if you didn't change anything in it.
  
