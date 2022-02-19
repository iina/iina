# Contributing

Thanks for your interest in contributing to IINA! IINA is not perfect, but it's our goal to make it the best it can be. Here's how you can help.

First of all, if you plan on doing any work, *please check the issue tracker*. Not only does this make it easier to track progress, it also prevents people doing duplicate work, as well as allows for the community to weigh in on the implementation of a feature *before* it's already all coded up. Nothing's more sad than having to go back and delete or rewrite code because of a misunderstanding in how it would fit into IINA :(

## Contribution workflow

IINA follows the standard fork/commit/pull request process for integrating changes. If you have something that you're interested in working on (*after checking the issue tracker, of course ;)*):

1. Fork and clone the repository
2. Follow [the guide to build with pre-compiled dylibs in README.md](README.md#using-the-pre-compiled-libraries), unless you're modifying those.
3. Open `iina.xcodeproj` in Xcode. Again, make sure you are using the [latest public version of Xcode](https://itunes.apple.com/us/app/xcode/id497799835); IINA may build with another version but this is not guaranteed. Generally, around June, a new branch will pop up with support for the new version of macOS and associated developer tools; however, main development will still occur on `develop`.
4. Commit your changes, test them, push to your repository, and submit a pull request against iina/iina's `develop` branch.

Some tips for your pull request:

* If you found `develop` has been updated before your change was merged, you can rebase in the new changes before opening a pull request:

```console
$ git rebase upstream/develop
```
* Please submit separate pull requests for different features; i.e. try not to shove multiple, unrelated changes into one pull request.
* Please make sure the pull request only contains changes that you've made intentionally; if you didn't mean to touch a file, you should probably not include it in your commit. Here are some files that like to have spurious changes in them:
  - `Podfile.lock`: This file may change if you have a different CocoaPods version installed than the project maintainers. We suggest updating to the ~~latest release~~ whatever `sudo gem install cocoapods --pre` gives you, at least until CocoaPods 1.6 is released.
  - `project.pbxproj`: This file may change if you sign the project with a different developer account. Changes due to adding or removing files are OK, generally.
  - `xib` files: Please discard changes to an `xib` file if you didn't change anything in it.

## Some Guidelines

* IINA is designed for modern versions of macOS.
  - Stay consistent with the [macOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/macos/).
  - Stay consistent with behaviors of the macOS built-in applications, except in certain exceptional cases.
* User interface and user experience is important.
  - Use animations for UI items, if possible.
  - Use the proper system font weight, size and color.
  - Leave margins everywhere.
* IINA is based on mpv.
  - Avoid adding features (especially decoding/playback related) that mpv does not provide.
  - Lua scripts are also a possible solution for some features.
* Give users more choices when possible.

### Technical tips

* Use a XIB for UI if possible for things like as positioning of UI elements, whether a view uses layer, Cocoa bindings, etc.
* Add comments when necessary.
* Use 2 spaces for indentation.
* There's no fixed guidelines for code style, unfortunately, so please use your best judgement in making the code look consistent. We may add one in the future.

### Current structure

* Only `VideoView` and `MPVController` may call mpv APIs directly.
* `PlayerCore` encapsulates general playback functions.
  - Setting options/properties directly through `MPVController` is discouraged.
  - `PlayerCore` should only contain logic that controls playback.
* Window related logic should be in `MainWindowController`.
  - `windowDidLoad()`: stuff that should be done once
  - `windowDidOpen()`: stuff that should be done every time when window shown, like resetting some UI components. Note that the window may not necessarily loaded here.
  - `windowWillClose()`: release resources and deinitialize

If you believe the code can be improved, please raise an issue.
