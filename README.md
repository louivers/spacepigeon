# SpacePigeon: Saved Workspaces for macOS

**SpacePigeon** is a native macOS app (powered by Hammerspoon) that lets you define *workspaces* — which apps open, which desktop spaces they go to, and how windows are arranged.

## Features
- 🚀 **One-Click Setup**: Installs everything automatically via a native macOS App.
- 🖥 **Workspace Automation**: Opens specific apps into specific Spaces and arranges them.
- ⚡️ **Hotkeys**: Trigger layouts instantly.
- 🛠 **Customizable**: Written in Lua, easily editable via the app.

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
   ./build_app.sh
   ```
3. Open the generated app:
   ```bash
   open SpacePigeon.app
   ```

## Requirements
- **[Hammerspoon](https://www.hammerspoon.org/)** (The app will prompt you to download it if missing).

## Configuration
You can edit your workspaces by clicking **"Edit Config"** in the SpacePigeon app, or by editing `~/.hammerspoon/config.lua` directly.

## License
MIT
