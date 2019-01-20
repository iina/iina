<p align="center">
<img src="https://github.com/iina/iina/raw/master/iina/Assets.xcassets/AppIcon.appiconset/256-1.png" />
</p>

<h1 align="center">IINA</h1>

<p align="center">IINA is the <b>modern</b> video player for macOS.</p>

<p align=center>
<a href="https://iina.io">Website</a> ·
<a href="https://github.com/iina/iina/releases">Releases</a> ·
<a href="https://t.me/joinchat/AAAAAEBemW7dU8X7IHShwQ">Telegram Group</a>
</p>

---

## Features

* Based on [mpv](https://github.com/mpv-player/mpv), which provides the best decoding capacity on macOS
* Designed with modern versions of macOS (10.11+) in mind
* All the features you need for video and music: subtitles, playlists, chapters…and much, much more!
* Force Touch, picture-in-picture and advanced Touch Bar support
* Customizable user interface including multiple color schemes and on screen controller (OSC) layout positioning
* Standalone Music Mode designed for audio files
* Video thumbnails
* Online subtitle searching and intelligent local subtitle matching
* Unlimited playback history
* Convenient and interactive settings for video/audio filters
* Fully customizable keyboard, mouse, trackpad, and gesture controls
* mpv configuration files and script system for advanced users
* Command line tool and browser extensions provided
* In active development

## Building

IINA ships with pre-compiled dynamic libraries for convenience reasons. If you aren't planning on modifying these libraries, you can follow the instructions below to build IINA; otherwise, skip down to [Building mpv manually](#building-mpv-manually) and then run the steps here:

### Using the pre-compiled libraries

1. IINA uses [CocoaPods](https://cocoapods.org) for managing the installation of third-party libraries. If you don't already have it installed, here's how you can do so:

*Note: The current stable version of CocoaPods [has an unfortunate bug](https://github.com/CocoaPods/CocoaPods/issues/7708) that prevents IINA from building, which has luckily been fixed in their master branch and set to roll out in version 1.6. To get access to this version, please install CocoaPods with `sudo gem install cocoapods --pre` and ignore the installation instructions below*.

### Using RubyGems
```console
$ sudo gem install cocoapods
```

### Using Homebrew
```console
$ brew install cocoapods
```

2. Run `pod install` in project's root directory.

3. Open iina.xcworkspace in the [latest public version of Xcode](https://itunes.apple.com/us/app/xcode/id497799835). *IINA may not build if you use any other version.*

## Building mpv manually

1. Install mpv:

```console
$ brew install mpv --with-uchardet
```
Feel free to include your own copies of the other libraries if you'd like.

2. Copy latest [header files](https://github.com/mpv-player/mpv/tree/master/libmpv) into `libmpv/include/mpv/`.

3. Run `other/parse_doc.rb`. This script will fetch the latest mpv documentation and generate `MPVOption.swift`, `MPVCommand.swift` and `MPVProperty.swift`. This is only needed when updating libmpv. Note that if the API changes, the player source code may also need to be changed.

4. Run `other/change_lib_dependencies.rb`. This script will deploy the depended libraries into `libmpv/libs`.
  Make sure you have a phase copying of all these dylibs in Xcode's build settings.

## Contributing

IINA is always looking for contributions, whether it's through bug reports, code, or new translations.

* If you find a bug in IINA, or would like to suggest a new feature or enhancement, it'd be nice if you could [search your problem first](https://github.com/iina/iina/issues); while we don't mind duplicates, keeping issues unique helps us save time and considates effort. If you can't find your issue, feel free [to file a new one](https://github.com/iina/iina/issues/new).

* If you're looking to contribute code, please read [CONTRIBUTING.md](CONTRIBUTING.md)–it has information on IINA's process for handling contributions, and tips on how the code is structured to make your work easier.
* If you'd like to translate IINA to your language, please check the [Translation Status](https://github.com/iina/iina/wiki/Translation-Status) page first: if a language is labeled as "Need help", then feel free to [update the translation](https://github.com/iina/iina/wiki/Translation#update-translations). If it doesn't contain your language at all, you can [submit a new translation](https://github.com/iina/iina/wiki/Translation). If you need help working on a translation, you can contact [@lhc70000](https://github.com/lhc70000) or file an issue and one of the maintainers will try to help you out.
