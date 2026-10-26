import Foundation

/// Which set of settings the app works on.
///
/// Without a profile (the default, and what every user gets) the config is
/// ~/.hammerspoon/spacepigeon_config.json and ~/.hammerspoon/lua/config.lua.
/// With `--profile <name>` (or SPACEPIGEON_PROFILE=<name>) the config, the
/// generated Lua and the log live in ~/.hammerspoon/spacepigeon_profiles/<name>/,
/// so a demo or test setup never touches your own presets.
///
/// Hammerspoon loads the profile named in ~/.hammerspoon/spacepigeon_profile
/// (see lua/profile.lua). Saving in a profile writes that file; saving
/// without a profile removes it, which switches back to your own setup.
enum Profile {
    /// The profile's name, or nil for your own setup.
    static let name: String? = {
        var value = ProcessInfo.processInfo.environment["SPACEPIGEON_PROFILE"]
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--profile"), i + 1 < args.count {
            value = args[i + 1]
        }
        guard let v = value?.trimmingCharacters(in: .whitespaces), !v.isEmpty, v != "default",
              v.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        return v
    }()

    static var hammerspoonDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hammerspoon")
    }

    /// Where this profile's files live: ~/.hammerspoon for your own setup.
    static var dir: URL {
        guard let name = name else { return hammerspoonDir }
        return hammerspoonDir.appendingPathComponent("spacepigeon_profiles/\(name)")
    }

    static var configJSON: URL {
        name == nil ? hammerspoonDir.appendingPathComponent("spacepigeon_config.json") : dir.appendingPathComponent("config.json")
    }

    static var configLua: URL {
        name == nil ? hammerspoonDir.appendingPathComponent("lua/config.lua") : dir.appendingPathComponent("config.lua")
    }

    static var log: URL { dir.appendingPathComponent("spacepigeon.log") }

    /// Names the profile Hammerspoon should load.
    static var marker: URL { hammerspoonDir.appendingPathComponent("spacepigeon_profile") }

    /// Makes Hammerspoon load this profile on its next reload.
    static func activate() {
        if let name = name {
            try? (name + "\n").write(to: marker, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: marker)
        }
    }

    /// The config a profile starts with when it has none yet.
    static func initialConfig() -> AppConfig {
        name == "demo" ? demoConfig() : ConfigManager.defaultConfig()
    }

    /// Sample presets for screenshots and recordings. Only apps that come
    /// with macOS, open in about a second and show nothing personal (no
    /// mail, notes, photos or browser tabs). Other apps are not quit, so
    /// recording a demo never closes your own work.
    ///
    /// Showcase has most features in one run: two Dictionary windows side by
    /// side, each opened on a word by a deep link (several windows of one
    /// app; Dictionary opens the second one with Cmd+N), fullscreen apps
    /// between the two desktops (each new one lands at the end and is dragged
    /// into place in Mission Control: three drags, four with one monitor),
    /// two-thirds and a custom position. Tips is centered on the second
    /// monitor, or fullscreen with one monitor (a mode). Meetings has thirds,
    /// Evening a fullscreen app first, two-thirds and a custom position.
    /// Switching between them moves the open windows instead of reopening
    /// them. Calculator cannot be resized, so it only goes where its size
    /// does not matter (a custom position).
    static func demoConfig() -> AppConfig {
        // The rows both Showcase layouts have, with the second desktop at `desktop2`.
        func showcaseRows(desktop2: Int) -> [AppLayout] {
            var calculator = AppLayout(name: "Calculator", monitor: "main", spaceIndex: desktop2, pos: "custom")
            calculator.frame = [0.77, 0.31, 0.13, 0.38] // in the right third, next to Clock
            return [
                AppLayout(name: "Dictionary", monitor: "main", spaceIndex: 1, pos: "left", url: "dict://pigeon", isBrowser: true),
                AppLayout(name: "Dictionary", monitor: "main", spaceIndex: 1, pos: "right", url: "dict://workspace", isBrowser: true),
                AppLayout(name: "Chess", monitor: "main", spaceIndex: 2, pos: "fullscreen"),
                AppLayout(name: "Stocks", monitor: "main", spaceIndex: 3, pos: "fullscreen"),
                AppLayout(name: "Font Book", monitor: "main", spaceIndex: 4, pos: "fullscreen"),
                AppLayout(name: "Clock", monitor: "main", spaceIndex: desktop2, pos: "left-two-thirds"),
                calculator,
            ]
        }
        var oneMonitor = showcaseRows(desktop2: 6)
        oneMonitor.insert(AppLayout(name: "Tips", monitor: "main", spaceIndex: 5, pos: "fullscreen"), at: 5)
        let showcase = Preset(key: "showcase", name: "Showcase", spaces: 5, secondarySpaces: 1,
                              layout: showcaseRows(desktop2: 5) + [
                                  AppLayout(name: "Tips", monitor: "secondary", spaceIndex: 1, pos: "center"),
                              ],
                              modes: [PresetMode(monitors: 1, spaces: 6, secondarySpaces: 0, layout: oneMonitor)],
                              focus: "Dictionary")

        let meetings = Preset(key: "meetings", name: "Meetings", spaces: 2, secondarySpaces: 0, layout: [
            AppLayout(name: "Clock", monitor: "main", spaceIndex: 1, pos: "left-third"),
            AppLayout(name: "Stocks", monitor: "main", spaceIndex: 1, pos: "center-third"),
            AppLayout(name: "Calculator", monitor: "main", spaceIndex: 1, pos: "right-third"),
            AppLayout(name: "Dictionary", monitor: "main", spaceIndex: 2, pos: "max"),
        ], focus: "Clock")

        var calculator = AppLayout(name: "Calculator", monitor: "main", spaceIndex: 2, pos: "custom")
        calculator.frame = [0.70, 0.20, 0.26, 0.60]
        let evening = Preset(key: "evening", name: "Evening", spaces: 2, secondarySpaces: 0, layout: [
            AppLayout(name: "Chess", monitor: "main", spaceIndex: 1, pos: "fullscreen"),
            AppLayout(name: "Tips", monitor: "main", spaceIndex: 2, pos: "left-two-thirds"),
            calculator,
        ], focus: "Tips")

        return AppConfig(
            presets: [showcase, meetings, evening],
            bindings: [
                KeyBinding(mods: ["cmd", "alt", "ctrl"], key: "1", presetKey: "showcase"),
                KeyBinding(mods: ["cmd", "alt", "ctrl"], key: "2", presetKey: "meetings"),
                KeyBinding(mods: ["cmd", "alt", "ctrl"], key: "3", presetKey: "evening"),
            ],
            keepAlive: [],
            quitOthers: false,
            saveBeforeQuit: [],
            menubar: true
        )
    }
}
