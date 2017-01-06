(WIP)

# Contributing

Thank you for being interested in IINA.

First of all, please be tolerate. I'm not a professional in Cocoa development or Swift, so my code, especially early parts may contain stupid logic or design flaw (a refactor is in my plan).

If you believe the code structure could be improved, please raise an issue.

## Issues

- Please use English for both title and detail. 请在标题和正文都使用英文。
- Before opening an issue, please check whether there already exists a similar one.

## Some Guidelines

- IINA is for modern macOS.
  - Stay consistent with the design language of macOS.
  - Stay consistent with behaviors of macOS original Applications.
- User interface and user experience are important.
  - Use animation for UI items, if possible.
  - Use proper font weight, size and color.
  - Leave margins everywhere.
- IINA is based on mpv.
  - Avoid adding features (especially decoding/playback related) that mpv does not provide.
  - Lua script is also a possible solution for some features.
- Give user more choices.

**Technical tips**

- Use xib for UI if possible, such as positioning of UI elements, whether a view uses layer, cocoa binding, etc.
- Add proper comments.
- Use 2 spaces for tabs.
- For code style, currently there's not a fixed guideline. Maybe later?

**Current structure**

- Only `VideoView` and `MPVController` may call mpv API directly.
- `PlayerCore` encapsulates general playback functions. Setting options/properties directly through `MPVController` is discouraged.


## How to Contribute

Fork, then clone the repo.
```
git clone git@github.com:(your-username)/iina.git
```

Make sure cocoapods is installed, if not, install by
```
sudo gem install cocoapods
```
Then run
```
pod install
```
in project root directory.

Open `iina.xcworkspace`.

Commit changes, test, push, and submit a pull request.

If you want to build dylibs on your own, please refer to `README.md`.

**Tips**

- If you found master has been updated during your change, remember to do a rebase before opening pull request.


