{ pkgs }:

pkgs.writeShellApplication {
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
}
