![IINA Icon](https://github.com/lhc70000/iina/raw/master/iina/Assets.xcassets/AppIcon.appiconset/256-1.png)

# IINA

Project IINA is a **modern** video player for macOS.

Website: [https://lhc70000.github.io/iina/](https://lhc70000.github.io/iina/)

Releases: [https://github.com/lhc70000/iina/releases](https://github.com/lhc70000/iina/releases)

---

When raising a issue, please **use English** if possible.

在提 issue 时，请尽量使用**英文**！

# Features

- Based on [mpv](https://github.com/mpv-player/mpv), the powerful media player project
- For and only for modern macOS (10.10+)
- User friendly interface
- All the features you need for video, audio and subtitles
- Support basic playlist and chapters
- MPV config file and script system are still available for advanced users
- Written in Swift, open for new technologies like Touch Bar
- Still in active development

# Build

Please make sure cocoapods is installed.

```
sudo gem install cocoapods
```

Run pod install in project root directory.

```
pod install
```

Theoretically no extra work is needed. _If you are unwilling to use the provided dylibs, follow the instructions below._

**Install mpv**

```
brew install mpv --with-uchardet
```
Currently `ytdl` is not included when building, but will be considered in later versions.

**other/parse_doc.rb**

This script will fetch the *lastest* mpv documentation and generate `MPVOption.swift`, `MPVCommand.swift` and `MPVProperty.swift`. Only needed when updating libmpv. Note that once API changed, player source code may also need to be changed.

**other/change_lib_dependencies.rb**

This script will resolve library dependencies and copy all required dylibs into `libmpv/libs`.

Before running this script, you should first copy libmpv into `libmpv/libs`, like:

```
cp path/to/libmpv ./libmpv/libs
sudo install_name_tool -id @executable_path/../Frameworks/libmpv.1.23.0.dylib ./libmpv/lib/libmpv.1.23.0.dylib
```

Where `path/to/libmpv` should be in your homebrew install path.

Make sure in Xcode build settings, you have a phase copying all these dylibs.

## Contribute

Any feedback is appreciated! You can

- Star or fork it
- Download and test it
- Send bug report
- Send feature request
- Provide suggestions on code structure and UI design
- Provide localizaton
- ...

## License

GPLv3
