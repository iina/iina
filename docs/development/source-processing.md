# Source processing and engine capabilities

The interface series retains IINA's dependency declarations. The experimental
LYINA preview also contains optional mpv extensions; their patches are included
under `other/patches/` for review, not automatically applied or distributed.

## Multiple audio/video sources

The player owns its generated `lavfi-complex` graph and rejects selection changes
that would replace a user-owned custom graph. The stock path rebuilds the graph
when source membership or scoped processing changes. This can cause a native
reconfiguration; it is not a claim of gap-free switching on arbitrary files.

`mpv-0.41.0-lavfi-complex-command.patch` adds live named-filter commands and an
audio-refresh argument. PlayerCore detects the advertised command and argument
before selecting that path. Unsupported engines use graph replacement.

Per-source video processing and layered composition use software filter formats.
HDR/Dolby Vision equivalence, GPU-only processing and arbitrary decoder/filter
combinations require additional evaluation.

## Secondary subtitle styles

`mpv-0.41.0-secondary-subtitle-style.patch` adds an opt-in independent secondary
style namespace. MPVController checks whether the engine accepts that option.
Without it, the Secondary Style card is replaced with an explanation; style
writers and resets reject unsupported secondary mutations. Native delay and
position remain available for both display roles. The current role's source
selection remains independent of its settings-editing context.

Primary styling and authored ASS styling retain the chosen override policy.
The interface supports configured font sizes outside its usual menu presets.

## Validation boundaries

Focused tests exercise extracted production models and native controls with
explicit collaborators. Engine probes use null audio/video or software rendering,
without opening the installed player or changing its profile. These probes do
not establish composited animation smoothness, general stability, Intel support
or behavior on older macOS releases. Each PR records its own actual checks.
