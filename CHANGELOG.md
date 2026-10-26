# Changelog

## Unreleased

### Fixed
- **macOS 27**: switching spaces, adding and removing desktops, and dragging fullscreen apps into place work again. macOS 27 draws Mission Control in WindowManager instead of the Dock, so Hammerspoon's `hs.spaces` could no longer find it ("no display with specified id found", "no Spaces bar"). SpacePigeon now finds Mission Control in either place and presses its buttons itself on macOS 27.
- **macOS 27**: the instant space switch (a synthesized Dock swipe) does nothing there. `spacectl check` now reports `"focus": false` on macOS 27 (helper 1.3.0), so SpacePigeon switches through Mission Control right away instead of waiting 2 seconds for each swipe to fail.
- **macOS 27**: fullscreen apps are dragged into place again. Mission Control there reports each Spaces bar thumbnail's centre as its position, so every drag pressed the corner of a thumbnail and was ignored. SpacePigeon corrects the frames (and notices when a later macOS reports them right), drags carefully, and when Mission Control does not open the gap it lets go over the thumbnail itself instead of next to another app (which made a Split View).
- **macOS 27**: an app in Split View is taken out again. A window in Split View says it is not fullscreen there, so it is taken out with its fullscreen button.
- A new desktop on macOS 27 goes after the fullscreen apps; the drags put it in its place.
- A space switch through Mission Control that does not go through is tried once more.

## 2.1.0

### Added
- **Several windows of one app** ([#11](https://github.com/louivers/spacepigeon/issues/11), [#13](https://github.com/louivers/spacepigeon/issues/13)): each row in a preset is one window, so an app can be in a preset more than once (two Terminal windows side by side, two Chrome profiles). Rows get the app's windows in list order and keep them when the preset is set up again. Missing windows are opened with Cmd+N, or with a menu item or AppleScript set per row. A row can ask for a specific window by text from its title. A window that does not show up is skipped with a warning.
- **Save the current layout as a preset** ([#12](https://github.com/louivers/spacepigeon/issues/12)): the 📷 button in the config editor, or **Save Current Layout as Preset…** in the menu bar, reads the open windows (app, monitor, space, position) into a new preset. Positions close to a half, third, quarter or the whole screen snap to it.
- **Custom position**: any part of the screen, in percent.

### Changed
- `spacectl windows` also reports each window's position (helper 1.2.0).
- Apps a preset names by their file name (like "Visual Studio Code", which runs as "Code") are no longer quit as "not in the preset".

## 2.0.1
- The app and the `spacectl` helper are universal, so SpacePigeon runs on Intel Macs too (it was Apple Silicon only).
- The app needs macOS 12 or newer and says so, instead of failing to open on older versions.

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
- **Profiles** for trying things without touching your own presets: `scripts/profile.sh demo` opens the app on sample presets (for screenshots), `scripts/profile.sh off` goes back. See [docs/testing.md](docs/testing.md).
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
