# Nix Advantages

A few of the advantages of using Nix to build the libraries IINA is dependent upon compared to using Homebrew.

## No Version Mismatch Between Apple Silicon and Intel

A single Nix build generates universal binaries. This guarantees the same library versions are used for Apple Silicon and Intel Macs.

Because Homebrew builds for Apple Silicon and Intel Macs are done separately, there is a chance that Homebrew could update the version of a library between builds. [This comment](https://github.com/iina/iina/issues/5712#issuecomment-4064217941) from @absurd on issue #5712 explains that the reason the crash playing AV1 encoded videos did not happen on Intel Macs was because the x86_64 version of the dav1d was newer than the version used for arm64.

## Admin Account Not Needed

Nix builds can be run from an unprivileged account. Homebrew must be run under a macOS account with admin privileges.

## Host Not Modified

Running the Nix build does not install anything on the Mac running the build. The Homebrew build installs the libraries being built on the Mac running the build.

## Reproducible Build

Nix is designed for reproducible builds. Versions are automatically pinned in a `flakes.lock` file. Multiple developers can run the Nix build and get the same results. This also means IINA could later apply a patch to mpv and rebuild without other libraries being updated by the build.

Homebrew's ability to pin versions is discussed in [Locking installed formulae at specific versions](https://docs.brew.sh/Versions#locking-installed-formulae-at-specific-versions) which starts with a warning that you should not do this:
> Homebrew’s versions should not be used to “pin” formulae to your personal requirements. If a versioned formula already exists in homebrew/core, prefer that first: it remains supported and updated by Homebrew.

It is possible to pin versions when using Homebrew, but Homebrew was not designed with reproducible builds in mind.