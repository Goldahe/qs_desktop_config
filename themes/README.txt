Quickshell themes

Each selectable theme is one JSON file in this directory. The filename must
match its "id" and the id may contain letters, numbers, underscores, and dashes.

A theme contains:
  id, name, description
  avatarId - validated ID from avatars/registry.json
  personalityId - validated ID from ~/.hermes/personalities/<id>/SOUL.md;
                 loaded at the next Hermes session start
  palette   - map from every original shell color to the theme color
  wallpaper - wallpaper sources and rendering settings
  effects   - spectrum, wallpaper reaction, cadence, and avatar permission

HK-47_Theme.json is the preserved original setup and current selection.
HK-47_Amber_Theme.json is the bundled alternate used to verify switching.

The Theme Control menu discovers valid JSON files when the main Quickshell
profile starts. Applying a theme validates it, persists the selected palette and
profile settings, restarts the wallpaper profile appropriate to Work/Game mode,
and reloads the main shell. Invalid themes are omitted from the selector and are
rejected before any state file is changed.

Avatar creation remains owned by Chatterbox. A theme selects an approved avatar
and may permit or disable it, but selecting a theme never launches it. HK themes
use hk47-hologram; Dark_Souls_Theme uses the static shrine-maiden profile.
