# Goal
Analyze the in-repo mpv configuration and determine how each relevant option can be exposed through IINA's native Settings UI, so users don't need to edit mpv config files directly.

## Dimensions
1. What mpv options are set in the bundled `mpv/` config?
2. Which of those already have IINA preference keys / Settings UI coverage?
3. Which mpv options are missing from IINA Settings and what UI would they need?
4. Which options does IINA currently force-overwrite, and how should those be handled?

## Boundaries
- Scope is the macOS app (`iina/`) only.
- Focus on `mpv/` directory config, not user runtime overrides.
- Do not implement changes, only analyze and propose.
