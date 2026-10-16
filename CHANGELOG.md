# Changelog

## 2.0.0

### Added
- **`spacectl` helper** (source in `helper/`, installed to `~/.hammerspoon/bin/spacectl`). It moves windows between spaces and switches spaces without opening Mission Control, with SIP turned on, on macOS 26.4 and newer. `spacectl check` and `spacectl selftest` show whether it works on your Mac.
- **No more quitting**: apps that are already open are moved to their space instead of being closed and reopened.
- **Native fullscreen** as a position. SpacePigeon creates the right number of desktops and drags each fullscreen app to its place in the Mission Control Spaces bar. You can turn the dragging off in the General tab.
- **New positions**: top and bottom halves, thirds, two-thirds, quarters and center.
- **Up to 10 monitors**: give each monitor its own spaces and apps. Apps on a monitor that is not connected go after the main monitor's spaces.
- **Modes**: a different layout per preset for each number of connected monitors (1 to 10).
- **Focus When Done**: pick the app that has focus when a preset is set up.
- **Follow monitors** (off by default): set up the last preset again when a monitor is plugged in or unplugged, without quitting apps.
- **Save before quitting**: press Cmd+S in the apps you choose before they are quit. SpacePigeon no longer force quits apps: if one asks about unsaved changes, it stops and asks you to save or close your work.
- **Quit apps that are not in the preset** can now be turned off.
- **Menu bar** preset picker (on by default).
- **Logs**: every run is logged to `~/.hammerspoon/spacepigeon.log`. **View Logs** in the app (or `open -a SpacePigeon --args --logs`) lets you browse runs, filter warnings and errors, and copy a run as text.
- **App picker**: choose apps from a searchable list of installed apps (with icons) instead of typing their exact name, in the layout and in the Keep Alive and Save Before Quitting lists.
- **Drag and drop** to reorder apps in a preset, by the handle on the left of each row.
- **Duplicate preset** button.
- Warnings in the config editor when spaces clash (two fullscreen apps on one number, an app past the last space).
- Simulation tests in `tests/` that run with plain Lua 5.4.

### Changed
- **Space numbers** count desktops and fullscreen apps together, as in the Mission Control bar. Configs from 1.x keep working: they are read with the old numbering (desktops only), and the config editor converts them when you save.
- If a window cannot be moved, SpacePigeon falls back to Mission Control, and to quitting and reopening the app on its space as a last resort. This is also what happens below macOS 26.4.
- Apps are also found by their file name, so names like "Visual Studio Code" (which runs as "Code") work.
- Quotes and backslashes in preset names, app names and URLs no longer break the generated config.
- Lua sources moved to `lua/`, Swift sources to `swift/`, and build scripts to `scripts/` (`./scripts/build_app.sh`, `./scripts/deploy.sh`).

## 1.2.0
- Keep-alive apps, app icon and the polished config UI.
