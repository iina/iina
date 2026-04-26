{ pkgs }:

pkgs.writeShellApplication {
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
}
