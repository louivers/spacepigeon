# Testing SpacePigeon without touching your own setup

There are three levels, from quick to thorough.

## 1. Simulation tests

```bash
for f in tests/*.lua; do lua "$f"; done
```

They run against a fake macOS, so they never move your windows. CI runs them on every push.

## 2. Profiles: a separate set of presets on your own Mac

A profile has its own presets, generated config and log in `~/.hammerspoon/spacepigeon_profiles/<name>/`. Your own config (`~/.hammerspoon/spacepigeon_config.json` and `~/.hammerspoon/lua/config.lua`) is never read or written while you use one.

```bash
bash scripts/build_app.sh             # build the app from this checkout
bash scripts/build_app.sh --notarize  # signed, notarized and stapled, for a release
scripts/profile.sh demo               # sample presets, for screenshots and recordings
scripts/profile.sh fresh --reset      # the default config a new user starts with
scripts/profile.sh status             # which profile Hammerspoon loads
scripts/profile.sh off                # back to your own setup
```

The app opens on the profile, but Hammerspoon keeps running your own setup until you press **Save & Reload** in the config editor. Hammerspoon then shows "SpacePigeon: using the demo profile", and its hotkeys and menu bar are the profile's. Saving from the normal app (without a profile) also switches back to your own setup.

The **demo** profile has three presets with apps that come with macOS, open in about a second and show nothing personal, bound to Ctrl+Alt+Cmd+1, 2 and 3:

| Preset | What it shows |
| --- | --- |
| **Showcase** (1) | Most features in one run. Desktop 1: two Dictionary windows side by side, each opened on a word with a `dict://` deep link (several windows of one app, the second opened with Cmd+N). Then Chess, Stocks and Font Book fullscreen, before desktop 2: each new fullscreen app lands at the end and is dragged into place in Mission Control. Desktop 2: Clock on the left two-thirds, Calculator at a custom position. Tips is centered on the second monitor, or with one monitor fullscreen after Font Book (a mode with its own layout), which makes four drags. Ends with Dictionary focused. |
| **Meetings** (2) | Clock, Stocks and Calculator in thirds, Dictionary maximized on desktop 2. |
| **Evening** (3) | Chess fullscreen before the desktops, Tips on the left two-thirds, Calculator at a custom position. |

Run Showcase first, then Meetings or Evening: the windows that are already open are moved, not reopened. The profile does not quit other apps, so running a preset while recording never closes your work. Turn **Quit apps that are not in the preset** on in its General tab if you want the clean-desktop effect.

The presets are written when the profile is created. If you made the demo profile before they changed, or changed them yourself, `scripts/profile.sh demo --reset` starts it over.

You can also start the app on a profile with `open -n SpacePigeon.app --args --profile <name>`, or with `SPACEPIGEON_PROFILE=<name>` in the environment.

## 3. A second macOS user: what a new user really gets

Profiles share your Hammerspoon install, its permissions and your Mission Control settings. To check the whole first-run experience before a release, use a separate user account:

1. **System Settings > Users & Groups > Add User**, a standard account is enough.
2. Log in to it (fast user switching from Control Center keeps your own session open).
3. Download `SpacePigeon.zip` from the GitHub release, exactly as a user would. Do not copy your build over.
4. Go through the README's installation steps: the "unidentified developer" warning, the Hammerspoon download, the Accessibility prompt, the default preset.
5. Delete the account afterwards, or keep it for the next release.

This is the only way to see the Gatekeeper warning, the permission prompts and a Hammerspoon that has never been set up.
