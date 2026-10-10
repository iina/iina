# Third-party notices and source provenance

## iPadOS additions

The application sources, tests, build definitions, and newly authored documentation in this directory are offered under **GPL-3.0-only**, to the extent copyright applies. They were added as an experimental iPadOS contribution on **2026-10-10**, with AI assistance. See [LICENSE](LICENSE). This notice does not change the ownership or licenses of upstream or third-party material. The application is provided without warranty.

## IINA project and artwork

IINA is the upstream macOS media-player project: <https://github.com/iina/iina> and <https://iina.io>. Its contributors retain ownership of their work. The upstream repository is licensed under GPLv3, and its existing notices and history are retained. A verbatim copy of that license is also present as [UPSTREAM-IINA-LICENSE](UPSTREAM-IINA-LICENSE).

`Sources/iina.icon/Assets/Image.svg`, `Image 3.svg`, `Image 4.svg`, and `Sources/iina.icon/icon.json` are unmodified copies from upstream commit `fbcff4df7183b335880396af0655f6bb89d46442`, under `iina/iina.icon/`. Their Git blob hashes were verified against the upstream tree. The source artwork remains available for modification in these SVG/JSON files.

`Sources/Assets.xcassets/IINALogo.imageset/IINALogo.png` is a rendered IINA logo extracted from a locally installed IINA build and is attributed to the same project. The legacy blue play-button `AppIcon` asset was created for this prototype; the active Home Screen icon uses upstream's Icon Composer artwork.

References: [artwork source](https://github.com/iina/iina/tree/fbcff4df7183b335880396af0655f6bb89d46442/iina/iina.icon), [upstream license](https://github.com/iina/iina/blob/develop/LICENSE).

The repository is a contribution fork. No trademark/branding permission, endorsement, or official iPadOS release is claimed. Copyright licensing does not itself resolve trademark rights.

## MPVKit and native playback dependencies

The project references **MPVKit 1.0.0**, commit `288527dffbc6d3e63cce147fc7b520c64a791603`, using the **MPVKit** product. Upstream declares its source and the non-GPL-suffixed native bundles to be **LGPLv3**. Its **MPVKit-GPL** product and `enable-gpl` builds have different GPL licensing. See [pinned supplier README](https://github.com/mpvkit/MPVKit/blob/1.0.0/README.md), [package manifest](https://github.com/mpvkit/MPVKit/blob/1.0.0/Package.swift), and [verbatim LGPL text](LGPL-3.0-MPVKit.txt).

MPVKit identifies mpv v0.41.0 and FFmpeg n8.1.2 as its principal playback components. See [mpv copyright information](https://github.com/mpv-player/mpv/blob/master/Copyright) and [FFmpeg legal guidance](https://ffmpeg.org/legal.html). These are supplier declarations; they do not certify every native artifact's exact source, patches, or build configuration.

The selected iPadOS product references the following native targets through Swift Package Manager. The URLs identify supplier archive releases, not necessarily the individual components' own version numbers. The actual bundles, headers, and dependency source copies are not vendored into this iPadOS contribution. Checksums remain recorded in the pinned supplier package manifest.

| Target | Supplier release reference |
| --- | --- |
| `Libcrypto` | [Supplier archive](https://github.com/mpvkit/openssl-build/releases/download/3.3.5/Libcrypto.xcframework.zip) |
| `Libssl` | [Supplier archive](https://github.com/mpvkit/openssl-build/releases/download/3.3.5/Libssl.xcframework.zip) |
| `gmp` | [Supplier archive](https://github.com/mpvkit/gnutls-build/releases/download/3.8.11/gmp.xcframework.zip) |
| `nettle` | [Supplier archive](https://github.com/mpvkit/gnutls-build/releases/download/3.8.11/nettle.xcframework.zip) |
| `hogweed` | [Supplier archive](https://github.com/mpvkit/gnutls-build/releases/download/3.8.11/hogweed.xcframework.zip) |
| `gnutls` | [Supplier archive](https://github.com/mpvkit/gnutls-build/releases/download/3.8.11/gnutls.xcframework.zip) |
| `Libunibreak` | [Supplier archive](https://github.com/mpvkit/libass-build/releases/download/0.17.5/Libunibreak.xcframework.zip) |
| `Libfreetype` | [Supplier archive](https://github.com/mpvkit/libass-build/releases/download/0.17.5/Libfreetype.xcframework.zip) |
| `Libfribidi` | [Supplier archive](https://github.com/mpvkit/libass-build/releases/download/0.17.5/Libfribidi.xcframework.zip) |
| `Libharfbuzz` | [Supplier archive](https://github.com/mpvkit/libass-build/releases/download/0.17.5/Libharfbuzz.xcframework.zip) |
| `Libass` | [Supplier archive](https://github.com/mpvkit/libass-build/releases/download/0.17.5/Libass.xcframework.zip) |
| `Libbluray` | [Supplier archive](https://github.com/mpvkit/libbluray-build/releases/download/1.4.0/Libbluray.xcframework.zip) |
| `Libuavs3d` | [Supplier archive](https://github.com/mpvkit/libuavs3d-build/releases/download/1.2.1-fix/Libuavs3d.xcframework.zip) |
| `Libdovi` | [Supplier archive](https://github.com/mpvkit/libdovi-build/releases/download/3.3.2/Libdovi.xcframework.zip) |
| `MoltenVK` | [Supplier archive](https://github.com/mpvkit/moltenvk-build/releases/download/1.4.2/MoltenVK.xcframework.zip) |
| `Libshaderc_combined` | [Supplier archive](https://github.com/mpvkit/libshaderc-build/releases/download/2025.5.0/Libshaderc_combined.xcframework.zip) |
| `lcms2` | [Supplier archive](https://github.com/mpvkit/lcms2-build/releases/download/2.17.0/lcms2.xcframework.zip) |
| `Libplacebo` | [Supplier archive](https://github.com/mpvkit/libplacebo-build/releases/download/7.360.1/Libplacebo.xcframework.zip) |
| `Libdav1d` | [Supplier archive](https://github.com/mpvkit/libdav1d-build/releases/download/1.5.3/Libdav1d.xcframework.zip) |
| `Libavcodec` | [Supplier archive](https://github.com/mpvkit/MPVKit/releases/download/1.0.0/Libavcodec.xcframework.zip) |
| `Libavdevice` | [Supplier archive](https://github.com/mpvkit/MPVKit/releases/download/1.0.0/Libavdevice.xcframework.zip) |
| `Libavformat` | [Supplier archive](https://github.com/mpvkit/MPVKit/releases/download/1.0.0/Libavformat.xcframework.zip) |
| `Libavfilter` | [Supplier archive](https://github.com/mpvkit/MPVKit/releases/download/1.0.0/Libavfilter.xcframework.zip) |
| `Libavutil` | [Supplier archive](https://github.com/mpvkit/MPVKit/releases/download/1.0.0/Libavutil.xcframework.zip) |
| `Libswresample` | [Supplier archive](https://github.com/mpvkit/MPVKit/releases/download/1.0.0/Libswresample.xcframework.zip) |
| `Libswscale` | [Supplier archive](https://github.com/mpvkit/MPVKit/releases/download/1.0.0/Libswscale.xcframework.zip) |
| `Libuchardet` | [Supplier archive](https://github.com/mpvkit/libuchardet-build/releases/download/0.0.8/Libuchardet.xcframework.zip) |
| `Libmpv` | [Supplier archive](https://github.com/mpvkit/MPVKit/releases/download/1.0.0/Libmpv.xcframework.zip) |

`Libsmbclient` and the `-GPL` mpv/FFmpeg targets are not dependencies of the selected product. `Libluajit` is conditional on macOS in the supplier manifest and is not part of this iPadOS target. Provider access through Files is distinct from linking Samba's client library.

Before distributing compiled applications or native-library bundles, the distributor must review the exact component licenses, preserve their required copyright/license notices, provide the appropriate corresponding sources/build information and relinking materials, and consider applicable signing, distribution-channel, and patent requirements. This source publication does not complete that binary-distribution review.

## System frameworks and provider APIs

AVFoundation, VideoToolbox, SwiftUI, UIKit, and other Apple frameworks are referenced through the installed Apple SDK; their implementations and SDK files are not included here. Using their public APIs does not relicense those frameworks under the application's GPL.

OpenSubtitles.com is an external service used through its API. No API credential, provider SDK source, or downloaded subtitle corpus is included. Users must supply registered credentials and comply with the provider's service terms and permissions for their subtitle downloads. Mock responses and placeholder credentials in the tests are authored test data.

## Synthetic fixtures

The short video, tone audio, and subtitle fixtures in `Tests/Fixtures` were generated for this prototype. They contain no third-party film, music recording, or downloaded subtitles. Their generated content and authored subtitle text are offered under GPL-3.0-only; see [fixture provenance](Tests/Fixtures/README.md). FFmpeg was a generation tool and its executable is not distributed with these fixtures.
