<p align="center">
<img src="https://github.com/lhc70000/iina/raw/master/iina/Assets.xcassets/AppIcon.appiconset/256-1.png" />
</p>

<h1 align="center">IINA</h1>

<p align="center">IINA is the <b>modern</b> video player for macOS.</p>

<p align=center>
<a href="https://lhc70000.github.io/iina/">Website</a> · 
<a href="https://github.com/lhc70000/iina/releases">Releases</a> · 
<a href="https://t.me/joinchat/AAAAAEBemW7dU8X7IHShwQ">Telegram Group</a>
</p>

***

# Features

- Based on [mpv](https://github.com/mpv-player/mpv), which provides the best decoding capacity on macOS
- Designed for modern macOS (10.11+), aims to offer the best user experience
- All the features you need for videos, audios, subtitles, playlist, chapters and so on
- Force Touch, Picture-in-picture and (advanced) Touch Bar support
- Customizable user interface including color schemes and on screen controller (OSC) layout
- Standalone Music Mode designed for audio files
- Thumbnail preview for the whole timeline like YouTube
- Online subtitle searching and intelligent local subtitle matching
- Unlimited playback history
- Convenient and interactive settings for video/audio filters
- Fully customizable keyboard, mouse and trackpad gesture control
- MPV config files and script system are available for advanced users
- Command Line Tool and browser extensions provided
- Still in active development

# Build

**Use pre-compiled dylibs**

1. Please make sure CocoaPods is installed.

  **gem**
  ```
  sudo gem install cocoapods
  ```
  **homebrew**
  ```
  brew install cocoapods
  ```

2. Run pod install in project root directory.
  ```
  pod install
  ```
  
3. Open `.xcworkspace` file.

Theoretically no extra work is needed. _If you are unwilling to use the provided dylibs, follow the instructions below._

**Build with the latest mpv**

* Install mpv

  ```
  brew install mpv --with-uchardet
  ```
  
  Feel free to include any other libraries if you like.
  
* Copy latest [header files](https://github.com/mpv-player/mpv/tree/master/libmpv) into `libmpv/include/mpv/`

* other/parse_doc.rb

  This script will fetch the *latest* mpv documentation and generate `MPVOption.swift`, `MPVCommand.swift` and `MPVProperty.swift`. This is only needed when updating libmpv. Note that if the API changes, the player source code may also need to be changed.

* other/change_lib_dependencies.rb

  This script will deploy the depended libraries into `libmpv/libs`.
  Make sure you have a phase copying of all these dylibs in Xcode's build settings.

## Contributing

**Please read [CONTRIBUTING.md](https://github.com/lhc70000/iina/blob/master/CONTRIBUTING.md) before opening an issue or pull request.**

**Please ask for permission from the author before starting working on a pull request** to make sure that there's not someone else working on the same feature.

Any feedback/contribution is appreciated!

**Translation**

Please check [Translation Status](https://github.com/lhc70000/iina/wiki/Translation-Status) first. If a language is labeled as "Need help", then please feel free to [update](https://github.com/lhc70000/iina/wiki/Translation#update-translations) the translation. If it doesn't contain your language, it will be awesome to [submit a new translation](https://github.com/lhc70000/iina/wiki/Translation). Please contact the author ([@lhc70000](https://github.com/lhc70000)) if you don't know how to submit translations using GitHub.
