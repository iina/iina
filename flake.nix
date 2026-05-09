{
  description = "IINA – The modern video player for macOS.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs =
    { self, nixpkgs }:
    let
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

            propagatedBuildInputs = [
            (pkgs.python3.withPackages (pythonPackages: with pythonPackages; [
              # Add Python packages here
            ]))];

            dontUnpack = true;
            installPhase = "install -Dm755 ${./other/lib_tool.py} $out/bin/iina-lib-tool";
          };

          # Pull system's xcode in
          xcode = pkgs.runCommand "system-xcode" { } ''
            mkdir -p $out/bin
            ln -sf /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild $out/bin/xcodebuild
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

          # Collect executables to expose them for plugins
          depsExecutable = pkgs.linkFarm "iina-deps-executable" (
            pkgs.lib.flatten (
              map
                (
                  pkg:
                  let
                    bindir = "${pkgs.lib.getBin pkg}/bin";
                  in
                  builtins.map (file: {
                    name = baseNameOf file;
                    path = "${bindir}/${file}";
                  }) (builtins.attrNames (builtins.readDir bindir))
                )
                [
                  ffmpeg
                  # Grab the real mpv binary instead of the /bin wrapper script
                  (pkgs.runCommand "iina-mpv-executable" { } ''
                    mkdir -p $out/bin
                    cp -p ${mpv}/Applications/mpv.app/Contents/MacOS/mpv $out/bin/mpv
                  '')
                  pkgs.yt-dlp
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
              pkgs.git
              pkgs.gnused
              pkgs.unzip
              pkgs.zip
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
                pkgs.git
                pkgs.gnused
                pkgs.unzip
                pkgs.zip
              ];

              buildInputs = [
                spmDeps
                pkgs.yt-dlp
              ];

              buildPhase = ''
                echo "[${system}] 🔧 Setting up build environment"
                git_rev="${self.rev or self.dirtyRev}"
                git_branch="???"  # FIXME: Find way to get the actual git branch
                echo "Git revision: $git_rev"
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
                cp -RL ${depsExecutable}/.        deps/executable/

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
                echo "[${system}] 🔨 Building IINA"
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
                mkdir -p $out/Applications
                cp -R build/Build/Products/Release/IINA.app $out/Applications/
              '';

              preFixup = ''
                export PATH=${pkgs.coreutils}/bin:$PATH
              '';

              postFixup = ''
                app="$out/Applications/IINA.app"
                macos="$app/Contents/MacOS"
                frameworks="$app/Contents/Frameworks"
                plist="$app/Contents/Info.plist"

                mkdir -p "$frameworks"

                echo "[${system}] 📦 Bundling ${depsExecutable} into IINA.app"
                cp -RL ${depsExecutable}/. "$macos/"

                echo "[${system}] 📦 Deep-bundling dynamic dependencies into IINA.app"
                ${libTool}/bin/iina-lib-tool --canonicalize --purge "$frameworks" "$macos"

                echo "[${system}] ✏️ Setting up environment variables"

                /usr/libexec/PlistBuddy -c 'Add :LSEnvironment dict'                                          "$plist" 2>/dev/null || true
                /usr/libexec/PlistBuddy -c 'Add :LSEnvironment:IINA_EXECUTABLE    string "@executable_path"'  "$plist" 2>/dev/null || true
                /usr/libexec/PlistBuddy -c 'Set :LSEnvironment:IINA_EXECUTABLE           "@executable_path"'  "$plist"
                # Overwrite Git info from build (which were set to placeholders because Xcode script could not determine them at build time)
                /usr/libexec/PlistBuddy -c "Set :com.colliderli.iina.build.commit        $git_rev"            "$plist"
                /usr/libexec/PlistBuddy -c "Set :com.colliderli.iina.build.branch        $git_branch"         "$plist"

                # echo "[${system}] 🔏 Re-signing IINA.app..."
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
                app="$out/Applications/IINA.app"
                frameworks="$app/Contents/Frameworks"

                export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
                APPLE_BIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
                export PATH="$APPLE_BIN:$DEVELOPER_DIR/usr/bin:/usr/bin:/bin"

                echo "📦 Combining universal IINA.app"

                mkdir -p "$out/Applications"
                # copy the contents of the source app into the target dir
                ${pkgs.rsync}/bin/rsync -a ${builtins.elemAt self.archApps 0}/Applications/IINA.app/ "$app/"
                chmod -R u+w "$app"

                echo "🔍 Merging binaries across architectures"
                find "$app" -type f \( -perm -111 -o -name "*.dylib" -o -name "*.so" \) | while read -r dep; do
                  if [[ -L "$dep" ]] || [[ ! -f "$dep" ]]; then
                    echo "✅ Skipping non-file $dep"
                    continue
                  fi

                  if ! file -b "$dep" | grep -qi 'Mach-O'; then
                    echo "✅ Skipping non-Mach-O $dep"
                    continue
                  fi

                  relpath=$(${pkgs.coreutils}/bin/realpath --relative-to="$app" "$dep")

                  # collect candidate files from each arch build
                  inputs=""
                  for archroot in ${
                    builtins.concatStringsSep " " (map (a: "\"${a}/Applications/IINA.app\"") self.archApps)
                  }; do
                    candidate="$archroot/$relpath"
                    if [ -f "$candidate" ]; then
                      inputs="$inputs $candidate"
                    fi
                  done

                  # pick at most one file per arch to avoid duplicates
                  arm64=""
                  x86_64=""
                  for f in $inputs; do
                    info=$(lipo -info "$f" 2>/dev/null || true)

                    if echo "$info" | grep -qw arm64 && [ -z "$arm64" ]; then
                      arm64="$f"
                    fi

                    if echo "$info" | grep -qw x86_64 && [ -z "$x86_64" ]; then
                      x86_64="$f"
                    fi

                    # if we ever see a fat that already has both, just use it as-is
                    if echo "$info" | grep -q 'Architectures in the fat file' && \
                       echo "$info" | grep -qw arm64 && echo "$info" | grep -qw x86_64; then
                      arm64="$f"; x86_64="$f"; break
                    fi
                  done

                  # if only one arch available, leave it alone
                  if [ -z "$arm64" ] || [ -z "$x86_64" ]; then
                    echo "✅ Skipping single-arch $dep"
                    continue
                  fi

                  echo "🔨 Merging $relpath"
                  tmp="$dep.universal.$$"

                  # Ensure we can replace the file
                  chmod u+w "$dep" 2>/dev/null || true

                  # Guard against already universal binaries
                  if [ "$arm64" = "$x86_64" ]; then
                    cp -p "$arm64" "$tmp"
                  else
                    lipo -create -arch arm64 "$arm64" -arch x86_64 "$x86_64" -output "$tmp"
                  fi

                  # Preserve mode if possible (GNU coreutils); fall back to +x
                  ${pkgs.coreutils}/bin/chmod --reference="$dep" "$tmp" 2>/dev/null || chmod +x "$tmp"

                  mv -f "$tmp" "$dep"
                done

                echo "📦 Deep-bundling dynamic dependencies into IINA.app"
                ${libTool}/bin/iina-lib-tool --canonicalize "$frameworks" "$app/Contents/MacOS"

                echo "🔏 Re-signing IINA.app..."
                ${resign}/bin/iina-resign "$app"

                echo "[${system}] 📦 Copying include dir"
                mkdir -p "$out/include"
                cp -RL ${depsInclude}/. $out/include

                app_real=$(realpath "$app" 2>/dev/null || echo "$app")
                echo "✅✅ Done! Universal IINA.app is ready at $app_real"
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
                link_tree ${depsExecutable} "$deps_root/executable"

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
