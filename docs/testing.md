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
scripts/profile.sh demo               # sample presets, for screenshots and recordings
scripts/profile.sh fresh --reset      # the default config a new user starts with
scripts/profile.sh status             # which profile Hammerspoon loads
scripts/profile.sh off                # back to your own setup
```

The app opens on the profile, but Hammerspoon keeps running your own setup until you press **Save & Reload** in the config editor. Hammerspoon then shows "SpacePigeon: using the demo profile", and its hotkeys and menu bar are the profile's. Saving from the normal app (without a profile) also switches back to your own setup.

The **demo** profile has three presets (Deep Work, Meetings, Evening) with apps that come with macOS, bound to Ctrl+Alt+Cmd+1, 2 and 3. It does not quit other apps, so running a preset while recording never closes your work. Turn **Quit apps that are not in the preset** on in its General tab if you want the clean-desktop effect.

You can also start the app on a profile with `open -n SpacePigeon.app --args --profile <name>`, or with `SPACEPIGEON_PROFILE=<name>` in the environment.

## 3. A second macOS user: what a new user really gets

Profiles share your Hammerspoon install, its permissions and your Mission Control settings. To check the whole first-run experience before a release, use a separate user account:

1. **System Settings > Users & Groups > Add User**, a standard account is enough.
2. Log in to it (fast user switching from Control Center keeps your own session open).
3. Download `SpacePigeon.zip` from the GitHub release, exactly as a user would. Do not copy your build over.
4. Go through the README's installation steps: the "unidentified developer" warning, the Hammerspoon download, the Accessibility prompt, the default preset.
5. Delete the account afterwards, or keep it for the next release.

This is the only way to see the Gatekeeper warning, the permission prompts and a Hammerspoon that has never been set up.
