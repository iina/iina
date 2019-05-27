<p align="center">
<img src="https://github.com/iina/iina/raw/master/iina/Assets.xcassets/AppIcon.appiconset/256-1.png" />
</p>

<h1 align="center">IINA</h1>

<p align="center">IINA is the <b>modern</b> video player for macOS.</p>

<p align=center>
<a href="https://iina.io">Website</a> ·
<a href="https://github.com/iina/iina/releases">Releases</a> ·
<a href="https://t.me/IINAUsers">Telegram Group</a>
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

1. IINA uses [CocoaPods](https://cocoapods.org) for managing the installation of third-party libraries. If you don't already have it installed, here's how you can do so:

#### Using RubyGems
```console
$ sudo gem install cocoapods
```

#### Using Homebrew
```console
$ brew install cocoapods
```

2. Run `pod install` in project's root directory.

IINA ships with pre-compiled dynamic libraries for convenience reasons. If you aren't planning on modifying these libraries, you can follow the instructions below to build IINA; otherwise, skip down to [Building mpv manually](#building-mpv-manually):

### Using the pre-compiled libraries

1. Open iina.xcworkspace in the [latest public version of Xcode](https://itunes.apple.com/us/app/xcode/id497799835). *IINA may not build if you use any other version.*

2. Build the project.

### Building mpv manually

1. Build your own copy of mpv. If you're using a package manager to manage dependencies, the steps below outline the process.

#### Homebrew

Use our tap as it passes in the correct flags to mpv's configure script:

```console
$ brew tap iina/homebrew-mpv-iina
$ brew install mpv-iina
```

#### MacPorts

Pass in these flags when installing:

```console
# port install mpv +uchardet -bundle -rubberband configure.args="--enable-libmpv-shared --enable-lua --enable-libarchive --enable-libbluray --disable-swift --disable-rubberband" 
```

2. Copy the latest [header files from mpv](https://github.com/mpv-player/mpv/tree/master/libmpv) (\*.h) into `deps/include/mpv/`.

3. Run `other/parse_doc.rb`. This script will fetch the latest mpv documentation and generate `MPVOption.swift`, `MPVCommand.swift` and `MPVProperty.swift`. This is only needed when updating libmpv. Note that if the API changes, the player source code may also need to be changed.

4. Run `other/change_lib_dependencies.rb`. This script will deploy the dependent libraries into `deps/libs`. If you're using a package manager to manage dependencies, invoke it like so:

#### Homebrew

```console
$ other/change_lib_dependencies.rb "$(brew --prefix)" "$(brew --prefix mpv-iina)/lib/libmpv.dylib"
```

#### MacPorts

```console
$ port contents mpv | grep '\.dylib$' | xargs other/change_lib_dependencies.rb /opt/local
```

5. Open iina.xcworkspace in the [latest public version of Xcode](https://itunes.apple.com/us/app/xcode/id497799835). *IINA may not build if you use any other version.* 

6. Remove all of references to .dylib files from the Frameworks group in the sidebar and drag all the .dylib files in `deps/libs` to that group.

7. Drag all the .dylib files in `deps/libs` into the "Embedded Binaries" section of the iina target.

8. Build the project.

## Contributing

IINA is always looking for contributions, whether it's through bug reports, code, or new translations.

* If you find a bug in IINA, or would like to suggest a new feature or enhancement, it'd be nice if you could [search your problem first](https://github.com/iina/iina/issues); while we don't mind duplicates, keeping issues unique helps us save time and considates effort. If you can't find your issue, feel free to [file a new one](https://github.com/iina/iina/issues/new).

* If you're looking to contribute code, please read [CONTRIBUTING.md](CONTRIBUTING.md)–it has information on IINA's process for handling contributions, and tips on how the code is structured to make your work easier.
* If you'd like to translate IINA to your language, please check the [Translation Status](https://github.com/iina/iina/wiki/Translation-Status) page first: if a language is labeled as "Need help", then feel free to [update the translation](https://github.com/iina/iina/wiki/Translation#update-translations). If it doesn't contain your language at all, you can [submit a new translation](https://github.com/iina/iina/wiki/Translation). If you need help working on a translation, you can contact [@lhc70000](https://github.com/lhc70000) or file an issue and one of the maintainers will try to help you out.
