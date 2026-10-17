import SwiftUI
import Cocoa

// MARK: - Data Models

/// The most monitors a preset can have spaces and apps on.
let maxMonitors = 10

/// Monitor number for a layout entry's `monitor`: "main" is 1, "secondary" is 2,
/// and monitors 3 to 10 are stored as their number ("3").
func monitorNumber(_ monitor: String) -> Int {
    switch monitor {
    case "main": return 1
    case "secondary": return 2
    default: return max(1, Int(monitor) ?? 1)
    }
}

func monitorKey(_ number: Int) -> String {
    switch number {
    case 1: return "main"
    case 2: return "secondary"
    default: return String(number)
    }
}

/// "Main", "2nd", "3rd", "4th", ...
func monitorLabel(_ number: Int) -> String {
    switch number {
    case 1: return "Main"
    case 2: return "2nd"
    case 3: return "3rd"
    default: return "\(number)th"
    }
}

/// Spaces per monitor (main first) with every app on a monitor past `keep`
/// moved to the main monitor, after its spaces, in monitor order. The same
/// way SpacePigeon handles monitors that are not connected.
func foldMonitors(spaces: [Int], layout: [AppLayout], keep: Int) -> (spaces: [Int], layout: [AppLayout]) {
    guard spaces.count > keep else { return (spaces, layout) }
    var mainTotal = spaces[0]
    var offset: [Int: Int] = [:]
    for n in (keep + 1)...spaces.count {
        offset[n] = mainTotal
        mainTotal += spaces[n - 1]
    }
    let folded = layout.map { app -> AppLayout in
        var a = app
        a.id = UUID()
        if let o = offset[monitorNumber(a.monitor)] {
            a.monitor = "main"
            a.spaceIndex += o
        }
        return a
    }
    var kept = Array(spaces.prefix(keep))
    kept[0] = mainTotal
    return (kept, folded)
}

struct AppLayout: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var monitor: String // "main", "secondary", or "3" to "10" (see monitorNumber)
    var spaceIndex: Int // 1-based index relative to the monitor
    var pos: String // "max", "fullscreen", or a part of the screen (see regions in lua/layout.lua)
    var url: String = "" // Optional URL/Deep link
    var isBrowser: Bool = false // New flag to indicate if advanced URL settings should be shown

    // Backwards compatibility for 'space' field (absolute index)
    // We'll map it during init if needed, but prefer the new structure.
    init(id: UUID = UUID(), name: String, monitor: String, spaceIndex: Int, pos: String, url: String = "", isBrowser: Bool = false) {
        self.id = id
        self.name = name
        self.monitor = monitor
        self.spaceIndex = spaceIndex
        self.pos = pos
        self.url = url
        self.isBrowser = isBrowser
    }

    enum CodingKeys: String, CodingKey {
        case name, monitor, spaceIndex, pos, url, isBrowser
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        pos = try container.decode(String.self, forKey: .pos)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        isBrowser = try container.decodeIfPresent(Bool.self, forKey: .isBrowser) ?? false

        // Try to decode new fields, fallback to legacy logic if missing
        if let m = try? container.decode(String.self, forKey: .monitor),
           let s = try? container.decode(Int.self, forKey: .spaceIndex) {
            monitor = m
            spaceIndex = s
        } else {
            monitor = "main"
            spaceIndex = 1
        }
    }
}

/// Spaces and layout used instead of the preset's own when this many
/// monitors are connected.
struct PresetMode: Codable, Identifiable, Hashable {
    var id = UUID()
    var monitors: Int
    var spaces: Int
    var secondarySpaces: Int
    var moreSpaces: [Int] = [] // monitors 3 and up
    var layout: [AppLayout]

    init(monitors: Int, spaces: Int, secondarySpaces: Int, moreSpaces: [Int] = [], layout: [AppLayout]) {
        self.monitors = monitors
        self.spaces = spaces
        self.secondarySpaces = secondarySpaces
        self.moreSpaces = moreSpaces
        self.layout = layout
    }

    enum CodingKeys: String, CodingKey {
        case monitors, spaces, secondarySpaces, moreSpaces, layout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monitors = try container.decode(Int.self, forKey: .monitors)
        spaces = try container.decode(Int.self, forKey: .spaces)
        secondarySpaces = try container.decodeIfPresent(Int.self, forKey: .secondarySpaces) ?? 0
        moreSpaces = try container.decodeIfPresent([Int].self, forKey: .moreSpaces) ?? []
        layout = try container.decode([AppLayout].self, forKey: .layout)
    }

    /// Spaces per monitor, main first.
    var monitorSpaces: [Int] {
        get { [spaces, secondarySpaces] + moreSpaces }
        set {
            spaces = newValue.first ?? 1
            secondarySpaces = newValue.count > 1 ? newValue[1] : 0
            moreSpaces = Array(newValue.dropFirst(2))
        }
    }

    var label: String { monitors == 1 ? "1 monitor" : "\(monitors) monitors" }
}

struct Preset: Codable, Identifiable, Hashable {
    var id = UUID()
    var key: String // Internal key for Lua table
    var name: String
    var spaces: Int // Main monitor spaces
    var secondarySpaces: Int // Secondary monitor spaces
    var moreSpaces: [Int] = [] // Spaces on monitors 3 and up
    var layout: [AppLayout]
    var modes: [PresetMode] // per monitor count; the fields above are the default
    var focus: String = "" // app to focus when the setup is done; empty = the first app

    init(id: UUID = UUID(), key: String, name: String, spaces: Int, secondarySpaces: Int, layout: [AppLayout], modes: [PresetMode] = [], focus: String = "") {
        self.id = id
        self.key = key
        self.name = name
        self.spaces = spaces
        self.secondarySpaces = secondarySpaces
        self.layout = layout
        self.modes = modes
        self.focus = focus
    }

    enum CodingKeys: String, CodingKey {
        case key, name, spaces, secondarySpaces, moreSpaces, layout, modes, focus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        name = try container.decode(String.self, forKey: .name)
        spaces = try container.decode(Int.self, forKey: .spaces)
        layout = try container.decode([AppLayout].self, forKey: .layout)
        secondarySpaces = try container.decodeIfPresent(Int.self, forKey: .secondarySpaces) ?? 0
        moreSpaces = try container.decodeIfPresent([Int].self, forKey: .moreSpaces) ?? []
        modes = try container.decodeIfPresent([PresetMode].self, forKey: .modes) ?? []
        focus = try container.decodeIfPresent(String.self, forKey: .focus) ?? ""
    }

    /// Every app name in the default layout and the modes, in order, once.
    var appNames: [String] {
        var seen = Set<String>()
        return (layout + modes.flatMap { $0.layout }).map { $0.name }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Spaces per monitor, main first.
    var monitorSpaces: [Int] {
        get { [spaces, secondarySpaces] + moreSpaces }
        set {
            spaces = newValue.first ?? 1
            secondarySpaces = newValue.count > 1 ? newValue[1] : 0
            moreSpaces = Array(newValue.dropFirst(2))
        }
    }

    /// A new mode for `monitors` monitors, starting from the default layout.
    /// The spaces and apps of monitors past that count go after the main
    /// monitor's, the same way SpacePigeon handles a monitor that is not connected.
    func newMode(monitors: Int) -> PresetMode {
        let folded = foldMonitors(spaces: monitorSpaces, layout: layout, keep: max(monitors, 1))
        var mode = PresetMode(monitors: monitors, spaces: 1, secondarySpaces: 0, layout: folded.layout)
        mode.monitorSpaces = folded.spaces
        return mode
    }
}

struct KeyBinding: Codable, Identifiable, Hashable {
    var id = UUID()
    var mods: [String] // e.g. ["cmd", "alt", "ctrl"]
    var key: String
    var presetKey: String

    enum CodingKeys: String, CodingKey {
        case mods, key, presetKey
    }
}

struct AppConfig: Codable {
    var presets: [Preset]
    var bindings: [KeyBinding]
    var keepAlive: [String]
    var quitOthers: Bool // quit apps that are not in the preset
    var reorderFullscreen: Bool // drag fullscreen apps into place in Mission Control
    // Space numbers are positions in Mission Control (desktops and fullscreen
    // apps counted together). Older configs numbered desktops only.
    var positionNumbering: Bool
    var saveBeforeQuit: [String] // apps that get Cmd+S in each window before they are quit
    var followMonitors: Bool // set up the last preset again when the monitor count changes
    var menubar: Bool // presets in the menu bar

    init(presets: [Preset], bindings: [KeyBinding], keepAlive: [String] = [], quitOthers: Bool = true, reorderFullscreen: Bool = true, positionNumbering: Bool = true, saveBeforeQuit: [String] = [], followMonitors: Bool = false, menubar: Bool = true) {
        self.presets = presets
        self.bindings = bindings
        self.keepAlive = keepAlive
        self.quitOthers = quitOthers
        self.reorderFullscreen = reorderFullscreen
        self.positionNumbering = positionNumbering
        self.saveBeforeQuit = saveBeforeQuit
        self.followMonitors = followMonitors
        self.menubar = menubar
    }

    enum CodingKeys: String, CodingKey {
        case presets, bindings, keepAlive, quitOthers, reorderFullscreen, positionNumbering, saveBeforeQuit, followMonitors, menubar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presets = try container.decode([Preset].self, forKey: .presets)
        bindings = try container.decode([KeyBinding].self, forKey: .bindings)
        keepAlive = try container.decodeIfPresent([String].self, forKey: .keepAlive) ?? []
        quitOthers = try container.decodeIfPresent(Bool.self, forKey: .quitOthers) ?? true
        reorderFullscreen = try container.decodeIfPresent(Bool.self, forKey: .reorderFullscreen) ?? true
        positionNumbering = try container.decodeIfPresent(Bool.self, forKey: .positionNumbering) ?? false
        saveBeforeQuit = try container.decodeIfPresent([String].self, forKey: .saveBeforeQuit) ?? []
        followMonitors = try container.decodeIfPresent(Bool.self, forKey: .followMonitors) ?? false
        menubar = try container.decodeIfPresent(Bool.self, forKey: .menubar) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(presets, forKey: .presets)
        try container.encode(bindings, forKey: .bindings)
        try container.encode(keepAlive, forKey: .keepAlive)
        try container.encode(quitOthers, forKey: .quitOthers)
        try container.encode(reorderFullscreen, forKey: .reorderFullscreen)
        try container.encode(positionNumbering, forKey: .positionNumbering)
        try container.encode(saveBeforeQuit, forKey: .saveBeforeQuit)
        try container.encode(followMonitors, forKey: .followMonitors)
        try container.encode(menubar, forKey: .menubar)
    }
}

// MARK: - Config Manager

class ConfigManager: ObservableObject {
    @Published var config: AppConfig
    @Published var saveStatus: String = ""

    init() {
        self.config = AppConfig(presets: [], bindings: [])
        loadConfig()
    }

    var configPath: URL { Profile.configJSON }

    func loadConfig() {
        if FileManager.default.fileExists(atPath: configPath.path),
           let data = try? Data(contentsOf: configPath),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            var loaded = decoded
            if !loaded.positionNumbering {
                ConfigManager.migrateToPositions(&loaded)
            }
            self.config = loaded
        } else {
            self.config = Profile.initialConfig()
        }
    }

    func save() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let hsDir = home.appendingPathComponent(".hammerspoon")
        if !FileManager.default.fileExists(atPath: hsDir.path) {
            try? FileManager.default.createDirectory(at: hsDir, withIntermediateDirectories: true)
        }

        try? FileManager.default.createDirectory(at: configPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(config) {
            try? data.write(to: configPath)
        }

        let lua = generateLua(from: config)
        // The Lua side loads `lua.config`, i.e. ~/.hammerspoon/lua/config.lua,
        // or the active profile's config.lua (see Profile).
        let luaPath = Profile.configLua
        try? FileManager.default.createDirectory(at: luaPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        do {
            try lua.write(to: luaPath, atomically: true, encoding: .utf8)
            // Bring the installed runtime Lua in line with this app build, so new
            // config options are understood after a rebuild. Never touches config.lua.
            let updated = BundleInstaller.installRuntimeFiles()
            Profile.activate()
            saveStatus = updated.isEmpty
                ? "Saved & Reloading..."
                : "Saved, updated \(updated.count) runtime file(s) & Reloading..."
            reloadHammerspoon()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.saveStatus = "Done"
            }
        } catch {
            saveStatus = "Error: \(error.localizedDescription)"
        }
    }

    static func defaultConfig() -> AppConfig {
        return AppConfig(
            presets: [
                Preset(key: "standard", name: "Standard", spaces: 3, secondarySpaces: 1, layout: [
                    AppLayout(name: "Safari", monitor: "main", spaceIndex: 1, pos: "max"),
                    AppLayout(name: "Terminal", monitor: "main", spaceIndex: 2, pos: "left"),
                    AppLayout(name: "Notes", monitor: "main", spaceIndex: 2, pos: "right"),
                    AppLayout(name: "Music", monitor: "main", spaceIndex: 3, pos: "max")
                ])
            ],
            bindings: [
                KeyBinding(mods: ["cmd", "alt", "ctrl"], key: "S", presetKey: "standard")
            ],
            keepAlive: ["Spotify"]
        )
    }

    /// Converts old numbering (space = desktop number; for a fullscreen app,
    /// the desktop it comes after) to positions in Mission Control, so every
    /// preset keeps the same layout. The monitor's space count becomes the
    /// total of desktops and fullscreen apps.
    static func migrateToPositions(_ config: inout AppConfig) {
        for pi in config.presets.indices {
            for monitor in ["main", "secondary"] {
                let original = config.presets[pi].layout.map { $0.spaceIndex }
                let indices = config.presets[pi].layout.indices.filter { config.presets[pi].layout[$0].monitor == monitor }
                if indices.isEmpty { continue }
                let desktops = max(monitor == "main" ? config.presets[pi].spaces : config.presets[pi].secondarySpaces, 1)

                var position = 0
                var desktopPosition: [Int: Int] = [:]
                for k in 1...desktops {
                    position += 1
                    desktopPosition[k] = position
                    for i in indices where config.presets[pi].layout[i].pos == "fullscreen" {
                        if min(max(original[i], 1), desktops) == k {
                            position += 1
                            config.presets[pi].layout[i].spaceIndex = position
                        }
                    }
                }
                for i in indices where config.presets[pi].layout[i].pos != "fullscreen" {
                    let k = original[i]
                    config.presets[pi].layout[i].spaceIndex = desktopPosition[k] ?? (position + max(k - desktops, 1))
                }
                if monitor == "main" {
                    config.presets[pi].spaces = position
                } else {
                    config.presets[pi].secondarySpaces = position
                }
            }
        }
        config.positionNumbering = true
    }

    /// A Lua string literal.
    func luaString(_ s: String) -> String {
        var out = "\""
        for c in s {
            switch c {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\r\n": out += "\\r\\n"
            default: out.append(c)
            }
        }
        return out + "\""
    }

    /// `{ main = 3, secondary = 1, [3] = 2 }`
    func spacesLua(_ monitorSpaces: [Int]) -> String {
        var parts = ["main = \(monitorSpaces.first ?? 1)", "secondary = \(monitorSpaces.count > 1 ? monitorSpaces[1] : 0)"]
        for (i, n) in monitorSpaces.enumerated() where i >= 2 {
            parts.append("[\(i + 1)] = \(n)")
        }
        return "{ " + parts.joined(separator: ", ") + " }"
    }

    func generateLua(from config: AppConfig) -> String {
        var lua = "local M = {}\n\n"

        lua += "-- Apps to keep alive when switching modes (e.g. Spotify)\n"
        lua += "M.keepAlive = {\n"
        for app in config.keepAlive {
            lua += "  \(luaString(app)),\n"
        }
        lua += "}\n\n"

        lua += "-- Apps that get Cmd+S in each window before SpacePigeon quits them\n"
        lua += "M.saveBeforeQuit = {\n"
        for app in config.saveBeforeQuit {
            lua += "  \(luaString(app)),\n"
        }
        lua += "}\n\n"

        lua += "-- Quit apps that are not in the preset (apps in the preset are moved, never quit)\n"
        lua += "M.quitOthers = \(config.quitOthers ? "true" : "false")\n\n"
        lua += "-- If a window refuses to move, quit that app normally and relaunch it on its Space\n"
        lua += "M.killFallback = true\n\n"
        lua += "-- Put fullscreen apps right after their desktop by dragging them in Mission Control\n"
        lua += "M.reorderFullscreen = \(config.reorderFullscreen ? "true" : "false")\n\n"
        lua += "-- Set up the last preset again (without quitting apps) when the monitor count changes\n"
        lua += "M.followMonitors = \(config.followMonitors ? "true" : "false")\n\n"
        lua += "-- Presets in the menu bar\n"
        lua += "M.menubar = \(config.menubar ? "true" : "false")\n\n"
        if config.positionNumbering {
            lua += "-- Space numbers are positions in Mission Control (desktops and fullscreen apps together)\n"
            lua += "M.numbering = \"position\"\n\n"
        }

        lua += "local presets = {\n"
        for preset in config.presets {
            let key = preset.key.isEmpty ? "preset_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))" : preset.key
            lua += "  [\(luaString(key))] = {\n"
            lua += "    name   = \(luaString(preset.name)),\n"
            lua += "    spaces = \(spacesLua(preset.monitorSpaces)),\n"
            lua += "    layout = {\n"
            lua += layoutLua(preset.layout, indent: "      ")
            lua += "    },\n"
            if !preset.modes.isEmpty {
                lua += "    -- Used instead of spaces/layout above when this many monitors are connected\n"
                lua += "    modes = {\n"
                for mode in preset.modes {
                    lua += "      { monitors = \(mode.monitors), spaces = \(spacesLua(mode.monitorSpaces)), layout = {\n"
                    lua += layoutLua(mode.layout, indent: "        ")
                    lua += "      } },\n"
                }
                lua += "    },\n"
            }
            if !preset.focus.isEmpty {
                lua += "    -- App to focus when the setup is done\n"
                lua += "    focus = \(luaString(preset.focus)),\n"
            }
            lua += "  },\n"
        }
        lua += "}\n\n"

        lua += "M.presets = presets\n\n"
        lua += "M.bindings = {\n"
        for binding in config.bindings {
            let modsString = binding.mods.map { luaString($0) }.joined(separator: ", ")
            lua += "  { mods = {\(modsString)}, key = \(luaString(binding.key)), preset = presets[\(luaString(binding.presetKey))] },\n"
        }
        lua += "}\n\n"
        lua += "return M"
        return lua
    }

    func layoutLua(_ layout: [AppLayout], indent: String) -> String {
        var lua = ""
        for item in layout where !item.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let urlPart = item.url.isEmpty ? "" : ", url = \(luaString(item.url))"
            lua += "\(indent){ name = \(luaString(item.name)), monitor = \(luaString(item.monitor)), space = \(item.spaceIndex), pos = \(luaString(item.pos))\(urlPart) },\n"
        }
        return lua
    }

    func reloadHammerspoon() {
        if let url = URL(string: "hammerspoon://reloadConfig") {
            NSWorkspace.shared.open(url)
        }

        let source = """
        tell application "Hammerspoon"
            execute lua code "hs.reload()"
        end tell
        """
        if let script = NSAppleScript(source: source) {
            var errorDict: NSDictionary?
            script.executeAndReturnError(&errorDict)
            if errorDict == nil {
                // Success
            }
        }
    }
}

// MARK: - Views

struct ConfigView: View {
    @StateObject var manager = ConfigManager()

    var body: some View {
        VStack {
            TabView {
                PresetsListView(config: $manager.config)
                    .tabItem { Label("Presets", systemImage: "list.bullet") }

                BindingsListView(config: $manager.config)
                    .tabItem { Label("Bindings", systemImage: "keyboard") }

                GeneralSettingsView(config: $manager.config)
                    .tabItem { Label("General", systemImage: "gear") }
            }

            HStack {
                Text(manager.saveStatus)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Save & Reload Hammerspoon") {
                    manager.save()
                }
            }
            .padding()
        }
        .frame(minWidth: 800, minHeight: 600)
        .padding()
    }
}

struct PresetsListView: View {
    @Binding var config: AppConfig
    @State private var selectedPresetId: UUID?

    func duplicateSelected() {
        guard let id = selectedPresetId, let index = config.presets.firstIndex(where: { $0.id == id }) else { return }
        var copy = config.presets[index]
        copy.id = UUID()
        copy.key = "preset_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        copy.name += " Copy"
        config.presets.insert(copy, at: index + 1)
        selectedPresetId = copy.id
    }

    var body: some View {
        HSplitView {
            VStack {
                List(selection: $selectedPresetId) {
                    ForEach(config.presets) { preset in
                        Text(preset.name)
                            .tag(preset.id)
                    }
                    .onDelete { indices in
                        config.presets.remove(atOffsets: indices)
                    }
                }
                HStack {
                    Button("+") {
                        let newKey = "preset_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
                        let new = Preset(key: newKey, name: "New Preset", spaces: 1, secondarySpaces: 0, layout: [])
                        config.presets.append(new)
                        selectedPresetId = new.id
                    }
                    Button("-") {
                        if let id = selectedPresetId, let index = config.presets.firstIndex(where: { $0.id == id }) {
                            config.presets.remove(at: index)
                            selectedPresetId = nil
                        }
                    }
                    .disabled(selectedPresetId == nil)
                    Button(action: duplicateSelected) {
                        Image(systemName: "plus.square.on.square")
                    }
                    .help("Duplicate this preset")
                    .disabled(selectedPresetId == nil)
                    Spacer()
                }
                .padding(5)
            }
            .frame(minWidth: 150, maxWidth: 200)
            .onAppear {
                if selectedPresetId == nil { selectedPresetId = config.presets.first?.id }
            }

            if let index = config.presets.firstIndex(where: { $0.id == selectedPresetId }) {
                PresetEditor(preset: $config.presets[index])
                    .id(config.presets[index].id)
                    .padding()
            } else {
                Text("Select a preset to edit")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct AppSettingsView: View {
    @Binding var app: AppLayout
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Advanced Settings for \(app.name)")
                .font(.headline)

            Divider()

            Toggle("Is this a Browser?", isOn: $app.isBrowser)
                .toggleStyle(.checkbox)

            if app.isBrowser {
                VStack(alignment: .leading) {
                    Text("Startup URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("https://example.com", text: $app.url)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.leading, 20)
            } else {
                Text("Only enable this if you want this app to open a specific URL/Deep Link instead of just launching.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    if !app.isBrowser {
                        app.url = ""
                    }
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .padding()
        .frame(width: 400, height: 250)
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}

struct MinimalistTextField: View {
    var placeholder: String
    @Binding var text: String
    var align: TextAlignment = .leading

    @FocusState private var isFocused: Bool
    @State private var isHovering: Bool = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(align)
            .focused($isFocused)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .opacity(isFocused ? 1.0 : (isHovering ? 0.5 : 0.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isFocused ? Color.accentColor.opacity(0.6) : (isHovering ? Color.secondary.opacity(0.2) : Color.clear), lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.03))
            )
            .onHover { hover in isHovering = hover }
    }
}

struct PresetEditor: View {
    @Binding var preset: Preset
    // 0 = the default layout, otherwise the monitor count of a mode.
    @State private var selectedMode = 0

    var modeIndex: Int? { preset.modes.firstIndex(where: { $0.monitors == selectedMode }) }

    var body: some View {
        if let i = modeIndex {
            LayoutEditor(monitorSpaces: $preset.modes[i].monitorSpaces,
                         layout: $preset.modes[i].layout, singleMonitor: selectedMode == 1) { header }
                .id(selectedMode)
        } else {
            LayoutEditor(monitorSpaces: $preset.monitorSpaces,
                         layout: $preset.layout, singleMonitor: false) { header }
                .id(0)
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preset Name")
                    .font(.headline)
                    .foregroundColor(.secondary)
                MinimalistTextField(placeholder: "Standard", text: $preset.name)
                    .font(.title3)
            }

            HStack(spacing: 12) {
                Picker("", selection: $selectedMode) {
                    Text("Default").tag(0)
                    ForEach(preset.modes) { mode in
                        Text(mode.label).tag(mode.monitors)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                let missing = (1...maxMonitors).filter { n in !preset.modes.contains { $0.monitors == n } }
                Menu {
                    ForEach(missing, id: \.self) { n in
                        Button(n == 1 ? "1 monitor" : "\(n) monitors") {
                            preset.modes.append(preset.newMode(monitors: n))
                            preset.modes.sort { $0.monitors < $1.monitors }
                            selectedMode = n
                        }
                    }
                } label: {
                    Label("Add Mode", systemImage: "plus")
                }
                .fixedSize()
                .disabled(missing.isEmpty)
                .help("Use a different layout when this many monitors are connected")

                if let i = modeIndex {
                    Button(action: {
                        preset.modes.remove(at: i)
                        selectedMode = 0
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Remove this mode")
                }
                Spacer()
            }

            Text(modeCaption)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text("Focus When Done")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: $preset.focus) {
                    Text("First app").tag("")
                    let names = preset.appNames
                    ForEach(names, id: \.self) { name in
                        Text(name).tag(name)
                    }
                    if !preset.focus.isEmpty && !names.contains(preset.focus) {
                        Text("\(preset.focus) (not in layout)").tag(preset.focus)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            .help("The app that has focus when the setup is complete. \"First app\" focuses the first app on the main monitor's first space.")
        }
    }

    var modeCaption: String {
        if let i = modeIndex {
            return selectedMode == 1
                ? "Used when only one monitor is connected."
                : "Used when \(preset.modes[i].label) are connected."
        }
        if preset.modes.isEmpty {
            return "Used with any number of monitors. Add a mode to use a different layout when a given number of monitors is connected."
        }
        return "Used when no mode matches the number of connected monitors."
    }
}

/// Spaces and apps of one layout: the preset's default or one of its modes.
struct LayoutEditor<Header: View>: View {
    @Binding var monitorSpaces: [Int] // main first; always at least main and 2nd
    @Binding var layout: [AppLayout]
    var singleMonitor: Bool
    @ViewBuilder var header: Header
    @State private var pickingNewAppId: UUID? = nil
    // Kept in @State but not observed here: the rows and the drag ghost
    // observe them, so a mouse move redraws only the ghost.
    @State private var drag = RowDragState()
    @State private var ghost = GhostPosition()
    @State private var rowHeight: CGFloat = 50
    private let rowSpacing: CGFloat = 10
    /// Width of the handle column at the left of each row.
    private let handleZone: CGFloat = 40

    /// Drags a row by its handle. A copy of the row (the ghost) follows the
    /// mouse, and the row takes the next slot once the ghost is more than
    /// halfway over it. The gesture is on the whole list, so it keeps
    /// tracking while the rows move.
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("appList"))
            .onChanged { value in
                let step = rowHeight + rowSpacing
                if drag.id == nil {
                    guard value.startLocation.x < handleZone else { return }
                    let index = Int(value.startLocation.y / step)
                    guard layout.indices.contains(index) else { return }
                    ghost.app = layout[index]
                    ghost.image = snapshotRow(at: index)
                    ghost.shift = 0
                    ghost.offset = 0
                    drag.id = layout[index].id
                    NSCursor.closedHand.push()
                }
                guard let id = drag.id, var index = layout.firstIndex(where: { $0.id == id }) else { return }
                var offset = value.translation.height - ghost.shift
                while offset > step / 2 && index < layout.count - 1 {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        layout.swapAt(index, index + 1)
                    }
                    index += 1
                    ghost.shift += step
                    offset -= step
                }
                while offset < -step / 2 && index > 0 {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        layout.swapAt(index, index - 1)
                    }
                    index -= 1
                    ghost.shift -= step
                    offset += step
                }
                ghost.slotY = CGFloat(index) * step
                ghost.offset = offset
            }
            .onEnded { _ in
                guard drag.id != nil else { return }
                NSCursor.pop()
                // Let the ghost settle into the slot, then show the row again.
                withAnimation(.easeOut(duration: 0.15)) {
                    ghost.offset = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    drag.id = nil
                    ghost.app = nil
                    ghost.image = nil
                }
            }
    }

    /// A picture of the row at `index`, taken from the window, so the ghost
    /// looks exactly like the row (its controls are AppKit views, which
    /// SwiftUI's own renderer cannot draw).
    func snapshotRow(at index: Int) -> NSImage? {
        guard let window = NSApp.keyWindow, let view = window.contentView, ghost.listFrame != .zero else { return nil }
        let step = rowHeight + rowSpacing
        var rect = CGRect(x: ghost.listFrame.minX + 1, y: ghost.listFrame.minY + 1 + CGFloat(index) * step,
                          width: ghost.listFrame.width - 2, height: rowHeight)
        // SwiftUI's global space starts at the top of the window, title bar
        // included; the content view starts below the title bar.
        rect.origin.y -= window.frame.height - view.frame.height
        if !view.isFlipped {
            rect.origin.y = view.bounds.height - rect.maxY
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: rep)
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }

    var monitorCount: Int { singleMonitor ? 1 : max(monitorSpaces.count, 2) }

    func spaces(of monitor: Int) -> Int {
        monitor <= monitorSpaces.count ? monitorSpaces[monitor - 1] : 0
    }

    func spacesBinding(_ monitor: Int) -> Binding<Int> {
        Binding(
            get: { spaces(of: monitor) },
            set: { value in
                while monitorSpaces.count < monitor { monitorSpaces.append(0) }
                monitorSpaces[monitor - 1] = value
            }
        )
    }

    func addMonitor() {
        while monitorSpaces.count < 2 { monitorSpaces.append(0) }
        monitorSpaces.append(1)
    }

    /// Removes the last monitor. Its apps go after the main monitor's spaces,
    /// the same way SpacePigeon handles a monitor that is not connected.
    func removeLastMonitor() {
        let folded = foldMonitors(spaces: monitorSpaces, layout: layout, keep: monitorSpaces.count - 1)
        withAnimation {
            monitorSpaces = folded.spaces
            layout = folded.layout
        }
    }

    func monitorTitle(_ monitor: Int) -> String {
        if singleMonitor { return "Spaces" }
        switch monitor {
        case 1: return "Main Monitor Spaces"
        case 2: return "Secondary Monitor Spaces"
        default: return "\(monitorLabel(monitor)) Monitor Spaces"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                header

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 10) {
                    ForEach(1...monitorCount, id: \.self) { monitor in
                        VStack(alignment: .leading) {
                            HStack(spacing: 4) {
                                Text(monitorTitle(monitor))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if monitor > 2 && monitor == monitorCount {
                                    Button(action: removeLastMonitor) {
                                        Image(systemName: "minus.circle")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove this monitor. Its apps go after the main monitor's spaces.")
                                }
                            }
                            Stepper(value: spacesBinding(monitor), in: (monitor == 1 ? 1 : 0)...32) {
                                Text("\(spaces(of: monitor))")
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minWidth: 20)
                            }
                        }
                    }
                    if !singleMonitor && monitorCount < maxMonitors {
                        Button(action: addMonitor) {
                            Label("Add Monitor", systemImage: "plus")
                        }
                        .help("Add spaces and apps for monitor \(monitorCount + 1). Monitors are numbered from the main one, then left to right.")
                    }
                }
                .help("Number of spaces in Mission Control: desktops and fullscreen apps together")

                LayoutPreviewView(monitorSpaces: Array((0..<monitorCount).map { spaces(of: $0 + 1) }), layout: layout, singleMonitor: singleMonitor)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            Divider()

            HStack {
                Text("Applications Layout")
                    .font(.headline)
                Spacer()
                Button(action: {
                    let new = AppLayout(name: "", monitor: "main", spaceIndex: 1, pos: "max")
                    layout.append(new)
                    pickingNewAppId = new.id
                }) {
                    Label("Add App", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                VStack(spacing: rowSpacing) {
                    if layout.isEmpty {
                        Text("No apps configured")
                            .foregroundColor(.secondary)
                            .padding(.top, 20)
                    }

                    ForEach($layout) { $app in
                        AppRowView(
                            app: $app,
                            singleMonitor: singleMonitor,
                            monitorCount: monitorCount,
                            maxSpaces: max(1, spaces(of: monitorNumber(app.monitor))),
                            pickOnAppear: pickingNewAppId == app.id,
                            onDelete: { id in layout.removeAll { $0.id == id } }
                        )
                        .equatable()
                        .background(GeometryReader { geo in
                            Color.clear.onAppear { rowHeight = geo.size.height }
                        })
                        .modifier(HiddenWhileDragged(drag: drag, id: app.id))
                    }
                }
                .padding(1)
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { ghost.listFrame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, frame in ghost.listFrame = frame }
                })
                .overlay(alignment: .topLeading) {
                    DragGhostLayer(drag: drag, ghost: ghost, singleMonitor: singleMonitor, rowHeight: rowHeight)
                }
                .coordinateSpace(name: "appList")
                .simultaneousGesture(dragGesture)
            }
        }
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}

/// Window positions, in menu groups: (tag, label, icon).
let positionGroups: [[(tag: String, label: String, icon: String)]] = [
    [("max", "Max", "rectangle.fill"),
     ("fullscreen", "Fullscreen", "arrow.up.left.and.arrow.down.right")],
    [("left", "Left", "rectangle.lefthalf.inset.filled"),
     ("right", "Right", "rectangle.righthalf.inset.filled"),
     ("top", "Top", "rectangle.tophalf.inset.filled"),
     ("bottom", "Bottom", "rectangle.bottomhalf.inset.filled")],
    [("left-third", "Left Third", "rectangle.leadingthird.inset.filled"),
     ("center-third", "Center Third", "rectangle.split.3x1"),
     ("right-third", "Right Third", "rectangle.trailingthird.inset.filled"),
     ("left-two-thirds", "Left Two Thirds", "rectangle.leadinghalf.inset.filled"),
     ("right-two-thirds", "Right Two Thirds", "rectangle.trailinghalf.inset.filled")],
    [("top-left", "Top Left", "rectangle.inset.topleft.filled"),
     ("top-right", "Top Right", "rectangle.inset.topright.filled"),
     ("bottom-left", "Bottom Left", "rectangle.inset.bottomleft.filled"),
     ("bottom-right", "Bottom Right", "rectangle.inset.bottomright.filled")],
    [("center", "Center", "rectangle.center.inset.filled")],
]

func positionOption(_ tag: String) -> (label: String, icon: String) {
    for group in positionGroups {
        if let o = group.first(where: { $0.tag == tag }) { return (o.label, o.icon) }
    }
    return (tag, "rectangle")
}

/// The row being dragged. The list rows observe only this, so they redraw
/// when a drag starts or ends, not on every mouse move.
final class RowDragState: ObservableObject {
    @Published var id: UUID?
}

/// Where the drag ghost is: the dragged row's slot plus how far the mouse
/// moved from it. Only DragGhostLayer observes this.
final class GhostPosition: ObservableObject {
    @Published var offset: CGFloat = 0
    @Published var slotY: CGFloat = 0
    var app: AppLayout?
    /// A picture of the dragged row; GhostRow is drawn when there is none.
    var image: NSImage?
    /// The list's frame in the window, kept up to date while scrolling.
    var listFrame: CGRect = .zero
    /// Translation already used up by moving the row to other slots.
    var shift: CGFloat = 0
}

/// Keeps the dragged row's slot in the list, empty, while its ghost moves.
struct HiddenWhileDragged: ViewModifier {
    @ObservedObject var drag: RowDragState
    let id: UUID

    func body(content: Content) -> some View {
        let dragging = drag.id == id
        return content
            .opacity(dragging ? 0 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(dragging ? 0.35 : 0), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
    }
}

/// The copy of the dragged row that follows the mouse.
struct DragGhostLayer: View {
    @ObservedObject var drag: RowDragState
    @ObservedObject var ghost: GhostPosition
    let singleMonitor: Bool
    let rowHeight: CGFloat

    var body: some View {
        if drag.id != nil, let app = ghost.app {
            Group {
                if let image = ghost.image {
                    Image(nsImage: image)
                } else {
                    GhostRow(app: app, singleMonitor: singleMonitor, height: rowHeight)
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 6, y: 4)
            .offset(x: 1, y: ghost.slotY + ghost.offset + 1)
            .allowsHitTesting(false)
        }
    }
}

/// A row drawn only with SwiftUI shapes and text, so it is cheap to move:
/// the real row's text field, menus and steppers are AppKit views.
struct GhostRow: View {
    let app: AppLayout
    let singleMonitor: Bool
    var height: CGFloat? = nil // the real row's height, so nothing jumps

    func pill<C: View>(width: CGFloat, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 4) {
            content()
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: 22)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
    }

    var body: some View {
        let position = positionOption(app.pos)
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 16, height: 24)

            HStack(spacing: 8) {
                AppIconView(name: app.name)
                Text(app.name.isEmpty ? "App Name" : app.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(app.name.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.03)))
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundColor(app.isBrowser ? .accentColor : .secondary.opacity(0.7))
            }
            .frame(width: 200, alignment: .leading)

            Divider().frame(height: 20)

            if !singleMonitor {
                pill(width: 75) { Text(monitorLabel(monitorNumber(app.monitor))) }
            }

            HStack(spacing: 2) {
                Text("Sp").font(.caption).foregroundColor(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 24)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                Text("\(app.spaceIndex)")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 20, alignment: .center)
            }

            pill(width: 150) {
                Image(systemName: position.icon)
                Text(position.label)
            }

            Spacer()

            Image(systemName: "trash")
                .font(.system(size: 12))
                .foregroundColor(.red.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .padding(.vertical, height == nil ? 8 : 0)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
    }
}

/// One app in the layout. Equatable on its data, so moving other rows
/// (or a drag) does not redraw it.
struct AppRowView: View, Equatable {
    @Binding var app: AppLayout
    let singleMonitor: Bool
    let monitorCount: Int
    let maxSpaces: Int
    let pickOnAppear: Bool
    let onDelete: (UUID) -> Void
    @State private var picking = false
    @State private var editing = false

    static func == (l: AppRowView, r: AppRowView) -> Bool {
        l.app == r.app && l.singleMonitor == r.singleMonitor && l.monitorCount == r.monitorCount
            && l.maxSpaces == r.maxSpaces && l.pickOnAppear == r.pickOnAppear
    }

    var body: some View {
        HStack(spacing: 12) {
            DragHandle()
                .help("Drag to reorder")

            HStack(spacing: 8) {
                AppIconView(name: app.name)
                MinimalistTextField(placeholder: "App Name", text: $app.name)
                    .font(.system(size: 14, weight: .medium))

                Button(action: { picking = true }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Choose from your apps")
                .popover(isPresented: $picking) {
                    AppPickerView { name in
                        app.name = name
                        picking = false
                    }
                }

                Button(action: { editing = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundColor(app.isBrowser ? .accentColor : .secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $editing) {
                    AppSettingsView(app: $app)
                }
            }
            .frame(width: 200, alignment: .leading)

            Divider()
                .frame(height: 20)

            if !singleMonitor {
                Picker("", selection: $app.monitor) {
                    ForEach(1...monitorCount, id: \.self) { n in
                        Text(monitorLabel(n)).tag(monitorKey(n))
                    }
                }
                .frame(width: 75)
                .labelsHidden()
            }

            HStack(spacing: 2) {
                Text("Sp")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Stepper("", value: $app.spaceIndex, in: 1...max(maxSpaces, app.spaceIndex))
                    .labelsHidden()
                Text("\(app.spaceIndex)")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 20, alignment: .center)
            }
            // Position in Mission Control, desktops and fullscreen apps counted together.
            .help(app.pos == "fullscreen" ? "Position of this fullscreen app in Mission Control, counting desktops and fullscreen apps from the left" : "Position of this app's desktop in Mission Control, counting desktops and fullscreen apps from the left")

            Picker("", selection: $app.pos) {
                ForEach(positionGroups.indices, id: \.self) { g in
                    if g > 0 { Divider() }
                    ForEach(positionGroups[g], id: \.tag) { o in
                        Label(o.label, systemImage: o.icon).tag(o.tag)
                    }
                }
            }
            .frame(width: 150)
            .labelsHidden()

            Spacer()

            Button(action: { onDelete(app.id) }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
        )
        .onAppear { if pickOnAppear { picking = true } }
    }
}

/// The three lines a row is dragged by.
struct DragHandle: View {
    @State private var hovering = false

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary.opacity(hovering ? 1 : 0.6))
            .frame(width: 16, height: 24)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
    }
}

struct BindingsListView: View {
    @Binding var config: AppConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Key Bindings")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 4)

            HStack(spacing: 12) {
                Text("Modifiers")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.secondary)
                    .frame(width: 160, alignment: .leading)
                Text("Key")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .center)
                Text("Target Preset")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 20)
            }
            .padding(.horizontal, 12)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($config.bindings) { $binding in
                        HStack(spacing: 12) {
                            MinimalistTextField(placeholder: "Cmd, Alt...", text: Binding(
                                get: { binding.mods.joined(separator: ", ") },
                                set: { binding.mods = $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                            ))
                            .frame(width: 160)

                            MinimalistTextField(placeholder: "K", text: $binding.key, align: .center)
                                .frame(width: 50)

                            Picker("", selection: $binding.presetKey) {
                                ForEach(config.presets, id: \.key) { preset in
                                    Text(preset.name).tag(preset.key)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)

                            Button(action: {
                                if let index = config.bindings.firstIndex(where: { $0.id == binding.id }) {
                                    config.bindings.remove(at: index)
                                }
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                    }
                }
            }
            .background(Color(NSColor.windowBackgroundColor))

            Button(action: {
                let firstKey = config.presets.first?.key ?? ""
                config.bindings.append(KeyBinding(mods: ["cmd", "alt", "ctrl"], key: "A", presetKey: firstKey))
            }) {
                Label("Add Binding", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .padding()
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}

struct GeneralSettingsView: View {
    @Binding var config: AppConfig

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Global Settings")
                    .font(.headline)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Quit apps that are not in the preset", isOn: $config.quitOthers)
                        .toggleStyle(.checkbox)
                    Text("Apps that are in the preset are never quit: their windows are moved to their space instead.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Put fullscreen apps right after their desktop", isOn: $config.reorderFullscreen)
                        .toggleStyle(.checkbox)
                    Text("macOS always adds fullscreen apps at the end. When this is on, SpacePigeon drags them into place in Mission Control (the mouse moves for a moment). When off, they stay at the end, in order.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Rearrange when a monitor is plugged in or unplugged", isOn: $config.followMonitors)
                        .toggleStyle(.checkbox)
                    Text("Sets up the last used preset again for the new number of monitors (using its mode for that count, if it has one). No apps are quit; windows are only moved.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show presets in the menu bar", isOn: $config.menubar)
                        .toggleStyle(.checkbox)
                    Text("A menu bar icon to set up any preset with a click.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                AppListEditor(
                    title: "Keep Alive Apps",
                    caption: "These apps will not be closed when switching presets. They will be moved to their assigned space if applicable.",
                    placeholder: "App Name (e.g. Spotify)",
                    apps: $config.keepAlive
                )

                AppListEditor(
                    title: "Save Before Quitting",
                    caption: "Before SpacePigeon quits one of these apps (when a preset without it is set up), it presses Cmd+S in each of its windows. Documents that were never saved are left alone: the app asks about them when it quits. Leave out browsers and other apps where Cmd+S does something else.",
                    placeholder: "App Name (e.g. TextEdit)",
                    apps: $config.saveBeforeQuit
                )
            }
            .padding()
        }
    }
}

/// A list of app names with a trash button per row and a field to add one.
struct AppListEditor: View {
    let title: String
    let caption: String
    let placeholder: String
    @Binding var apps: [String]
    @State private var newAppName: String = ""
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.subheadline)
                .bold()
            Text(caption)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(apps, id: \.self) { appName in
                    HStack {
                        AppIconView(name: appName, size: 16)
                        Text(appName)
                        Spacer()
                        Button(action: {
                            apps.removeAll { $0 == appName }
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(appName)")
                    }
                }
            }
            .frame(height: 120)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))

            HStack {
                TextField(placeholder, text: $newAppName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)

                Button("Add", action: add)
                    .disabled(newAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Choose…") { picking = true }
                    .help("Choose from your apps")
                    .popover(isPresented: $picking) {
                        AppPickerView { name in
                            if !apps.contains(name) { apps.append(name) }
                            picking = false
                        }
                    }
            }
        }
    }

    private func add() {
        let name = newAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && !apps.contains(name) {
            apps.append(name)
            newAppName = ""
        }
    }
}

// MARK: - Layout preview

struct LayoutPreview {
    var parts: [String]
    var warnings: [String]
}

/// Same rules as lua/slots.lua: space numbers are positions in Mission Control,
/// counting desktops and fullscreen apps together. Every position without a
/// fullscreen app is a desktop.
// (Not called previewLayout: SwiftUI views already have a modifier with that name.)
func spacesPreview(total: Int, apps: [AppLayout]) -> LayoutPreview {
    var last = total
    var warnings: [String] = []
    var fsAt: [Int: [AppLayout]] = [:]
    var normalAt: [Int: [AppLayout]] = [:]
    for a in apps {
        let n = max(1, a.spaceIndex)
        if a.pos == "fullscreen" {
            fsAt[n, default: []].append(a)
        } else {
            normalAt[n, default: []].append(a)
        }
        if n > last {
            last = n
            warnings.append("\(a.name) is at space \(n), but there are only \(total) spaces; more are added")
        }
    }

    var parts: [String] = []
    var desktops = 0
    var waiting: [String] = []
    if last >= 1 {
        for p in 1...last {
            if let fs = fsAt[p] {
                if fs.count > 1 {
                    warnings.append("Several fullscreen apps at space \(p) (\(fs.map { $0.name }.joined(separator: ", "))); they follow each other in list order")
                }
                for a in fs {
                    parts.append("\(p) \(a.name) (fullscreen)")
                }
                for a in normalAt[p] ?? [] {
                    warnings.append("\(a.name) is at space \(p), which is a fullscreen app; it goes on the next desktop")
                    waiting.append(a.name)
                }
            } else {
                desktops += 1
                let names = waiting + (normalAt[p] ?? []).map { $0.name }
                waiting = []
                parts.append("\(p) Desktop" + (names.isEmpty ? "" : ": " + names.joined(separator: ", ")))
            }
        }
        if desktops == 0 || !waiting.isEmpty {
            if desktops == 0 {
                warnings.append("Every space is a fullscreen app; a desktop is added at the end (macOS needs one)")
            }
            parts.append("\(last + 1) Desktop" + (waiting.isEmpty ? "" : ": " + waiting.joined(separator: ", ")))
        }
    }
    return LayoutPreview(parts: parts, warnings: warnings)
}

struct LayoutPreviewView: View {
    var monitorSpaces: [Int] // main first
    var layout: [AppLayout]
    var singleMonitor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Main", spacesPreview(total: monitorSpaces.first ?? 1, apps: layout.filter { monitorNumber($0.monitor) == 1 }))
            if !singleMonitor {
                ForEach(Array(monitorSpaces.indices.dropFirst()), id: \.self) { i in
                    let apps = layout.filter { monitorNumber($0.monitor) == i + 1 }
                    if monitorSpaces[i] > 0 || !apps.isEmpty {
                        row(monitorLabel(i + 1), spacesPreview(total: monitorSpaces[i], apps: apps))
                    }
                }
            }
        }
    }

    // Only the warnings are shown (clashes and the like); the app list below
    // already shows the layout. Plain rows with a line limit: wrapping text
    // with fixedSize inside the split view can blank the window.
    @ViewBuilder
    func row(_ label: String, _ preview: LayoutPreview) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, warning in
                Text("⚠︎ " + label + ": " + warning)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Bridge

class ConfigWindowManager {
    static let shared = ConfigWindowManager()
    var windowController: NSWindowController?

    func show() {
        if let wc = windowController {
            wc.showWindow(nil)
            wc.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let configView = ConfigView()
        let hostingController = NSHostingController(rootView: configView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 650),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpacePigeon Configuration"
        window.contentViewController = hostingController
        window.center()

        let wc = NSWindowController(window: window)
        self.windowController = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

func openConfigWindow() {
    ConfigWindowManager.shared.show()
}
