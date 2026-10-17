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
    /// with macOS and show nothing personal (no mail, notes, photos or
    /// browser tabs). Other apps are not quit, so recording a demo never
    /// closes your own work.
    static func demoConfig() -> AppConfig {
        let deepWork = Preset(key: "deep_work", name: "Deep Work", spaces: 3, secondarySpaces: 1, layout: [
            AppLayout(name: "Dictionary", monitor: "main", spaceIndex: 1, pos: "max"),
            AppLayout(name: "Font Book", monitor: "main", spaceIndex: 2, pos: "left"),
            AppLayout(name: "Tips", monitor: "main", spaceIndex: 2, pos: "right"),
            AppLayout(name: "Chess", monitor: "main", spaceIndex: 3, pos: "fullscreen"),
            AppLayout(name: "Clock", monitor: "secondary", spaceIndex: 1, pos: "max"),
        ], focus: "Font Book")
        var deepWorkWithMode = deepWork
        deepWorkWithMode.modes = [deepWork.newMode(monitors: 1)]

        let meetings = Preset(key: "meetings", name: "Meetings", spaces: 2, secondarySpaces: 0, layout: [
            AppLayout(name: "Clock", monitor: "main", spaceIndex: 1, pos: "left"),
            AppLayout(name: "Stocks", monitor: "main", spaceIndex: 1, pos: "right"),
            AppLayout(name: "Dictionary", monitor: "main", spaceIndex: 2, pos: "max"),
        ], focus: "Clock")

        let evening = Preset(key: "evening", name: "Evening", spaces: 2, secondarySpaces: 0, layout: [
            AppLayout(name: "Chess", monitor: "main", spaceIndex: 1, pos: "fullscreen"),
            AppLayout(name: "Tips", monitor: "main", spaceIndex: 2, pos: "left-two-thirds"),
            AppLayout(name: "Calculator", monitor: "main", spaceIndex: 2, pos: "right-third"),
        ], focus: "Tips")

        return AppConfig(
            presets: [deepWorkWithMode, meetings, evening],
            bindings: [
                KeyBinding(mods: ["cmd", "alt", "ctrl"], key: "1", presetKey: "deep_work"),
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
