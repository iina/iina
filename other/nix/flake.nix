{
  description = "IINA – The modern video player for macOS.";

  # Nix Packages has adopted Apple's perceived macOS support policy of only supporting the latest 3
  # versions. Also of concern, Nixpkgs 26.05 is the last release that supports Intel Macs. Rather
  # than applying overrides to newer versions of Nix packages to lower the minimum supported macOS
  # version, this flake uses nixpkgs 25.05 (supports macOS 11.3+) and applies overrides to upgrade
  # packages to newer versions.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs =
    { self, nixpkgs }:
    let
      appName = "IINA";

      systemNames = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      # Dictionary of { system name → package set }
      perSystemPackages = nixpkgs.lib.genAttrs systemNames (
        systemName:
        let
          pkgs = import nixpkgs {
            system = systemName;
            config.allowUnfree = true;
          };

          ### Tools / Commands ###

          resign = pkgs.writeShellApplication {
            name = "iina-resign";
            runtimeInputs = [
              pkgs.coreutils
            ];
            text = ''
              set -euo pipefail
              app="$1"

              find "$app" -type d -print0 | xargs -0 chmod u+rwx
              find "$app" -type f -print0 | xargs -0 chmod u+rw
              find "$app/Contents/MacOS" -type f -perm -111 -print0 | xargs -0 chmod u+rw

              /usr/bin/codesign --remove-signature "$app"
              /usr/bin/codesign --force --deep --sign - "$app"
            '';
          };

          libTool = pkgs.stdenv.mkDerivation {
            pname = "iina-lib-tool";
            version = "1.0";
            propagatedBuildInputs = [ pkgs.python3 ];
            dontUnpack = true;
            installPhase = "install -Dm755 ${./lib_tool.py} $out/bin/iina-lib-tool";
          };

          # Pull system's xcode in
          xcode = pkgs.runCommand "system-xcode" { } ''
            export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer";
            mkdir -p "$out/bin"
            ln -sf "$DEVELOPER_DIR/usr/bin/xcodebuild" "$out/bin/xcodebuild"
          '';

          # FFmpeg 9 must be built with a newer version of nasm than provided by nixpkgs 25.05.
          # Rather than build a newer version of this tool, pull in the system's version.
          nasm = pkgs.runCommand "system-nasm" { } ''
            mkdir -p "$out/bin"
            ln -sf /opt/homebrew/bin/nasm "$out/bin/nasm"
          '';

          ### Package Overrides ###

          # Upgrade to the version supplied by nixpkgs 26.05.
          dav1d =
            (pkgs.dav1d.override {
              inherit nasm;
            }).overrideAttrs
              (
                finalAttrs: previousAttrs: {
                  version = "1.5.3";
                  src = pkgs.fetchFromGitHub {
                    owner = "videolan";
                    repo = "dav1d";
                    rev = finalAttrs.version;
                    hash = "sha256-E3da/LJ8HNy1osExmupovqnL8JHgVNzPUCG5F8TJKXQ=";
                  };
                }
              );

          # Upgrade to 2.14.3 as it contains fixes for security vulnerabilities.
          freetype = pkgs.freetype.overrideAttrs (
            finalAttrs: previousAttrs: {
              version = "2.14.3";
              src = pkgs.fetchurl {
                url = "mirror://savannah/freetype/freetype-${finalAttrs.version}.tar.xz";
                sha256 = "sha256-NrxPHMQTM1No7mVsQq/KZcWjmH6HaMwozxG6d154Wl8=";
              };
            }
          );

          # Upgrade to the version supplied by nixpkgs 26.05.
          fontconfig =
            (pkgs.fontconfig.override {
              inherit freetype;
            }).overrideAttrs
              (
                finalAttrs: previousAttrs: {
                  version = "2.18.3";
                  src = pkgs.fetchurl {
                    url = "https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/${finalAttrs.version}/fontconfig-${finalAttrs.version}.tar.xz";
                    hash = "sha256-T3tVSjjN94wDP2ZsiHHzdJ4UoJT2Wgf2MMke0LQ9NeM=";
                  };
                  doCheck = false; # Skip tests to speed up build
                }
              );

          # Upgrade to the version supplied by nixpkgs 26.05.
          harfbuzz =
            (pkgs.harfbuzz.override {
              inherit freetype;
            }).overrideAttrs
              (
                finalAttrs: previousAttrs: {
                  version = "13.2.1";
                  src = pkgs.fetchurl {
                    url = "https://github.com/harfbuzz/harfbuzz/releases/download/${finalAttrs.version}/harfbuzz-${finalAttrs.version}.tar.xz";
                    hash = "sha256-ZpXaPrfhvgqjCS/k2BQzoztH9FGSWcdZ1ynjqaVcFCk=";
                  };
                }
              );

          # Upgrade to a newer version.
          libass =
            (pkgs.libass.override {
              fontconfigSupport = true;
              inherit fontconfig;
              inherit freetype;
              inherit harfbuzz;
            }).overrideAttrs
              (
                finalAttrs: previousAttrs: {
                  version = "0.17.5";
                  src = pkgs.fetchurl {
                    url = "https://github.com/libass/libass/releases/download/${finalAttrs.version}/libass-${finalAttrs.version}.tar.xz";
                    hash = "sha256-LcolwODIN93wC1IBGz+CysHk3dOtAYIngGsMIoiGSsw=";
                  };
                  enableParallelBuilding = true;
                  nativeBuildInputs = previousAttrs.nativeBuildInputs ++ [ nasm ];
                }
              );

          # Upgrade to a newer version.
          libbluray =
            (pkgs.libbluray.override {
              inherit fontconfig;
            }).overrideAttrs
              (
                finalAttrs: previousAttrs: {
                  version = "1.4.1";
                  src = pkgs.fetchurl {
                    url = "https://get.videolan.org/libbluray/${finalAttrs.version}/libbluray-${finalAttrs.version}.tar.xz";
                    hash = "sha256-drXcQAl/KNyk67AJyY7VEyGyknRT91zHLPdKzQm59Ek=";
                  };
                  enableParallelBuilding = true;
                  nativeBuildInputs = [
                    pkgs.meson
                    pkgs.ninja
                    pkgs.pkg-config
                  ];
                  mesonFlags = [
                    "-Dbdj_jar=disabled" # No Java support
                  ];
                }
              );

          libhwy = pkgs.libhwy.overrideAttrs (old: {
            cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DBUILD_SHARED_LIBS=ON" ];
          });

          # Upgrade to a newer version.
          libjxl = pkgs.libjxl.overrideAttrs (
            finalAttrs: previousAttrs: {
              version = "0.12";
              src = pkgs.fetchFromGitHub {
                owner = "libjxl";
                repo = "libjxl";
                tag = "v${finalAttrs.version}";
                hash = "sha256-R69tMaqvbf3x/Uyh/OXTPICP7rS/4TXPiY2nFYKaotE=";
                # There are various submodules in `third_party/`.
                fetchSubmodules = true;
              };
              doCheck = false; # Skip tests to speed up build
            }
          );

          # Upgrade to a newer version.
          svt-av1 = pkgs.svt-av1.overrideAttrs (
            finalAttrs: previousAttrs: {
              version = "4.2.0";
              src = pkgs.fetchFromGitLab {
                owner = "AOMediaCodec";
                repo = "SVT-AV1";
                rev = "v${finalAttrs.version}";
                hash = "sha256-UF2g+QIlXOqtlp11QHqundyKHo0g7xIuQB0kg4vN8oY=";
              };
            }
          );

          openssl = pkgs.openssl.overrideAttrs (
            finalAttrs: previousAttrs: {
              version = "4.0.3";
              src = pkgs.fetchFromGitHub {
                owner = "openssl";
                repo = "openssl";
                tag = "openssl-${finalAttrs.version}";
                hash = "sha256-7h7s/mznobOfDHhZOlSg9A9Jvh70MhcSH6Ilb8Ytj/I=";
              };
              # OpenSSL from nixpkgs 25.05 includes patches which are no longer needed
              patches = [ ];
              # TODO: find way to disable manpages to speed up build. This alone doesn't work
              # outputs = builtins.filter (x: x != "man") previousAttrs.outputs;
              doCheck = false;
              withDocs = false;
            }
          ); # END openssl

          ffmpeg =
            (pkgs.ffmpeg-headless.override {
              # Upgrade to FFmpeg 9.0.2 as nixpkgs 25.05 provides FFmpeg 7.1.1.
              version = "9.0.2";
              hash = "sha256-/c6cVfMSF6JJxCuJs58bxBlmBXDJ+jbnC4pELB97Qb0=";

              withGPL = true; # Enable GPL-licensed codecs (e.g., x264, x265, libmp3lame)
              withVersion3 = true; # Enable version 3-licensed codecs (e.g., libfdk-aac)
              withUnfree = true; # Enable unfree codecs (e.g., AAC, MP3, H.264, H.265)

              withDebug = false; # Build using debug options
              withStripping = false; # Strip symbols from the resulting binaries to reduce size
              withSmallDeps = true;

              withAss = true; # (Advanced) SubStation Alpha subtitle rendering
              inherit libass;

              withBluray = true;
              inherit libbluray;

              withBs2b = true; # Bass to Binaural audio filter (uncommon)

              withDav1d = true; # AV1 decoder (focused on speed and correctness)
              inherit dav1d;

              withFontconfig = true;
              inherit fontconfig;

              withFreetype = true;
              inherit freetype;

              withHarfbuzz = true;
              inherit harfbuzz;

              withJxl = true;
              inherit libjxl;

              withSoxr = true;
              soxr = pkgs.soxr;

              withSvtav1 = true; # SVT-AV1 encoder, used for screenshots in AVIF format
              inherit svt-av1;

              withRubberband = true;
              rubberband = pkgs.rubberband;

              withVorbis = true; # Vorbis audio codec

              withXml2 = false; # Crashing due to missing library without this.

              withAom = false; # AV1 video encoder, IINA prefers SVT-AV1 (better performance)
              withCaca = false; # ASCII art video output, not used by IINA
              withDvdnav = false;
              withDvdread = false;
              withGnutls = false; # Use OpenSSL instead
              withMp3lame = false; # MP3 LAME audio codec encoder, not super useful for IINA
              withOpencl = false; # Vulkan predecessor, not supported on modern macOS
              withOpenjpeg = false; # JPEG 2000 de/encoder
              withOpenmpt = false; # Tracker music files decoder (various formats), not included in IINA historically
              withOpus = false; # Opus audio codec, not included in IINA historically
              withRist = false; # RIST protocol support
              withSdl2 = false; # SDL2 is disabled in our mpv build
              withSrt = false; # Secure Reliable Transport (SRT) protocol, not useful for IINA
              withSsh = false; # SFTP protocol support
              withTheora = false; # Theora video codec, not included in IINA historically
              withVdpau = false; # nVidia HW acceleration, not supported on modern macOS
              withVidStab = false; # Video stabilization filter, requires Linux
              withVmaf = false; # Video quality measurement tool, not useful for IINA
              withX264 = false; # H.264 video encoder, not super useful for IINA (& adds >4 MB to app size)
              withX265 = false; # H.265 video encoder, not super useful for IINA (& adds >31 MB to app size)
              withZmq = false; # ZeroMQ messaging library for FFmpeg streaming; not used by mpv or IINA
              withZvbi = false; # Teletext support, not useful for IINA

              # Don't build docs; we don't use them
              withHtmlDoc = false;
              withManPages = false;
              withPodDoc = false;
              withTxtDoc = false;

              # Don't build executables; we only want the libs
              buildFfmpeg = false;
              buildFfplay = false;
              buildFfprobe = false;
              buildQtFaststart = false;

            }).overrideAttrs
              (
                finalAttrs: previousAttrs: {
                  # The postproc configure flag was removed in FFmpeg 8.
                  configureFlags =
                    builtins.filter
                      (
                        x:
                        x != "--enable-postproc"
                        # The libcelt configure flag was removed in FFmpeg 9.
                        && x != "--disable-libcelt"
                        # The libshaderc configure flag was removed in FFmpeg 9.
                        && x != "--disable-libshaderc"
                      )
                      (
                        previousAttrs.configureFlags
                        ++ [
                          "--enable-openssl"
                          "--extra-cflags=-I${pkgs.lib.getLib openssl}/include"
                          "--extra-ldflags=-I${pkgs.lib.getLib openssl}/lib"
                        ]
                      );

                  nativeBuildInputs = previousAttrs.nativeBuildInputs ++ [ nasm ];
                  buildInputs = previousAttrs.buildInputs ++ [ openssl ];
                  # Skip tests to speed up build
                  doCheck = false;
                }
              ); # END ffmpeg

          # The upgraded mpv requires a newer version of libplacebo than provided by nixpkgs 25.05.
          libplacebo = pkgs.libplacebo.overrideAttrs (finalAttrs: {
            pname = "libplacebo";
            version = "7.360.1";
            src = pkgs.fetchFromGitLab {
              domain = "code.videolan.org";
              owner = "videolan";
              repo = "libplacebo";
              rev = "v${finalAttrs.version}";
              hash = "sha256-mIjQvc7SRjE1Orb2BkHK+K1TcRQvzj2oUOCUT4DzIuA=";
            };
          });

          mpv =
            (pkgs.mpv-unwrapped.override {
              inherit ffmpeg;
              inherit freetype;
              inherit libass;
              inherit libbluray;
              inherit libplacebo;

              lua = pkgs.luajit;

              archiveSupport = true;
              bs2bSupport = true;
              bluraySupport = true;
              cacaSupport = false;
              cmsSupport = true;
              dvdnavSupport = false;
              javascriptSupport = true;
              openalSupport = false;
              rubberbandSupport = true;
              vapoursynthSupport = false;
              vulkanSupport = true;
              zimgSupport = true;

              # Disable Linux-only bits
              alsaSupport = false;
              jackaudioSupport = false;
              pipewireSupport = false;
              x11Support = false;
              waylandSupport = false;
              vaapiSupport = false;
              vdpauSupport = false;
              sdl2Support = false;
              cddaSupport = false;
              dvbinSupport = false;
              sixelSupport = false;
            }).overrideAttrs
              (
                finalAttrs: previousAttrs: {
                  # Upgrade to mpv 0.41.0 as nixpkgs 25.05 provides mpv 0.40.0.
                  version = "v0.41.0";
                  src = pkgs.fetchFromGitHub {
                    owner = "mpv-player";
                    repo = "mpv";
                    tag = "v${"finalAttrs:version"}";
                    hash = "sha256-gJWqfvPE6xOKlgj2MzZgXiyOKxksJlY/tL6T/BeG19c=";
                  };
                  # The mpv package in nixpkgs 25.05 passes a sdl2 option to meson that is not present in
                  # mpv 0.41.0. Disable the building of man pages to speed up the build.
                  mesonFlags = builtins.filter (x: x != "-Dsdl2=disabled") previousAttrs.mesonFlags ++ [
                    "-Dmanpage-build=disabled"
                  ];
                  # Disabling building of man pages requires the package outputs be adjusted accordingly.
                  outputs = builtins.filter (x: x != "man") previousAttrs.outputs;
                  patches =
                    [ ]
                    # If needed include the fix for IINA issue #5956, the mpv regression described in mpv
                    # issue #17436 and fixed in mpv PR #17448. The fix is expected to be included in
                    # mpv 0.42.0.
                    ++
                      pkgs.lib.optionals
                        (
                          pkgs.lib.versionAtLeast finalAttrs.version "v0.40.0"
                          && pkgs.lib.versionOlder finalAttrs.version "v0.42.0"
                        )
                        [
                          (pkgs.fetchpatch2 {
                            url = "https://github.com/mpv-player/mpv/pull/17448.patch";
                            hash = "sha256-kXnlu8SJ/GEnFljnXK4ri6CrgDBXvOTjnQo3jdPAbSA=";
                          })
                        ];
                }
              ); # END mpv

          ### Dep Aggregations ###

          # Collect include deps (header files) as per readme.md
          depsInclude = pkgs.linkFarm "iina-deps-inc" [
            {
              name = "mpv";
              path = "${pkgs.lib.getDev mpv}/include/mpv";
            }
            {
              name = "libavcodec";
              path = "${pkgs.lib.getDev ffmpeg}/include/libavcodec";
            }
            {
              name = "libavdevice";
              path = "${pkgs.lib.getDev ffmpeg}/include/libavdevice";
            }
            {
              name = "libavfilter";
              path = "${pkgs.lib.getDev ffmpeg}/include/libavfilter";
            }
            {
              name = "libavformat";
              path = "${pkgs.lib.getDev ffmpeg}/include/libavformat";
            }
            {
              name = "libavutil";
              path = "${pkgs.lib.getDev ffmpeg}/include/libavutil";
            }
            {
              name = "libswresample";
              path = "${pkgs.lib.getDev ffmpeg}/include/libswresample";
            }
            {
              name = "libswscale";
              path = "${pkgs.lib.getDev ffmpeg}/include/libswscale";
            }
          ]; # END depsInclude

          # Collect lib deps as per readme.md
          depsLib = pkgs.linkFarm "iina-deps-lib" (
            pkgs.lib.flatten (
              map
                (
                  pkg:
                  let
                    libdir = "${pkgs.lib.getLib pkg}/lib";
                  in
                  builtins.map (file: {
                    name = baseNameOf file;
                    path = "${libdir}/${file}";
                  }) (builtins.attrNames (builtins.readDir libdir))
                )
                [
                  dav1d # AV1 video decoder
                  ffmpeg
                  fontconfig # Font configuration library
                  freetype # FreeType font rendering engine
                  harfbuzz # Text shaping engine. Used by avdevice, avfilter, ass
                  libass # ASS subtitle renderer
                  libbluray # Blu-ray support
                  libhwy
                  libjxl # JPEG-XL support
                  libplacebo # Required by mpv
                  mpv
                  pkgs.brotli # Brotli compression. Used for ass, fontconfig, bluray, & more
                  pkgs.fribidi # Hebrew and Arabic support
                  pkgs.gettext # Internationalization library
                  pkgs.glib # GTK GLib utility library. Required by harfbuzz
                  pkgs.gmp # Provides arbitrary precision arithmetic. Required by several libs
                  pkgs.graphite2 # Compiles Graphite-enabled fonts. Used by harfbuzz
                  pkgs.lcms2 # Little CMS color management lib. Required by placebo, jxl
                  pkgs.libarchive # Archive support
                  pkgs.libb2 # BLAKE2 hashing library
                  pkgs.libidn2 # Converts between ASCII & UTF domain names. Used by gnutls
                  pkgs.libjpeg_turbo # Needed to provide libjpeg
                  pkgs.libpng # PNG image format support
                  pkgs.libsamplerate # Sample Rate Converter for audio
                  pkgs.libuchardet # Character encoding detection library
                  pkgs.libunibreak # Unicode line breaking & word/grapheme breaking
                  pkgs.libunistring # Unicode string handling
                  pkgs.libwebp # WebP image de/encoder
                  pkgs.luajit # Lua Just-In-Time compiler. Required by mpv
                  pkgs.lz4 # LZ4 compression. Used by libarchive
                  pkgs.mujs # JavaScript engine. Needed for mpv's JS support
                  openssl # TLS support, needed for network streams
                  pkgs.pcre2 # Perl-compatible regular expression pattern matching
                  pkgs.rubberband # Enables FFmpeg to perform audio tempo & pitch modifications
                  pkgs.shaderc # Referenced by libplacebo, despite requiring Vulkan which IINA doesn't use
                  pkgs.snappy # Snappy compression
                  pkgs.soxr # SoX Resampler, needed for high-quality audio resampling
                  pkgs.speex # Used by avcodec, avdevice, avfilter, avformat
                  pkgs.xz # LZMA2 compression, needed by libarchive
                  pkgs.zimg # Image scaling & colorspace conversion library, needed by mpv
                  pkgs.zstd # Needed by libarchive

                  # Indirect libs
                  pkgs.libdovi # Dolby Vision, needed by libplacebo
                ]
            ) # END pkgs.lib.flatten
          ); # END depsLib

          # Collect SwiftPM deps as separate derivation for them to be cached
          spmDeps = pkgs.stdenv.mkDerivation {
            pname = "iina-spm-deps";
            version = "${self.shortRev or self.dirtyShortRev}";

            # Only include SwiftPM-related files as input
            src = pkgs.lib.cleanSourceWith {
              src = ./../..;
              filter =
                path: type:
                let
                  relPath = pkgs.lib.removePrefix (toString ./../.. + "/") (toString path);
                in
                pkgs.lib.hasSuffix "Package.resolved" relPath
                || pkgs.lib.hasSuffix "Package.swift" relPath
                || pkgs.lib.hasPrefix "iina.xcodeproj" relPath;
            };

            dontFixup = true;

            nativeBuildInputs = [ xcode ];

            buildPhase = ''
              export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer";
              APPLE_BIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
              export PATH="$APPLE_BIN:$DEVELOPER_DIR/usr/bin:/usr/bin:/bin:$PATH"
              export HOME=$PWD/.home  # Override home directory to isolate Xcode build from the host system
              export CFFIXED_USER_HOME="$HOME". # Another home variable to override
              export __XPC_CFFIXED_USER_HOME="$HOME" # Another home variable to override, for tests
              export TMPDIR="$PWD/.tmp"; mkdir -p "$TMPDIR"  # Overrides Derived Data directory

              export TOOLCHAINS=XcodeDefault
              export SDKROOT=macosx

              echo "[${systemName}] 🔧 Setting up SPM dependencies"
              if [ ${systemName} == "aarch64-darwin" ]; then
                export XCODE_BUILD_DESTINATION='platform=macOS,arch=arm64'
                ARCH="arm64"
              else
                export XCODE_BUILD_DESTINATION='platform=macOS,arch=x86_64'
                ARCH="x86_64"
              fi

              mkdir -p $out/.spm $out/.spm-cache $out/build

              xcodebuild \
                -workspace iina.xcodeproj/project.xcworkspace \
                -scheme iina \
                -destination "$XCODE_BUILD_DESTINATION" \
                -resolvePackageDependencies \
                -derivedDataPath "$out/build" \
                -clonedSourcePackagesDirPath "$out/.spm" \
                -packageCachePath "$out/.spm-cache" \
                -disablePackageRepositoryCache \
                -IDEPackageSupportDisableManifestSandbox=YES \
                -IDEPackageSupportDisablePluginExecutionSandbox=YES \
                ARCHS=$ARCH ONLY_ACTIVE_ARCH=NO
            '';

          }; # END spmDeps

          packages = {
            # Generates deps/lib & deps/executable (for a single architecture)l
            deps = pkgs.stdenv.mkDerivation {
              pname = "iina-single-arch-deps";
              version = "${self.shortRev or self.dirtyShortRev}";
              src = null;
              dontUnpack = true;
              dontFixup = true;

              nativeBuildInputs = [
                libTool
                pkgs.coreutils
                spmDeps
              ];

              buildPhase = ''
                echo "[${systemName}] 📦 Copying external deps"
                mkdir -p deps

                # Be careful to rename the directory to "lib" when copying
                cp -RLv "${depsLib}/" deps/lib
                mkdir -p deps/executable

                echo "[${systemName}] 📦 Copying SPM deps"
                cp -Rv "${spmDeps}"/* .
                cp -Rv "${spmDeps}"/.* .
                chmod -R u+rwx,g+rx,o+rx .

                echo "[${systemName}] 📦 Canonicalizing libs"
                ${libTool}/bin/iina-lib-tool --canonicalize --prune "./deps/lib" "./deps/executable"
              '';

              installPhase = ''
                mkdir -p $out
                # Note: Do not use -L. Need to preserve relative symlinks for later xcodebuild to resolve correctly.
                cp -Rv . "$out"
                cp -Rv .* "$out"
              '';

            }; # END iina

            # --- IINA Universal Application ---
            iina-universal = pkgs.stdenv.mkDerivation {
              pname = "iina-universal";
              version = "${self.shortRev or self.dirtyShortRev}";
              src = pkgs.nix-gitignore.gitignoreSource [ "other\ndeps\n" ] ./../..;
              strictDeps = true;
              dontFixup = true;

              nativeBuildInputs = [
                libTool
                pkgs.coreutils
                pkgs.gnused
                xcode
              ];

              buildPhase = ''
                echo "📦 Copying header files to deps/include"
                mkdir -p deps
                # Make sure to name this directory properly when copying
                cp -Rv "${depsInclude}" deps/include

                echo "📦 Combining universal libs"
                # Merge each lib in archroot1 with its counterpart in archroot0, creating universal binaries in archroot0
                archroot0=$PWD
                archroot1="${builtins.elemAt self.singleArchDeps 1}"

                echo "📦 Copying libs"
                cp -RLv "${builtins.elemAt self.singleArchDeps 0}/"* "$archroot0/"
                cp -Rv "${builtins.elemAt self.singleArchDeps 0}/.spm"* "$archroot0"
                chmod -R u+w "$archroot0"

                ${libTool}/bin/iina-lib-tool --canonicalize --merge-architectures "./deps/lib" "./deps/executable" \
                  --archroot0 "$archroot0" --archroot1 "$archroot1"

                chmod -R u+rwx,g+rx,o+rx . ./.*

                # Rewrite SwiftPM workspace-state.json to fix absolute paths
                if [ -f .spm/workspace-state.json ]; then
                  old_prefix=$(grep -Eo '/nix/.*/\.spm/' .spm/workspace-state.json | head -n1)
                  echo "Patching workspace-state.json: replacing $old_prefix → $PWD/.spm/"
                  ${pkgs.gnused}/bin/sed -i -E "s|$old_prefix|$PWD/.spm/|g" .spm/workspace-state.json
                fi

                git_rev="${self.rev or self.dirtyRev}"
                # Nix flakes cannot currently access branch info. Doing so may violate the stated goal of maximum
                # reproducibility, as the same git revision can be associated with an arbitrary number of branches.
                # Just use a placeholder for now:
                git_branch="<nix-build>"
                echo "Git branch: $git_branch, revision: $git_rev"

                echo "🔧 Setting up build environment for ${appName}"

                export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer";
                APPLE_BIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
                export PATH="$APPLE_BIN:$DEVELOPER_DIR/usr/bin:/usr/bin:/bin:$PATH"
                export HOME=$PWD/.home  # Override home directory to isolate Xcode build from the host system
                export CFFIXED_USER_HOME="$HOME". # Another home variable to override
                export __XPC_CFFIXED_USER_HOME="$HOME" # Another home variable to override, for tests
                export TMPDIR="$PWD/.tmp"; mkdir -p "$TMPDIR"  # Overrides Derived Data directory
                export XCODE_BUILD_DESTINATION='platform=macOS'
                PLUGINS_DIR="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"

                unset CC CXX LD AR RANLIB NM STRIP OBJCOPY \
                  CFLAGS CXXFLAGS LDFLAGS SDKROOT CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH \
                  NIX_CFLAGS_COMPILE NIX_CFLAGS_LINK PKG_CONFIG_PATH

                export TOOLCHAINS=XcodeDefault
                export SDKROOT=macosx

                echo "Using $TOOLCHAINS toolchain"
                echo "Using SDK: $SDKROOT"
                PLUGINS_DIR="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"

                # Build IINA Advance (universal)
                echo "🔨 Building ${appName}"
                xcodebuild \
                  -workspace iina.xcodeproj/project.xcworkspace \
                  -scheme iina \
                  -destination "$XCODE_BUILD_DESTINATION" \
                  -configuration Release \
                  -sdk $SDKROOT \
                  -skipPackagePluginValidation \
                  -derivedDataPath "$PWD/build" \
                  -clonedSourcePackagesDirPath "$PWD/.spm" \
                  -packageCachePath "$PWD/.spm-cache" \
                  -disablePackageRepositoryCache \
                  -disableAutomaticPackageResolution \
                  -onlyUsePackageVersionsFromResolvedFile \
                  -IDEPackageSupportDisableManifestSandbox=YES \
                  -IDEPackageSupportDisablePluginExecutionSandbox=YES \
                  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
                  OTHER_SWIFT_FLAGS="$OTHER_SWIFT_FLAGS -enable-experimental-feature Lifetimes -load-plugin-library $PLUGINS_DIR/libAppIntentsMacros.dylib -load-plugin-library $PLUGINS_DIR/libFinanceMacros.dylib -load-plugin-library $PLUGINS_DIR/libFoundationMacros.dylib -load-plugin-library $PLUGINS_DIR/libFoundationModelsMacros.dylib -load-plugin-library $PLUGINS_DIR/libMMIOMacros.dylib -load-plugin-library $PLUGINS_DIR/libObservationMacros.dylib -load-plugin-library $PLUGINS_DIR/libPreviewsMacros.dylib -load-plugin-library $PLUGINS_DIR/libStateReportingMacros.dylib -load-plugin-library $PLUGINS_DIR/libSwiftMacros.dylib -load-plugin-library $PLUGINS_DIR/libSwiftUIMacros.dylib -load-plugin-library $PLUGINS_DIR/libSwiftDataMacros.dylib -load-plugin-library $PLUGINS_DIR/libStateReportingMacros.dylib"
                # Workaround for Xcode Tools bug with MacOS 27 SDK: add explicit `-load-plugin-library`s.
                # See https://github.com/drumih/turbo-fieldfare/issues/185

                mkdir -p "$out/Applications"
                cp -R "build/Build/Products/Release/${appName}.app" "$out/Applications/"

                app="$out/Applications/${appName}.app"
                plist="$app/Contents/Info.plist"

                echo "✏️ Setting up environment variables"

                /usr/libexec/PlistBuddy -c 'Add :LSEnvironment dict'                                       "$plist" 2>/dev/null || true
                /usr/libexec/PlistBuddy -c 'Add :LSEnvironment:IINA_EXECUTABLE string "@executable_path"'  "$plist" 2>/dev/null || true
                /usr/libexec/PlistBuddy -c 'Set :LSEnvironment:IINA_EXECUTABLE        "@executable_path"'  "$plist"
                # Overwrite Git info from build (which were set to placeholders because Xcode script could not determine them at build time)
                /usr/libexec/PlistBuddy -c "Set :com.colliderli.iina.build.commit     $git_rev"            "$plist"
                /usr/libexec/PlistBuddy -c "Set :com.colliderli.iina.build.branch     $git_branch"         "$plist"

                echo "🔏 Re-signing ${appName}.app..."
                ${resign}/bin/iina-resign "$app"

                echo "📦 Copying includes to output dir"
                mkdir -p "$out"
                cp -RLv deps/include $out/include

                app_real=$(realpath "$app" 2>/dev/null || echo "$app")
                echo "✅✅ Done! Universal ${appName}.app is ready at $app_real"
              '';

            }; # END iina-universal

            default = packages.iina-universal;
          }; # END packages

        in
        packages
      ); # END perSystemPackages
    in
    {
      inherit systemNames;
      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-tree;
      packages = nixpkgs.lib.genAttrs systemNames (systemName: (perSystemPackages.${systemName}));
      singleArchDeps = builtins.map (systemName: self.packages.${systemName}.deps) systemNames;
    };
}
