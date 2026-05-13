{
  description = "IINA – The modern video player for macOS.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs =
    { self, nixpkgs }:
    let
      appName = "IINA";

      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      perSystem = nixpkgs.lib.genAttrs systems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };

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
            propagatedBuildInputs = [ pkgs.python3 ];
            dontUnpack = true;
            installPhase = "install -Dm755 ${./other/lib_tool.py} $out/bin/iina-lib-tool";
          };

          # Pull system's xcode in
          xcode = pkgs.runCommand "system-xcode" { } ''
            mkdir -p "$out/bin"
            ln -sf /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild "$out/bin/xcodebuild"
          '';

          # Override ffmpeg to use our version of libs
          ffmpeg = (pkgs.ffmpeg.override {
            withSoxr = true;
            soxr = pkgs.soxr;

            withBs2b = true;
            libbs2b = pkgs.libbs2b;

            withRubberband = true;
            rubberband = pkgs.rubberband;

            withPlacebo = true;
            libplacebo = pkgs.libplacebo;

            withJxl = true;
            libjxl = pkgs.libjxl;
          }).overrideAttrs (_: {
            # Skip tests to speed up build
            doCheck = false;
            });

          # Override mpv with desired features support
          mpv = pkgs.mpv-unwrapped.override {
            ffmpeg = ffmpeg;
            lua = pkgs.luajit;

            # Enable features we want
            vapoursynthSupport = false;
            javascriptSupport = true;
            cmsSupport = true;
            rubberbandSupport = true;
            archiveSupport = true;
            bluraySupport = true;
            openalSupport = true;
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
          };

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
                  ffmpeg
                  mpv
                  (pkgs.libhwy.overrideAttrs (old: {
                    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DBUILD_SHARED_LIBS=ON" ];
                  }))
                  pkgs.brotli
                  pkgs.dav1d
                  pkgs.fontconfig
                  pkgs.freetype
                  pkgs.fribidi
                  pkgs.gettext
                  pkgs.glib
                  pkgs.gmp
                  pkgs.gnutls
                  pkgs.graphite2
                  pkgs.harfbuzz
                  pkgs.lcms2
                  pkgs.libarchive
                  pkgs.libass
                  pkgs.libb2
                  pkgs.libbluray
                  pkgs.libbs2b
                  pkgs.libidn2
                  pkgs.libjpeg_turbo
                  pkgs.libjxl
                  pkgs.libplacebo
                  pkgs.libpng
                  pkgs.libsamplerate
                  pkgs.libsodium
                  pkgs.libtasn1
                  pkgs.libuchardet
                  pkgs.libunibreak
                  pkgs.libunistring
                  pkgs.libwebp
                  pkgs.luajit
                  pkgs.lz4
                  pkgs.mujs
                  pkgs.nettle
                  pkgs.p11-kit
                  pkgs.pcre2
                  pkgs.python3
                  pkgs.rubberband
                  pkgs.shaderc
                  pkgs.snappy
                  pkgs.soxr
                  pkgs.speex
                  pkgs.vid-stab
                  pkgs.vulkan-loader
                  pkgs.xorg.libX11
                  pkgs.xorg.libXau
                  pkgs.xorg.libxcb
                  pkgs.xorg.libXdmcp
                  pkgs.xz
                  pkgs.zeromq
                  pkgs.zimg
                  pkgs.zstd

                  # Indirect libs
                  pkgs.bzip2
                  pkgs.expat
                  pkgs.lame
                  pkgs.libaom
                  pkgs.libcaca
                  pkgs.libcxx
                  pkgs.libdovi
                  pkgs.libdvdcss
                  pkgs.libdvdnav
                  pkgs.libffi
                  pkgs.libogg
                  pkgs.libopenmpt
                  pkgs.libopus
                  pkgs.librist
                  pkgs.libssh
                  pkgs.libtheora
                  pkgs.libvdpau
                  pkgs.libvmaf
                  pkgs.libvorbis
                  pkgs.libxml2
                  pkgs.llvmPackages.openmp
                  pkgs.ocl-icd
                  pkgs.openal
                  pkgs.openjpeg
                  pkgs.SDL2
                  pkgs.sdl3
                  pkgs.srt
                  pkgs.svt-av1
                  pkgs.x264
                  pkgs.x265
                  pkgs.zlib
                  pkgs.zstd.out
                  pkgs.zvbi
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

              mkdir -p .spm .spm-cache build

              xcodebuild \
                -workspace iina.xcodeproj/project.xcworkspace \
                -scheme iina \
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
        in
        rec {
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
                echo "Git bramch: $git_branch, revision: $git_rev"
                export HOME=$PWD/.home
                export CFFIXED_USER_HOME="$HOME"
                export __XPC_CFFIXED_USER_HOME="$HOME"
                export TMPDIR="$PWD/.tmp"; mkdir -p "$TMPDIR"
                export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

                APPLE_BIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
                export PATH="$APPLE_BIN:$DEVELOPER_DIR/usr/bin:/usr/bin:/bin"

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
                cp -RL ${depsInclude}/.           deps/include
                cp -RL ${depsLib}/.               deps/lib

                echo "[${system}] 📦 Copying SPM deps"
                rsync -a ${spmDeps}/ ./
                chmod -R u+rwx,g+rx,o+rx .

                echo "[${system}] 📦 Adding canonical links"
                ${libTool}/bin/iina-lib-tool --add-canonical-links "./deps/lib" "./deps/executable"

                # Rewrite SwiftPM workspace-state.json to fix absolute paths
                if [ -f .spm/workspace-state.json ]; then
                  old_prefix=$(grep -Eo "/nix/var/nix/builds/nix-[^/]+/source" .spm/workspace-state.json | head -n1)
                  echo "Patching workspace-state.json: replacing $old_prefix → $PWD"
                  sed -i -E "s|$old_prefix|$PWD|g" .spm/workspace-state.json
                fi

                # Build IINA
                echo "[${system}] 🔨 Building ${appName}"
                xcodebuild \
                  -workspace iina.xcodeproj/project.xcworkspace \
                  -scheme iina \
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
                ${libTool}/bin/iina-lib-tool --canonicalize --purge "$frameworks" "$macos"

                echo "[${system}] ✏️ Setting up environment variables"

                /usr/libexec/PlistBuddy -c 'Add :LSEnvironment dict'                                          "$plist" 2>/dev/null || true
                /usr/libexec/PlistBuddy -c 'Add :LSEnvironment:IINA_EXECUTABLE    string "@executable_path"'  "$plist" 2>/dev/null || true
                /usr/libexec/PlistBuddy -c 'Set :LSEnvironment:IINA_EXECUTABLE           "@executable_path"'  "$plist"
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

                ${libTool}/bin/iina-lib-tool --merge-architectures "$frameworks" "$app/Contents/MacOS" \
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
                    echo "⚠️  $link exists and is not a symlink; leaving it untouched."
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
    in
    {
      inherit systems;

      packages = nixpkgs.lib.genAttrs systems (system: (perSystem.${system}).packages);

      devShells = nixpkgs.lib.genAttrs systems (system: (perSystem.${system}).devShells);

      archApps = builtins.map (system: self.packages.${system}.iina) systems;
    };
}
