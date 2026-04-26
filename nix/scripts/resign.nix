{ pkgs }:

pkgs.writeShellApplication {
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
}
