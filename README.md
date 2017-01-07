![IINA Icon](https://github.com/lhc70000/iina/raw/master/iina/Assets.xcassets/AppIcon.appiconset/256-1.png)

# IINA

IINA is a **modern** video player for macOS.  
Published under the [GPLv3](http://www.gnu.org/licenses/gpl-3.0-standalone.html).

Website: [https://lhc70000.github.io/iina/](https://lhc70000.github.io/iina/)

Releases: [https://github.com/lhc70000/iina/releases](https://github.com/lhc70000/iina/releases)

Telegram group: 
[https://telegram.me/joinchat/EUPqOwkAnyXQGU3cje6aQg](https://telegram.me/joinchat/EUPqOwkAnyXQGU3cje6aQg)

---

When raising an issue, please **use English** if possible.  

在提 issue 时，请尽量使用**英文**！  

# Features

- Based on [mpv](https://github.com/mpv-player/mpv), a powerful media player
- Designed for modern macOS (10.10+)
- User-friendly interface
- All the features you need for videos, audios and subtitles
- Supported basic playlist and chapters
- MPV config files and script system are still available for advanced users
- Written in Swift, followed up on new technologies like Touch Bar
- Still in active development

# Build

## Use pre-compiled dylibs

1. Please make sure cocoapods is installed.

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

Theoretically no extra work is needed. _If you are unwilling to use the provided dylibs, follow the instructions below._

## Build with the lastest mpv

* Install mpv

  ```
  brew install mpv --with-uchardet
  ```
  Currently `ytdl` is not included when building, but will be considered in later versions.

* other/parse_doc.rb

  This script will fetch the *lastest* mpv documentation and generate `MPVOption.swift`, `MPVCommand.swift` and `MPVProperty.swift`. Only needed when updating libmpv. Note that once API changed, player source code may also need to be  changed.

* other/change_lib_dependencies.rb

  This script will deploy depended libraries into `libmpv/libs`.  
  Before running this script, you should copy libmpv into `libmpv/libs` first, like:

  ```
  cp ##path/to/libmpv## ./libmpv/libs
  sudo install_name_tool -id @executable_path/../Frameworks/libmpv.1.23.0.dylib ./libmpv/lib/libmpv.1.23.0.dylib
  ```

  Replace `##path/to/libmpv##` with the path to libmpv (which should be in your homebrew install path).

  Make sure in Xcode build settings, you have a phase copying of all these dylibs.

## Contribute

Any feedback is appreciated! You can

- Star it or fork it
- Download and test it
- Send bug reports
- Send feature requests
- Provide suggestions on code structures or UI designs
- Provide localizatons
- ...

