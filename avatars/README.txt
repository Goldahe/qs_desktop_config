Theme avatar registry

avatars/registry.json is the trusted mapping from theme avatarId values to
standalone Quickshell profiles, IPC targets, adapters, and required assets.
Theme JSON files contain IDs only; they never provide paths or commands.

Lifecycle ownership:
  - theme-control.py validates and persists the desired avatar
  - theme or Game Mode changes may terminate registered avatars
  - theme selection never launches an avatar
  - Chatterbox resolves the committed policy at each segment and owns lazy launch
  - main/avatar-control.py rechecks mode and policy before invoking start.sh

Adapters:
  hk47-hologram  supports emotion color, audio envelope, and power transitions
  static-portrait supports only activation and deactivation

The shrine-maiden ID is intentionally stable. To add a slideshow later, keep the
same theme avatarId and replace only that profile's internal renderer after adding
its additional images, timing configuration, and lifecycle tests. A static profile
must not run a recurring timer while hidden.
