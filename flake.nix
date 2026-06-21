{
  description = "IINA – The modern video player for macOS.";

  # Nix Packages has adopted Apple's perceived macOS support policy of only supporting the latest 3
  # versions. Also of concern, Nixpkgs 26.05 is the last release that supports Intel Macs. Rather
  # than applying overrides to newer versions of Nix packages to lower the minimum supported macOS
  # version, this flake uses nixpkgs 25.05 (supports macOS 11.3+) and applies overrides to upgrade
  # packages to newer versions.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }: let
    appName = "IINA";

    systems = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];

    perSystem = nixpkgs.lib.genAttrs systems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
        };

        resign = pkgs.writeShellApplication {
          name = "iina-resign";
          runtimeInputs = [ pkgs.findutils pkgs.coreutils ];
          text = ''
            set -euo pipefail
            app="$1"

            find "$app" -type d -exec chmod u+rwx {} \;
            find "$app" -type f -exec chmod u+rw  {} \;
            find "$app/Contents/MacOS" -type f -perm -111 -exec chmod u+rw {} \;

            /usr/bin/codesign --force --deep --sign - "$app"
          '';
        };

        libTool = pkgs.stdenv.mkDerivation {
          pname = "iina-lib-tool";
          version = "1.0";
          propagatedBuildInputs = [
            (pkgs.python3.withPackages (pythonPackages: with pythonPackages; [
              packaging
            ]))
          ];
          dontUnpack = true;
          installPhase = "install -Dm755 ${./other/lib_tool.py} $out/bin/iina-lib-tool";
        };

        # Pull system's xcode in
        xcode = pkgs.runCommand "system-xcode" { } ''
          mkdir -p "$out/bin"
          ln -sf /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild "$out/bin/xcodebuild"
        '';

        # FFmpeg 8 must be built with a newer version of nasm than provided by nixpkgs 25.05.
        # Rather than build a newer version of this tool, pull in the system's version.
        nasm = pkgs.runCommand "system-nasm" { } ''
          mkdir -p "$out/bin"
          ln -sf /opt/homebrew/bin/nasm "$out/bin/nasm"
        '';

        # Upgrade to the version supplied by nixpkgs 26.05.
        dav1d = pkgs.dav1d.overrideAttrs (finalAttrs: previousAttrs: {
          version = "1.5.3";
          src = pkgs.fetchFromGitHub {
            owner = "videolan";
            repo = "dav1d";
            rev = finalAttrs.version;
            hash = "sha256-E3da/LJ8HNy1osExmupovqnL8JHgVNzPUCG5F8TJKXQ=";
          };
        });

        # Upgrade to the version supplied by nixpkgs 26.05.
        expat = pkgs.expat.overrideAttrs (finalAttrs: previousAttrs: {
          version = "2.8.0";
          tag = "R_${pkgs.lib.replaceStrings [ "." ] [ "_" ] finalAttrs.version}";
          src = pkgs.fetchurl {
            url = "https://github.com/libexpat/libexpat/releases/download/${finalAttrs.tag}/${finalAttrs.pname}-${finalAttrs.version}.tar.xz";
            hash = "sha256-o3v64KqXdb2FIevYXcRW1Ibw/zETj2yR/ZAupzJiRUI=";
          };
        });

        # Upgrade to the version supplied by nixpkgs 26.05.
        fontconfig = (pkgs.fontconfig.override {
          expat = expat;
          freetype = freetype;
        }).overrideAttrs (finalAttrs: previousAttrs: {
          version = "2.17.1";
          src = pkgs.fetchurl {
            url = "https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/${finalAttrs.version}/fontconfig-${finalAttrs.version}.tar.xz";
            hash = "sha256-n1yuk/T//B+8Ba6ZzfxwjNYN/WYS/8BRKCcCXAJvpUE=";
          };
        });

        # Upgrade to the version supplied by nixpkgs 26.05.
        freetype = pkgs.freetype.overrideAttrs (finalAttrs: previousAttrs: {
          version = "2.14.2";
          src = pkgs.fetchurl {
            url = "mirror://savannah/freetype/freetype-${finalAttrs.version}.tar.xz";
            sha256 = "sha256-S2Lcq0ySChqGA2mTMiGBQ2LmmeJvVXklFtZx5v9VteE=";
          };
        });

        # Upgrade to the version supplied by nixpkgs 25.11.
        harfbuzz = (pkgs.harfbuzz.override {
          freetype = freetype;
        }).overrideAttrs (finalAttrs: previousAttrs: {
          version = "12.1.0";
          src = pkgs.fetchurl {
            url = "https://github.com/harfbuzz/harfbuzz/releases/download/${finalAttrs.version}/harfbuzz-${finalAttrs.version}.tar.xz";
            hash = "sha256-5cgbf24LEC37AAz6QkU4uOiWq3ii9Lil7IyuYqtDNp4=";
          };
        });

        # Upgrade to the version supplied by nixpkgs 26.05.
        libass = (pkgs.libass.override {
          fontconfigSupport = true;
          fontconfig = fontconfig;
          freetype = freetype;
          harfbuzz = harfbuzz;
        }).overrideAttrs (finalAttrs: previousAttrs: {
          version = "0.17.4";
          src = pkgs.fetchurl {
            url = "https://github.com/libass/libass/releases/download/${finalAttrs.version}/libass-${finalAttrs.version}.tar.xz";
            hash = "sha256-ePEXm4ONAl6cJuj+8z+AkvZWEURP+hv8DPrGozURoFo=";
          };
          enableParallelBuilding = true;
          nativeBuildInputs = previousAttrs.nativeBuildInputs ++ [nasm];
        });

        # Must use the upgraded fontconfig.
        libbluray = (pkgs.libbluray.override {
          fontconfig = fontconfig;
        }).overrideAttrs (finalAttrs: previousAttrs: {
          enableParallelBuilding = true;
        });

        # Upgrade to the version supplied by nixpkgs 26.05.
        libjxl = pkgs.libjxl.overrideAttrs (finalAttrs: previousAttrs: {
          version = "0.11.2";
          src = pkgs.fetchFromGitHub {
            owner = "libjxl";
            repo = "libjxl";
            tag = "v${finalAttrs.version}";
            hash = "sha256-L4/BY68ZBCpebQxryR7D1CxrsneYvw8B8EvW2mkF7bA=";
            # There are various submodules in `third_party/`.
            fetchSubmodules = true;
          };
        });

        # Upgrade to the version supplied by nixpkgs 26.05.
        svt-av1 = pkgs.svt-av1.overrideAttrs (finalAttrs: previousAttrs: {
          version = "3.1.2";
          src = pkgs.fetchFromGitLab {
            owner = "AOMediaCodec";
            repo = "SVT-AV1";
            rev = "v${finalAttrs.version}";
            hash = "sha256-/CpcxdyC4qf9wdzzySMYw17FbjYpasT+QVykXSlx28U=";
          };
        });

        ffmpeg = (pkgs.ffmpeg-headless.override {
          # Upgrade to FFmpeg 8.1.1 as nixpkgs 25.05 provides FFmpeg 7.1.1.
          version = "8.1.1";
          hash = "sha256-WPGfjTZjsgpR5QiANRWF4g6LF2ejGzFQUrLjhzw9cfQ=";

          withDebug = false;      # Build using debug options
          withStripping = false;  # Strip symbols from the resulting binaries to reduce size
          withSmallDeps  = true;

          withAss = true;         # (Advanced) SubStation Alpha subtitle rendering
          libass = libass;

          withBluray = true;
          libbluray = libbluray;

          withDav1d = true;       # AV1 decoder (focused on speed and correctness)
          dav1d = dav1d;

          withFontconfig = true;
          fontconfig = fontconfig;

          withFreetype = true;
          freetype = freetype;

          withHarfbuzz = true;
          harfbuzz = harfbuzz;

          withSoxr = true;
          soxr = pkgs.soxr;

          withSvtav1 = true;      # SVT-AV1 encoder, used for screenshots in AVIF format
          svt-av1 = svt-av1;

          withRubberband = true;
          rubberband = pkgs.rubberband;

          withJxl = true;
          libjxl = libjxl;

          withGnutls = true;

          # May want to enable some of these in the near future
          withOpenjpeg = false;   # JPEG 2000 de/encoder
          withTheora = false;     # Theora video codec, not included in IINA historically
          withVorbis = false;     # Vorbis audio codec, not included in IINA historically

          withXml2 = false;       # Crashing due to missing library without this.

          withX264 = false;      # H.264 video encoder, not super useful for IINA (& adds >4 MB to app size)
          withX265 = false;      # H.265 video encoder, not super useful for IINA (& adds >31 MB to app size)
          withAom = false;       # AV1 video encoder, IINA prefers SVT-AV1 (better performance)
          withBs2b = false;      # Bass to Binaural audio filter (uncommon)
          withCaca = false;      # ASCII art video output, not used by IINA
          withDvdnav = false;
          withDvdread = false;
          withMp3lame = false;   # MP3 LAME audio codec encoder, not super useful for IINA
          withOpenmpt = false;   # Tracker music files decoder (various formats), not included in IINA historically
          withOpus = false;      # Opus audio codec, not included in IINA historically
          withPlacebo = false;
          withRist = false;      # RIST protocol support, not used by IINA (yet?)
          withSrt = false;       # Secure Reliable Transport (SRT) protocol, not used by IINA
          withSsh = false;       # SFTP protocol support, not used by IINA
          withVidStab = false;   # Video stabilization filter, requires Linux
          withVmaf = false;      # Video quality measurement tool, not used by IINA
          withVulkan = false;    # IINA can't use gpu-next yet
          withZmq = false;       # ZeroMQ messaging library for FFmpeg streaming; not used by mpv or IINA
          withZvbi = false;      # Teletext support, not used by IINA

          # Unlikely to ever enable these
          withOpencl = false;    # Vulkan predecessor, not supported on modern macOS
          withVdpau = false;     # nVidia HW acceleration, not supported on modern macOS
          withXlib = false;      # X11 support, no longer supported on modern OSes
          withXcb = false;       # X11
          withXcbxfixes = false; # X11
          withXcbShape = false;  # X11
          withXcbShm = false;    # X11

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

        }).overrideAttrs (old: {
          # The postproc configure flag was removed in FFmpeg 8.
          configureFlags = builtins.filter(x: x != "--enable-postproc") old.configureFlags;
          # Skip tests to speed up build
          doCheck = false;
          nativeBuildInputs = old.nativeBuildInputs ++ [nasm];
        });

        # The upgraded mpv requires a newer version of libplacebo than provided by nixpkgs 25.05.
        libplacebo = pkgs.libplacebo.overrideAttrs (finalAttrs: {
          version = "7.351.0";
          src = pkgs.fetchFromGitLab {
            domain = "code.videolan.org";
            owner = "videolan";
            repo = "libplacebo";
            rev = "v${finalAttrs.version}";
            hash = "sha256-ccoEFpp6tOFdrfMyE0JNKKMAdN4Q95tP7j7vzUj+lSQ=";
          };
        });

        mpv = (pkgs.mpv-unwrapped.override {
          ffmpeg = ffmpeg;
          freetype = freetype;
          libass = libass;
          libbluray = libbluray;
          libplacebo = libplacebo;
          lua = pkgs.luajit;

          archiveSupport = true;
          bs2bSupport = false;
          bluraySupport = true;
          cacaSupport = false;
          cmsSupport = true;
          dvdnavSupport = false;
          javascriptSupport = true;
          openalSupport = false;
          rubberbandSupport = true;
          vapoursynthSupport = false;
          vulkanSupport = false;
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
        }).overrideAttrs (finalAttrs: previousAttrs: {
          # Upgrade to mpv 0.41.0 as nixpkgs 25.05 provides mpv 0.40.0.
          version = "v0.41.0";
          src = pkgs.fetchFromGitHub {
            owner = "mpv-player";
            repo = "mpv";
            tag = "v${finalAttrs:version}";
            hash = "sha256-gJWqfvPE6xOKlgj2MzZgXiyOKxksJlY/tL6T/BeG19c=";
          };
          # The mpv package in nixpkgs 25.05 passes a sdl2 option to meson that is not present in
          # mpv 0.41.0. Disable the building of man pages to speed up the build.
          mesonFlags = builtins.filter(x: x != "-Dsdl2=disabled") previousAttrs.mesonFlags
            ++ ["-Dmanpage-build=disabled"];
          # Disabling building of man pages requires the package outputs be adjusted accordingly.
          outputs = builtins.filter(x: x != "man") previousAttrs.outputs;
          patches =
            []
            # If needed include the fix for IINA issue #5956, the mpv regression described in mpv
            # issue #17436 and fixed in mpv PR #17448. The fix is expected to be included in
            # mpv 0.42.0.
            ++ pkgs.lib.optionals (pkgs.lib.versionAtLeast finalAttrs.version "v0.40.0"
                && pkgs.lib.versionOlder finalAttrs.version "v0.42.0") [
              (pkgs.fetchpatch2 {
                url = "https://github.com/mpv-player/mpv/pull/17448.patch";
                hash = "sha256-kXnlu8SJ/GEnFljnXK4ri6CrgDBXvOTjnQo3jdPAbSA=";
              })
            ];
        });

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
        ];

        libhwy = pkgs.libhwy.overrideAttrs (old: {
          cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DBUILD_SHARED_LIBS=ON" ];
        });

        # Collect lib deps as per readme.md
        depsLib = pkgs.linkFarm "iina-deps-lib" (
          pkgs.lib.flatten (
            map (
              pkg: let
                libdir = "${pkgs.lib.getLib pkg}/lib";
              in
              builtins.map (file: {
                name = baseNameOf file;
                path = "${libdir}/${file}";
              }) (builtins.attrNames (builtins.readDir libdir))
            ) [
              dav1d               # AV1 video decoder
              ffmpeg
              fontconfig          # Font configuration library
              freetype            # FreeType font rendering engine
              harfbuzz            # Text shaping engine. Used by avdevice, avfilter, ass
              libass              # ASS subtitle renderer
              libbluray           # Blu-ray support
              libhwy
              libjxl              # JPEG-XL support
              libplacebo          # Required by mpv
              mpv
              pkgs.brotli         # Brotli compression. Used for ass, fontconfig, bluray, & more
              pkgs.fribidi        # Hebrew and Arabic support
              pkgs.gettext        # Internationalization library
              pkgs.glib           # GTK GLib utility library. Required by harfbuzz
              pkgs.gmp            # Provides arbitrary precision arithmetic. Required by several libs
              pkgs.gnutls         # TLS support, needed for network streams
              pkgs.graphite2      # Compiles Graphite-enabled fonts. Used by harfbuzz
              pkgs.lcms2          # Little CMS color management lib. Required by placebo, jxl
              pkgs.libarchive     # Archive support
              pkgs.libb2          # BLAKE2 hashing library
              pkgs.libidn2        # Converts between ASCII & UTF domain names. Used by gnutls
              pkgs.libjpeg_turbo  # Needed to provide libjpeg
              pkgs.libpng         # PNG image format support
              pkgs.libsamplerate  # Sample Rate Converter for audio
              pkgs.libtasn1       # ASN.1 library used by GnuTLS, p11-kit
              pkgs.libuchardet    # Character encoding detection library
              pkgs.libunibreak    # Unicode line breaking & word/grapheme breaking
              pkgs.libunistring   # Unicode string handling
              pkgs.libwebp        # WebP image de/encoder
              pkgs.luajit         # Lua Just-In-Time compiler. Required by mpv
              pkgs.lz4            # LZ4 compression. Used by libarchive
              pkgs.mujs           # JavaScript engine. Needed for mpv's JS support
              pkgs.nettle         # GnuTLS dependency (cryptographic algorithms)
              pkgs.p11-kit        # Tools for managing PKCS#11 modules (crypto keys / tokens)
              pkgs.pcre2          # Perl-compatible regular expression pattern matching
              pkgs.rubberband     # Enables FFmpeg to perform audio tempo & pitch modifications
              pkgs.shaderc        # Referenced by libplacebo, despite requiring Vulkan which IINA doesn't use
              pkgs.snappy         # Snappy compression
              pkgs.soxr           # SoX Resampler, needed for high-quality audio resampling
              pkgs.speex          # Used by avcodec, avdevice, avfilter, avformat
              pkgs.xz             # LZMA2 compression, needed by libarchive
              pkgs.zimg           # Image scaling & colorspace conversion library, needed by mpv
              pkgs.zstd           # Needed by libarchive

              # Indirect libs
              pkgs.libcxx         # C standard library
              pkgs.libdovi        # Dolby Vision, needed by libplacebo
            ]
          )
        );

        # Collect SwiftPM deps as separate derivation for them to be cached
        spmDeps = pkgs.stdenv.mkDerivation {
          pname = "iina-spm-deps";
          version = "${self.shortRev or self.dirtyShortRev}";

          # Only include SwiftPM-related files as input
          src = pkgs.lib.cleanSourceWith {
            src = ./.;
            filter =
              path: type:
              let
                relPath = pkgs.lib.removePrefix (toString ./. + "/") (toString path);
              in
              pkgs.lib.hasSuffix "Package.resolved" relPath
              || pkgs.lib.hasSuffix "Package.swift" relPath
              || pkgs.lib.hasPrefix "iina.xcodeproj" relPath;
          };

          dontFixup = true;

          nativeBuildInputs = [
            xcode
          ];

          buildPhase = ''
            export HOME=$PWD/.home
            export CFFIXED_USER_HOME="$HOME"
            export __XPC_CFFIXED_USER_HOME="$HOME"
            export TMPDIR="$PWD/.tmp"; mkdir -p "$TMPDIR"
            export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

            APPLE_BIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
            export PATH="$APPLE_BIN:$DEVELOPER_DIR/usr/bin:/usr/bin:/bin"

            export TOOLCHAINS=XcodeDefault
            export SDKROOT=macosx

            if [ "$system" == "aarch64-darwin" ]; then
              export XCODE_BUILD_DESTINATION='platform=macOS,arch=arm64'
            else
              export XCODE_BUILD_DESTINATION='platform=macOS,arch=x86_64'
            fi

            mkdir -p .spm .spm-cache build

            xcodebuild \
              -workspace iina.xcodeproj/project.xcworkspace \
              -scheme iina \
              -destination "$XCODE_BUILD_DESTINATION" \
              -resolvePackageDependencies \
              -derivedDataPath "$PWD/build" \
              -clonedSourcePackagesDirPath "$PWD/.spm" \
              -packageCachePath "$PWD/.spm-cache" \
              -disablePackageRepositoryCache \
              -IDEPackageSupportDisableManifestSandbox=YES \
              -IDEPackageSupportDisablePluginExecutionSandbox=YES \
              ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES \
              SWIFT_ENABLE_EXPLICIT_MODULES=NO
          '';

          # Copy everything — keep full structure (SPM state, caches, workspace, etc.)
          installPhase = ''
            mkdir -p $out
            cp -R . $out/
          '';
        };

      in rec {
        packages = rec {

          iina = pkgs.stdenv.mkDerivation {
            pname = "iina";
            version = "${self.shortRev or self.dirtyShortRev}";

            src = pkgs.nix-gitignore.gitignoreSource [ "flake.nix" "flake.lock" ] ./.;

            strictDeps = true;

            nativeBuildInputs = [
              pkgs.coreutils
              xcode
              libTool
              pkgs.rsync
              pkgs.gnused
            ];

            buildInputs = [
              spmDeps
            ];

            buildPhase = ''
              echo "[${system}] 🔧 Setting up build environment for ${appName}"
              git_rev="${self.rev or self.dirtyRev}"
              # Nix flakes cannot currently access branch info. Doing so may violate the stated goal of maximum
              # reproducibility, as the same git revision can be associated with an arbitrary number of branches.
              # Just use a placeholder for now:
              git_branch="<nix-build>"
              echo "Git branch: $git_branch, revision: $git_rev"
              export HOME=$PWD/.home
              export CFFIXED_USER_HOME="$HOME"
              export __XPC_CFFIXED_USER_HOME="$HOME"
              export TMPDIR="$PWD/.tmp"; mkdir -p "$TMPDIR"
              export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

              APPLE_BIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
              export PATH="$APPLE_BIN:$DEVELOPER_DIR/usr/bin:/usr/bin:/bin"

              if [ "$system" == "aarch64-darwin" ]; then
                export XCODE_BUILD_DESTINATION='platform=macOS,arch=arm64'
              else
                export XCODE_BUILD_DESTINATION='platform=macOS,arch=x86_64'
              fi

              unset CC CXX LD AR RANLIB NM STRIP OBJCOPY \
                CFLAGS CXXFLAGS LDFLAGS SDKROOT CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH \
                NIX_CFLAGS_COMPILE NIX_CFLAGS_LINK PKG_CONFIG_PATH

              export TOOLCHAINS=XcodeDefault
              export SDKROOT=macosx

              echo "Using $TOOLCHAINS toolchain"
              echo "Using $SDKROOT sdk"

              echo "[${system}] 📦 Copying external deps"
              mkdir -p deps
              rm -rf deps/include deps/lib

              mkdir -p deps/include deps/lib deps/executable
              cp -RL "${depsInclude}/" deps/include
              cp -RLv "${depsLib}/" deps/lib

              echo "[${system}] 📦 Copying SPM deps"
              rsync -a "${spmDeps}/" ./
              chmod -R u+rwx,g+rx,o+rx .

              echo "[${system}] 📦 Canonicalizing libs"
              ${libTool}/bin/iina-lib-tool --canonicalize --prune "./deps/lib" "./deps/executable"

              # Rewrite SwiftPM workspace-state.json to fix absolute paths
              if [ -f .spm/workspace-state.json ]; then
                old_prefix=$(grep -Eo "/nix/var/nix/builds/nix-[^/]+/source" .spm/workspace-state.json | head -n1)
                echo "Patching workspace-state.json: replacing $old_prefix → $PWD"
                sed -i -E "s|$old_prefix|$PWD|g" .spm/workspace-state.json
              fi

              # Build IINA (single-arch)
              echo "[${system}] 🔨 Building ${appName}"
              xcodebuild \
                -workspace iina.xcodeproj/project.xcworkspace \
                -scheme iina \
                -destination "$XCODE_BUILD_DESTINATION" \
                -configuration Release \
                -sdk macosx \
                -skipPackagePluginValidation \
                -derivedDataPath "$PWD/build" \
                -clonedSourcePackagesDirPath "$PWD/.spm" \
                -packageCachePath "$PWD/.spm-cache" \
                -disablePackageRepositoryCache \
                -disableAutomaticPackageResolution \
                -onlyUsePackageVersionsFromResolvedFile \
                -IDEPackageSupportDisableManifestSandbox=YES \
                -IDEPackageSupportDisablePluginExecutionSandbox=YES \
                ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES \
                SWIFT_ENABLE_EXPLICIT_MODULES=NO \
                CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
            '';

            installPhase = ''
              mkdir -p "$out/Applications"
              cp -R "build/Build/Products/Release/${appName}.app" "$out/Applications/"
            '';

            preFixup = ''
              export PATH=${pkgs.coreutils}/bin:$PATH
            '';

            postFixup = ''
              app="$out/Applications/${appName}.app"
              macos="$app/Contents/MacOS"
              frameworks="$app/Contents/Frameworks"
              plist="$app/Contents/Info.plist"

              mkdir -p "$frameworks"

              echo "[${system}] 📦 Deep-bundling dynamic dependencies into ${appName}.app"
              ${libTool}/bin/iina-lib-tool --canonicalize "$frameworks" "$macos"

              echo "[${system}] ✏️ Setting up environment variables"

              /usr/libexec/PlistBuddy -c 'Add :LSEnvironment dict'                                       "$plist" 2>/dev/null || true
              /usr/libexec/PlistBuddy -c 'Add :LSEnvironment:IINA_EXECUTABLE string "@executable_path"'  "$plist" 2>/dev/null || true
              /usr/libexec/PlistBuddy -c 'Set :LSEnvironment:IINA_EXECUTABLE        "@executable_path"'  "$plist"
              # Overwrite Git info from build (which were set to placeholders because Xcode script could not determine them at build time)
              /usr/libexec/PlistBuddy -c "Set :com.colliderli.iina.build.commit        $git_rev"            "$plist"
              /usr/libexec/PlistBuddy -c "Set :com.colliderli.iina.build.branch        $git_branch"         "$plist"

              # echo "[${system}] 🔏 Re-signing ${appName}.app..."
              # ${resign}/bin/iina-resign "$app"
            '';
          };

          # --- IINA Universal ---
          iina-universal = pkgs.stdenv.mkDerivation {
            pname = "iina-universal";
            version = "${self.shortRev or self.dirtyShortRev}";

            nativeBuildInputs = [
              libTool
              pkgs.rsync
              pkgs.coreutils
            ];

            buildCommand = ''
              app="$out/Applications/${appName}.app"
              frameworks="$app/Contents/Frameworks"

              export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
              APPLE_BIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
              export PATH="$APPLE_BIN:$DEVELOPER_DIR/usr/bin:/usr/bin:/bin"

              echo "📦 Combining universal ${appName}.app"

              mkdir -p "$out/Applications"
              # copy the contents of the source app into the target dir
              ${pkgs.rsync}/bin/rsync -a "${builtins.elemAt self.archApps 0}/Applications/${appName}.app/" "$app/"
              chmod -R u+w "$app"

              archroot0="${builtins.elemAt self.archApps 0}/Applications/${appName}.app"
              archroot1="${builtins.elemAt self.archApps 1}/Applications/${appName}.app"

              ${libTool}/bin/iina-lib-tool --merge-architectures --canonicalize "$frameworks" "$app/Contents/MacOS" \
                --archroot0 "$archroot0" --archroot1 "$archroot1"

              echo "🔏 Re-signing ${appName}.app..."
              ${resign}/bin/iina-resign "$app"

              echo "[${system}] 📦 Copying include dir"
              mkdir -p "$out/include"
              cp -RL ${depsInclude}/. $out/include

              app_real=$(realpath "$app" 2>/dev/null || echo "$app")
              echo "✅✅ Done! Universal ${appName}.app is ready at $app_real"
            '';

            preFixup = ''
              export PATH=${pkgs.coreutils}/bin:$PATH
            '';
          };

          default = iina-universal;
        };

        devShells = {
          default = pkgs.mkShell {
            packages = [
              xcode
              pkgs.rsync
              pkgs.gnused
              pkgs.gnugrep
              pkgs.coreutils
            ];

            shellHook = ''
              set -euo pipefail

              export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

              deps_root="$PWD/deps"
              mkdir -p "$deps_root"

              link_tree() {
                local target="$1"
                local link="$2"

                if [ -e "$link" ] && [ ! -L "$link" ]; then
                  echo "⚠️ $link exists and is not a symlink; leaving it untouched."
                  return
                fi

                ln -sfn "$target" "$link"
              }

              link_tree ${depsInclude} "$deps_root/include"
              link_tree ${depsLib} "$deps_root/lib"

              echo "📦 Syncing SwiftPM deps"
              rsync -a --chmod=Du+rwx,Fu+rw ${spmDeps}/ ./

              if [ -f .spm/workspace-state.json ]; then
                chmod u+w .spm/workspace-state.json 2>/dev/null || true
                old_prefix=$(grep -Eo "/nix/var/nix/builds/nix-[^/]+/source" .spm/workspace-state.json | head -n1)
                if [ -n "$old_prefix" ]; then
                  sed -i -E "s|$old_prefix|$PWD|g" .spm/workspace-state.json
                fi
              fi
            '';
          };
        };
      }
    );
  in {
    inherit systems;

    packages = nixpkgs.lib.genAttrs systems (system: (perSystem.${system}).packages);

    devShells = nixpkgs.lib.genAttrs systems (system: (perSystem.${system}).devShells);

    archApps = builtins.map (system: self.packages.${system}.iina) systems;
  };
}
