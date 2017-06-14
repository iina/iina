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

- Based on [mpv](https://github.com/mpv-player/mpv), a powerful media player
- Designed for modern macOS (10.10+)
- Aims to offer the best user experience
- All the features you need for videos, audios, subtitles, playlist, chapters and so on
- MPV config files and script system are available for advanced users
- Written in Swift, followed up on new technologies like Touch Bar and Force Touch
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

**Build with the lastest mpv**

* Install mpv

  ```
  brew install mpv --with-uchardet
  ```
  
  Feel free to include any other libraries if you like.
  
* Copy latest [header files](https://github.com/mpv-player/mpv/tree/master/libmpv) into `libmpv/include/mpv/`

* other/parse_doc.rb

  This script will fetch the *lastest* mpv documentation and generate `MPVOption.swift`, `MPVCommand.swift` and `MPVProperty.swift`. This is only needed when updating libmpv. Note that if the API changes, the player source code may also need to be changed.

* other/change_lib_dependencies.rb

  This script will deploy the depended libraries into `libmpv/libs`.
  Make sure you have a phase copying of all these dylibs in Xcode's build settings.

## Contributing

**Please read [CONTRIBUTING.md](https://github.com/lhc70000/iina/blob/master/CONTRIBUTING.md) before opening an issue or pull request.**

**Please ask for permission from the author before starting working on a pull request** to make sure that there's not someone else working on the same feature.

Any feedback/contribution is appreciated!
