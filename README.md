![IINA Icon](https://github.com/lhc70000/iina/raw/master/iina/Assets.xcassets/AppIcon.appiconset/256-1.png)

# IINA

IINA is a **modern** video player for macOS.  
Published under [GPLv3](https://github.com/lhc70000/iina/blob/master/LICENSE).

Website: [https://lhc70000.github.io/iina/](https://lhc70000.github.io/iina/)

Releases: [https://github.com/lhc70000/iina/releases](https://github.com/lhc70000/iina/releases)

Telegram group: 
[https://t.me/joinchat/AAAAAEBemW7dU8X7IHShwQ](https://t.me/joinchat/AAAAAEBemW7dU8X7IHShwQ)

---

When raising an issue, please **use English** if possible.  

在提 issue 时，请尽量使用**英文**！  

---

# Features

- Based on [mpv](https://github.com/mpv-player/mpv), a powerful media player
- Designed for modern versions of macOS (10.10+)
- User-friendly interface
- Contains all features for videos, audios and subtitles
- Supports basic playlists and chapters
- MPV config files and script system available for advanced users
- Written in Swift, followed up on new technologies like Touch Bar
- Still in active development

# Installing

To install IINA, please go to the [releases page](https://github.com/lhc70000/iina/releases) and download the latest version of IINA. Simply open the downloaded .dmg file and then drag the IINA icon to your Applications folder. Done!

# Building

**Using pre-compiled dylibs**

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

**Building with the lastest mpv**

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

**Please read [CONTRIBUTING.md](https://github.com/lhc70000/iina/blob/master/CONTRIBUTING.md) before opening an issue or a pull request.**

**Please ask the author before starting to work on a pull request** to ensure that no one else is working on the same feature.

Any feedback is appreciated! You can

- Star or fork it
- Download and test it
- Post bug reports
- Post feature requests
- Provide suggestions on code structure or UI design
- Provide localizatons
- ...

