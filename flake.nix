{
  description = "IINA – The modern video player for macOS.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs =
    { self, nixpkgs }:
    {
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      archApps = builtins.map (system: self.packages.${system}.iina) self.systems;

      packages = nixpkgs.lib.genAttrs self.systems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          # Pull system's xcode in
          xcode = pkgs.runCommand "system-xcode" { } ''
            mkdir -p $out/bin
            ln -sf /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild $out/bin/xcodebuild
          '';

          # Override ffmpeg to use our version of libs
          ffmpeg = pkgs.ffmpeg_7.override {
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
          };

          # Override mpv with vapoursynth support
          mpv = pkgs.mpv-unwrapped.override {
            ffmpeg = ffmpeg;
            lua = pkgs.luajit;
            vapoursynth = pkgs.vapoursynth;

            # enable features we want
            vapoursynthSupport = true;
            javascriptSupport = true;
            cmsSupport = true;
            rubberbandSupport = true;
            archiveSupport = true;
            bluraySupport = true;
            openalSupport = true;
            vulkanSupport = true;
            zimgSupport = true;

            # disable linux-only bits
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

          # Collect include deps as per readme.md
          depsInc = pkgs.linkFarm "iina-deps-inc" [
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
              name = "libpostproc";
              path = "${pkgs.lib.getDev ffmpeg}/include/libpostproc";
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
                  pkgs.vapoursynth
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
                ]
            )
          );

          # Collect indirect deps
          depsIndirect = pkgs.linkFarm "iina-deps-indirect" (
            pkgs.lib.flatten (
              map
                (
                  pkg:
                  let
                    libdir = "${pkgs.lib.getLib pkg}/lib";
                    files = builtins.attrNames (builtins.readDir libdir);
                  in
                  pkgs.lib.concatMap (
                    file:
                    if pkgs.lib.hasSuffix ".dylib" file then
                      [
                        {
                          name = file;
                          path = "${libdir}/${file}";
                        }
                      ]
                    else
                      [ ]
                  ) files
                )
                [
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
                  pkgs.libjxl
                  pkgs.libogg
                  pkgs.libopenmpt
                  pkgs.libopus
                  pkgs.libplacebo
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
                  pkgs.rubberband
                  pkgs.SDL2
                  pkgs.sdl3
                  pkgs.srt
                  pkgs.svt-av1
                  pkgs.vapoursynth
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
                  pkgs.vapoursynth
                  pkgs.python3
                  pkgs.yt-dlp
                ]
            )
          );

          # Collect SwiftPM deps as separate derivation for them to be cached
          spmDeps = pkgs.stdenv.mkDerivation {
            pname = "iina-spm-deps";
            version = if self ? rev then builtins.substring 0 8 self.rev else "dev";

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

          # hared normalizer script
          normalizer = pkgs.writeShellApplication {
            name = "iina-normalize-app";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.gawk
              pkgs.gnugrep
              pkgs.file
            ];
            text = ''
              set -euo pipefail

              if [[ $# -lt 1 ]]; then
                echo "usage: iina-normalize-app /path/to/IINA.app" >&2
                exit 2
              fi

              app="$1"
              frameworks="$app/Contents/Frameworks"

              echo "🔧 iina-normalize-app: normalizing $app"
              mkdir -p "$frameworks"

              echo "📝 Making app contents writable"
              find "$app" -type d -exec chmod u+rwx {} \;
              find "$app" -type f -exec chmod u+rw  {} \;

              # ✏️ Helpers
              is_macho() {
                # true for thin/fat Mach-O; false for scripts/text
                file -b "$1" 2>/dev/null | grep -Eq 'Mach-O (universal binary|64-bit|arm64|x86_64)'
              }

              ensure_writable() { chmod u+rw "$1" 2>/dev/null || true; }

              ensure_rpath() {
                local f="$1"

                if ! is_macho "$f"; then
                  echo "🧾 Non-Mach-O, skipping rpath: $f"
                  return
                fi

                if otool -l "$f" | grep -q '@executable_path/../Frameworks'; then
                  echo "✅ LC_RPATH present → $f"
                  return
                fi
                
                echo "➕ LC_RPATH @executable_path/../Frameworks → $f"
                install_name_tool -add_rpath "@executable_path/../Frameworks" "$f" || true
              }

              rewrite_deps_to_rpath() {
                local bin="$1"

                if ! is_macho "$bin"; then
                  echo "🧾 Non-Mach-O, skipping dep rewrite: $bin"
                  return
                fi

                echo "✏️ Rewriting deps → @rpath for: $bin"

                # /nix/store/* → @rpath/<basename>
                otool -L "$bin" | awk '/\/nix\/store/ && $1 !~ /:$/ {print $1}' | while read -r abs; do
                  local base
                  base=$(basename "$abs")
                  echo "  🔁 /nix/store → @rpath: $abs → @rpath/$base"
                  install_name_tool -change "$abs" "@rpath/$base" "$bin" || true
                done

                # bare dylibs (no /, no @) → @rpath/<basename>
                otool -L "$bin" | awk 'NF && $1 !~ /:$/ && $1 ~ /^[^/@][^/]*\.dylib$/ {print $1}' | while read -r bare; do
                  local base
                  base=$(basename "$bare")
                  echo "  🔁 bare → @rpath: $bare → @rpath/$base"
                  install_name_tool -change "$bare" "@rpath/$base" "$bin" || true
                done
              }

              declare -Ag BUNDLED_DEPS=()

              bundle_dep() {
                local dep="$1"   # path as found in otool -L (may be libbs2b.0.dylib)

                # Canonical path for cycle detection
                local dep_real
                dep_real=$(realpath "$dep" 2>/dev/null || echo "$dep")

                # Break cycles by *real* path
                if [[ -n "''${BUNDLED_DEPS["$dep_real"]:-}" ]]; then
                  echo "🔁 Already processed dep: $dep_real"
                  return
                fi
                BUNDLED_DEPS["$dep_real"]=1

                local request_base
                request_base=$(basename "$dep")
                local real_base
                real_base=$(basename "$dep_real")
                local dest="$frameworks/$request_base"

                if [[ "$dep_real" == /usr/lib/* ]] || [[ "$dep_real" == /System/* ]] || [[ "$real_base" == libffi-trampoline.dylib ]]; then
                  echo "🚫 Skipping system/non-target dep: $dep_real"
                  return
                fi

                if [ ! -f "$dep_real" ]; then
                  echo "⚠️  Dep missing on disk, skipping: $dep_real"
                  return
                fi

                # Ensure the real payload file exists in Frameworks under some canonical name
                local canonical="$frameworks/$real_base"
                if [ ! -f "$canonical" ]; then
                  echo "📥 Copying dep → Frameworks: $dep_real → $canonical"
                  cp -L -p "$dep_real" "$canonical" || { echo "❌ Copy failed for $dep_real"; return; }
                fi

                # Ensure the *requested* name exists and points to the payload
                if [ ! -e "$dest" ]; then
                  echo "🔗 Copying $canonical → $dest"
                  cp -L -p "$canonical" "$dest"
                else
                  echo "✏️ Normalizing already-bundled dep alias: $request_base"
                fi

                ensure_writable "$canonical"

                if ! is_macho "$canonical"; then
                  echo "🧾 Non-Mach-O dep (no patching): $real_base"
                  return
                fi

                echo "✏️ Setting install_name id on $real_base"
                install_name_tool -id "@rpath/$request_base" "$canonical" || true

                ensure_rpath "$canonical"
                rewrite_deps_to_rpath "$canonical"

                # Recurse into transitive deps based on their /nix/store path
                otool -L "$canonical" | awk 'NF && $1 !~ /:$/ {print $1}' | while read -r sub; do
                  case "$sub" in
                    /nix/store/*)
                      local subbase
                      subbase=$(basename "$sub")
                      echo "  🔗 Repointing subdep for $real_base: $sub → @rpath/$subbase"
                      install_name_tool -change "$sub" "@rpath/$subbase" "$canonical" || true
                      bundle_dep "$sub"
                      ;;
                    *) : ;;
                  esac
                done
              }

              export -f ensure_writable ensure_rpath rewrite_deps_to_rpath bundle_dep

              echo "🔍 Scanning app for dylib + executable dependencies…"

              # executables + loadable libs
              find "$app" -type f \( -perm -111 -o -name "*.dylib" -o -name "*.so" \) | while read -r bin; do
                echo "———"
                echo "🔍 Inspecting: $bin"
                ensure_writable "$bin"
                ensure_rpath "$bin"

                if ! is_macho "$bin"; then
                  echo "🧾 Non-Mach-O target has no dylib deps to bundle"
                  continue
                fi

                # bundle remaining absolute /nix/store deps
                otool -L "$bin" | awk 'NF && $1 !~ /:$/ {print $1}' | while read -r dep; do
                  case "$dep" in
                    /nix/store/*)
                      echo "  📦 Bundling needed dep for $bin: $dep"
                      bundle_dep "$dep"
                      ;;
                    *) : ;;
                  esac
                done

                rewrite_deps_to_rpath "$bin"
              done

              echo "✅ Normalization complete"
            '';
          };

          canonicalizeLibGroups = pkgs.writeShellApplication {
            name = "iina-canonicalize-lib-groups";
            runtimeInputs = [
              pkgs.findutils
              pkgs.coreutils
              pkgs.gawk
            ];
            text = ''
              set -euo pipefail

              frameworks="$1/Contents/Frameworks"

              # Build the index in memory: each line is "STEM \t VERSION \t BASENAME"
              lines="$(
                find "$frameworks" -maxdepth 1 \( -type f -o -type l \) -name 'lib*.dylib' | while read -r dep; do
                  base="$(basename "$dep")"
                  if [[ "$base" =~ ^(lib[^.]+)\.([0-9]+(\.[0-9]+)*)\.dylib$ ]]; then
                    printf '%s\t%s\t%s\n' "''${BASH_REMATCH[1]}" "''${BASH_REMATCH[2]}" "$base"
                  elif [[ "$base" =~ ^(lib[^.]+)\.dylib$ ]]; then
                    printf '%s\tUNVER\t%s\n' "''${BASH_REMATCH[1]}" "$base"
                  fi
                done
              )"

              # For each STEM, pick highest VERSION as canonical; relink others to it
              printf '%s\n' "$lines" | cut -f1 | sort -u | while read -r stem; do
                canon="$(
                  printf '%s\n' "$lines" | awk -F'\t' -v s="$stem" '$1==s && $2!="UNVER"{print $2"\t"$3}' \
                    | ${pkgs.coreutils}/bin/sort -V | tail -n1 | cut -f2
                )"

                # If no versioned file exists, fall back to unversioned
                if [ -z "$canon" ]; then
                  canon="$(printf '%s\n' "$lines" | awk -F'\t' -v s="$stem" '$1==s && $2=="UNVER"{print $3}' | head -n1)"
                fi
                [ -n "$canon" ] || continue

                # Relink every other alias in the group to canonical (relative link)
                (
                  cd "$frameworks"
                  printf '%s\n' "$lines" | awk -F'\t' -v s="$stem" '$1==s{print $3}' | while read -r alias; do
                    [ "$alias" = "$canon" ] && continue
                    rm -f -- "$alias"
                    ln -s -- "$canon" "$alias"
                  done
                )
              done

              echo "✅ Canonicalized lib groups under $frameworks"
            '';
          };

          resign = pkgs.writeShellApplication {
            name = "iina-resign";
            runtimeInputs = [
              pkgs.findutils
              pkgs.coreutils
            ];
            text = ''
              set -euo pipefail
              app="$1"

              # Make sure everything we might sign is writable
              find "$app" -type d -exec chmod u+rwx {} \;
              find "$app" -type f -exec chmod u+rw  {} \;

              # (optionally re-mark executables executable, in case)
              find "$app/Contents/MacOS" -type f -perm -111 -exec chmod u+rw {} \;

              /usr/bin/codesign --force --deep --sign - "$app"
            '';
          };
        in
        {
          iina = pkgs.stdenv.mkDerivation {
            pname = "iina";
            version = if self ? rev then builtins.substring 0 8 self.rev else "dev";

            src = pkgs.nix-gitignore.gitignoreSource [ "flake.nix" "flake.lock" ] ./.;

            strictDeps = true;

            nativeBuildInputs = [
              pkgs.coreutils
              xcode
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
              echo "🔧 Setting up build environment"
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

              echo "📦 Copying external deps"
              mkdir -p deps
              rm -rf deps/include deps/lib

              mkdir -p deps/include deps/lib deps/executable

              cp -RL ${depsInc}/.               deps/include
              cp -RL ${depsLib}/.               deps/lib
              cp -RL ${depsExecutable}/.        deps/executable/

              echo "✏️ Rewriting install names to use @rpath"
              find deps/lib -type f \( -perm -111 -o -name "*.dylib" -o -name "*.so" \) | while read -r dep; do
                echo "✏️ Patching install names in $dep"
                chmod +w "$dep"

                # Change its ID to @rpath/<filename>
                install_name_tool -id "@rpath/$(basename "$dep")" "$dep" || true

                # Rewrite dependencies that still point to /nix/store
                otool -L "$dep" | awk '/\/nix\/store/ && $1 !~ /:$/ {print $1}' | while read -r nixdep; do
                  base=$(basename "$nixdep")
                  install_name_tool -change "$nixdep" "@rpath/$base" "$dep" || true
                done
              done

              echo "📦 Copying SPM deps"
              rsync -a ${spmDeps}/ ./
              chmod -R u+rwx,g+rx,o+rx .

              # Rewrite SwiftPM workspace-state.json to fix absolute paths
              if [ -f .spm/workspace-state.json ]; then
                old_prefix=$(grep -Eo "/nix/var/nix/builds/nix-[^/]+/source" .spm/workspace-state.json | head -n1)
                echo "Patching workspace-state.json: replacing $old_prefix → $PWD"
                sed -i -E "s|$old_prefix|$PWD|g" .spm/workspace-state.json
              fi

              # Build IINA
              echo "🔨 Building IINA"
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
              resources="$app/Contents/Resources"
              plist="$app/Contents/Info.plist"

              mkdir -p "$frameworks"
              mkdir -p "$resources"

              echo "📦 Bundling ${depsIndirect} into IINA.app"
              cp -RL ${depsIndirect}/. "$frameworks/"

              echo "📦 Bundling ${depsExecutable} into IINA.app"
              cp -RL ${depsExecutable}/. "$macos/"

              echo "🐍 Bundling ${pkgs.python3} into IINA.app"

              # Pick the single pythonX.Y dir from Nix’s python3
              python_src_dir=$(echo ${pkgs.python3}/lib/python* | awk '{print $1}')
              python_basename="$(basename "$python_src_dir")"
              python_site="$resources/Python/lib/$python_basename/site-packages"
              vapoursynth_site_src=$(echo ${pkgs.vapoursynth}/lib/python*/site-packages | awk '{print $1}')

              mkdir -p "$resources/Python/lib"
              mkdir -p "$python_site"

              # Copy Python's stdlib
              cp -RL "$python_src_dir" "$resources/Python/lib/"

              # Copy VapourSynth’s Python package
              cp -RL "$vapoursynth_site_src"/. "$python_site/"

              echo "📦 Deep-bundling dynamic dependencies into IINA.app"
              ${normalizer}/bin/iina-normalize-app "$app"

              echo "✏️ Canonicalize Lib Groups"
              ${canonicalizeLibGroups}/bin/iina-canonicalize-lib-groups "$app"

              echo "✏️ Setting up environment variables"

              /usr/libexec/PlistBuddy -c 'Add :LSEnvironment dict'                                                                             "$plist" 2>/dev/null || true
              /usr/libexec/PlistBuddy -c 'Add :LSEnvironment:PYTHONHOME          string "@executable_path/../Resources/Python"'                "$plist" 2>/dev/null || true
              /usr/libexec/PlistBuddy -c 'Set :LSEnvironment:PYTHONHOME                 "@executable_path/../Resources/Python"'                "$plist"
              /usr/libexec/PlistBuddy -c 'Add :LSEnvironment:PYTHONNOUSERSITE    string "1"'                                                   "$plist" 2>/dev/null || true
              /usr/libexec/PlistBuddy -c 'Set :LSEnvironment:PYTHONNOUSERSITE           "1"'                                                   "$plist"
              /usr/libexec/PlistBuddy -c 'Add :LSEnvironment:VAPOURSYNTH_LIBRARY string "@executable_path/../Frameworks/libvapoursynth.dylib"' "$plist" 2>/dev/null || true
              /usr/libexec/PlistBuddy -c 'Set :LSEnvironment:VAPOURSYNTH_LIBRARY        "@executable_path/../Frameworks/libvapoursynth.dylib"' "$plist"
              /usr/libexec/PlistBuddy -c 'Add :LSEnvironment:IINA_EXECUTABLE    string "@executable_path"'                                    "$plist" 2>/dev/null || true
              /usr/libexec/PlistBuddy -c 'Set :LSEnvironment:IINA_EXECUTABLE           "@executable_path"'                                    "$plist"

              echo "🔏 Re-signing IINA.app..."
              ${resign}/bin/iina-resign "$app"
            '';
          };

          iina-universal = pkgs.stdenv.mkDerivation {
            pname = "iina-universal";
            version = if self ? rev then builtins.substring 0 8 self.rev else "dev";

            nativeBuildInputs = [
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
              ${normalizer}/bin/iina-normalize-app "$app"

              echo "✏️ Canonicalize Lib Groups"
              ${canonicalizeLibGroups}/bin/iina-canonicalize-lib-groups "$app"

              echo "🔏 Re-signing IINA.app..."
              ${resign}/bin/iina-resign "$app"
            '';

            preFixup = ''
              export PATH=${pkgs.coreutils}/bin:$PATH
            '';
          };

          default = self.packages.${system}.iina-universal;
        }
      );
    };
}
