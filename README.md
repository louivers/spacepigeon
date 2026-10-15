# SpacePigeon: Saved Workspaces for macOS

<div align="center">
  <img src="spacepigeon_screenshot.png" alt="SpacePigeon Screenshot" width="600"/>
</div>

**SpacePigeon** is a native macOS app (powered by Hammerspoon) that lets you define *workspaces* — which apps open, which desktop spaces they go to, and how windows are arranged.

Effortlessly transition between workflows. SpacePigeon instantly orchestrates your applications, windows, and displays into the perfect environment for any task with a single click or hotkey.

## Features

- 🚀 **One-Click Setup**: Installs everything automatically. If you don't have Hammerspoon, SpacePigeon will download and install it for you.
- 🎨 **Visual Configuration**: A full native UI to manage your workspaces. No need to touch Lua code manually.
- 🖥 **Multi-Monitor Support**: Configure spaces and app layouts for both your Main and Secondary monitors.
- ⚡️ **Smart App Launching**:
  - **Browser Mode**: Launch browsers with specific startup URLs.
  - **Deep Links**: Open apps to specific content (e.g., Notion pages, Spotify playlists, or custom URL schemes).
- 🪟 **Window Management**: Automatically position windows:
  - Maximize
  - Halves (left, right, top, bottom), thirds, two-thirds, quarters, or centered
  - Native fullscreen, in the order you choose
- ♻️ **No more quitting**: Apps that are already open are moved to their space instead of being closed and reopened.
- ⌨️ **Hotkeys**: Bind global hotkeys to trigger specific presets instantly.
- 🐦 **Menu Bar**: Pick a preset from the menu bar.
- 🔌 **Follows your monitors**: Optionally rearranges your windows when you plug in or unplug a monitor.
- 💾 **Save before quitting**: Presses Cmd+S in the apps you choose before quitting them.
- 📑 **Presets**: Create multiple workspace states (e.g., "Work", "Chill", "Stream") and switch between them.

## Installation

### Option 1: Download App (Recommended)
1. Go to the **[Releases](../../releases)** page.
2. Download `SpacePigeon.zip`.
3. Unzip the file.
4. Run **SpacePigeon.app**.
5. Click **"Install & Reload"**.

### "Unidentified Developer" Warning?
If macOS prevents the app from opening because it "cannot be verified":

1. Click **Done** (or Cancel) on the warning dialog.
2. Open **System Settings**.
3. Go to **Privacy & Security**.
4. Scroll down to the **Security** section.
5. Click the **Open Anyway** button next to *"SpacePigeon.app was blocked..."*.
6. Click **Open** in the final confirmation.

*(This is required because the app is open-source and not signed with a paid Apple Developer certificate).*

### Option 2: Build from Source
If you prefer to build it yourself:

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/spacepigeon.git
   cd spacepigeon
   ```
2. Run the build script:
   ```bash
   ./scripts/build_app.sh
   ```
3. Open the generated app:
   ```bash
   open SpacePigeon.app
   ```

## Configuration

Launch SpacePigeon and click **"Edit Config"** to open the configuration editor.

### Presets Tab
Manage your workspace layouts here.
- **Spaces**: How many spaces you want on your Main and Secondary monitors, counting desktops and fullscreen apps together (what you see in the Mission Control bar). Every space without a fullscreen app is a desktop. If something clashes (two fullscreen apps on one number, an app past the last space), a warning shows under the counts.
- **Modes**: Give a preset a different layout for 1, 2 or 3 connected monitors with **Add Mode**. When you trigger the preset, SpacePigeon uses the mode for the number of monitors connected right now, or the **Default** layout if there is none. A new mode starts as a copy of the default; a 1-monitor mode puts the second monitor's spaces after the main monitor's.
- **Focus When Done**: The app that has focus when the setup is complete. SpacePigeon switches to the space with that app's window. **First app** (the default) focuses the first app on the main monitor's first space.
- **Applications Layout**: Add apps to the list.
  - **Name**: The application name (e.g., "Safari", "Terminal").
  - **Monitor**: Choose "Main" or "2nd".
  - **Space**: Where the app goes in Mission Control, counting desktops and fullscreen apps together from the left. Example with 5 spaces: Brave fullscreen at 1 and Cursor at 3 gives *Brave, Desktop, Desktop with Cursor, Desktop, Desktop*.
  - **Position**: Maximize, Fullscreen, a half (left, right, top, bottom), a third or two-thirds, a quarter, or Center. A fullscreen app takes its space for itself.
  - **Gear Icon ⚙️**: Access advanced settings:
    - **Is this a Browser?**: Check this to enable startup URL support.
    - **URL**: Enter a web URL (for browsers) or a deep link (for other apps) to open on launch.

### Bindings Tab
Set up global hotkeys to trigger your presets.
- **Modifiers**: `cmd`, `alt`, `ctrl`, `shift` (comma separated).
- **Key**: The key to press (e.g., `S`, `1`, `F`).
- **Preset**: Select which preset this hotkey should activate.

### General Tab
Global settings that apply to all presets.
- **Quit apps that are not in the preset**: On by default. Apps that *are* in the preset are never quit; their windows are moved.
- **Rearrange when a monitor is plugged in or unplugged**: Off by default. When the number of monitors changes, the last preset is set up again, using its mode for the new count if it has one. No apps are quit; windows are only moved.
- **Show presets in the menu bar**: On by default.
- **Keep Alive Apps**: A list of applications that should *not* be quit when switching presets.
  - By default, SpacePigeon quits apps not defined in the current preset to keep your workspace clean.
  - Add apps here (e.g., "Spotify", "Discord") to keep them running in the background.
  - If a kept-alive app is also part of the new preset's layout, it will be moved to its assigned space/position.
- **Save Before Quitting**: Apps that get Cmd+S in each of their windows before SpacePigeon quits them, i.e. when a preset without them is set up (e.g. "TextEdit", "Pages").
  - Documents that were never saved are left alone: the app asks about them when it quits.
  - Don't add browsers or other apps where Cmd+S does something else.
  - SpacePigeon never force quits an app that is asking about unsaved changes. It stops and asks you to save or close your work first.

After making changes, click **"Save & Reload Hammerspoon"** to apply them immediately.

## How windows are moved

SpacePigeon ships a small helper, `spacectl` (source in `helper/`, installed to `~/.hammerspoon/bin/spacectl`). It uses a private macOS call to move windows between spaces and a fast swipe trick to switch spaces without opening Mission Control. Both work with System Integrity Protection (SIP) turned on, on **macOS 26.4 and newer**.

If the helper is missing or a move does not work, SpacePigeon falls back to the old way: switching spaces through Mission Control, and quitting and reopening an app on the right space as a last resort.

Spaces cannot be moved by any API. macOS puts a new desktop after the last desktop and a new fullscreen app at the very end. So SpacePigeon first gets the right number of desktops, makes the fullscreen apps fullscreen (they land at the end), and then drags each one to its place in the Mission Control Spaces bar. It reads the exact thumbnail positions from Mission Control, so the drags are precise; the mouse moves for a moment and is put back afterwards. You can turn the dragging off in the General tab; fullscreen apps then stay after the last desktop, in order. When everything is already in place, nothing happens.

**Tip:** turn off *System Settings > Desktop & Dock > Automatically rearrange Spaces based on most recent use*, or macOS will shuffle your spaces again.

### Check that it works on your Mac
```bash
bash scripts/build_helper.sh         # builds build/spacectl
./build/spacectl check               # "move": true means window moves work
./build/spacectl selftest            # moves your Terminal window to another desktop and back
```
`selftest` needs at least two desktops on the screen you run it from.

### Logs
Every workspace run is logged to `~/.hammerspoon/spacepigeon.log`: each step with how long it took, which apps were quit, which windows were moved or relaunched, and every warning and error. Open **View Logs** in the SpacePigeon app (or run `open -a SpacePigeon --args --logs`) to browse runs, filter warnings and errors, and copy a run as text.

### Tests without a Mac
The space arranging and the workspace flow have simulation tests that run with plain Lua 5.4 (`brew install lua`):
```bash
lua tests/slots_sim.lua
lua tests/structure_sim.lua
lua tests/mcdrag_sim.lua
lua tests/workspace_sim.lua
```

## Requirements
- **[Hammerspoon](https://www.hammerspoon.org/)** (The app will automatically download and install this to `~/Applications` if it is not found).
- **macOS 26.4 or newer** to move windows between spaces without quitting apps. Older versions still work with the fallback.
- **Xcode Command Line Tools** to build from source (`xcode-select --install`).

## License
MIT
