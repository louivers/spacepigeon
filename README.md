# SpacePigeon: Saved Workspaces for macOS (Hammerspoon-based)

**SpacePigeon** lets you define *workspaces* for macOS — which apps open, which desktop spaces they go to, and how windows are arranged — using a lightweight Hammerspoon configuration.

## Features
- Open specific apps into specific macOS Spaces
- Auto-arrange windows
- Trigger workspaces via hotkeys
- Written entirely in Hammerspoon Lua
- Lightweight and open-source

## Installation
1. Install [Hammerspoon](https://www.hammerspoon.org/)
2. Copy the repository contents (including `init.lua` and the helper modules) into your `~/.hammerspoon` directory
3. Reload Hammerspoon

## Structure
- `init.lua` – entrypoint that binds the workspace hotkeys
- `space_utils.lua` – helpers for counting, creating, and navigating Spaces
- `layout.lua` – logic to launch apps into the correct Spaces and verify placement
- `workspaces.lua` – workspace presets and orchestration for quitting apps, setting up Spaces, and binding hotkeys

## Status
This is an early open-source release.
More modular structure, documentation, and GUI tools are coming soon.

## License
MIT
