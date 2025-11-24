import SwiftUI
import Cocoa

// MARK: - Data Models

struct AppLayout: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var space: Int
    var pos: String // "max", "left", "right"
    
    enum CodingKeys: String, CodingKey {
        case name, space, pos
    }
}

struct Preset: Codable, Identifiable, Hashable {
    var id = UUID()
    var key: String // Internal key for Lua table
    var name: String
    var spaces: Int
    var layout: [AppLayout]
    
    enum CodingKeys: String, CodingKey {
        case key, name, spaces, layout
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
}

// MARK: - Config Manager

class ConfigManager: ObservableObject {
    @Published var config: AppConfig
    @Published var saveStatus: String = ""
    
    init() {
        // Placeholder init
        self.config = AppConfig(presets: [], bindings: [])
        loadConfig()
    }
    
    var configPath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".hammerspoon/spacepigeon_config.json")
    }
    
    func loadConfig() {
        if FileManager.default.fileExists(atPath: configPath.path),
           let data = try? Data(contentsOf: configPath),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = ConfigManager.defaultConfig()
        }
    }
    
    func save() {
        // Ensure directory exists
        let home = FileManager.default.homeDirectoryForCurrentUser
        let hsDir = home.appendingPathComponent(".hammerspoon")
        if !FileManager.default.fileExists(atPath: hsDir.path) {
            try? FileManager.default.createDirectory(at: hsDir, withIntermediateDirectories: true)
        }

        // 1. Save JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(config) {
            try? data.write(to: configPath)
        }
        
        // 2. Generate Lua
        let lua = generateLua(from: config)
        let luaPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hammerspoon/config.lua")
        
        do {
            try lua.write(to: luaPath, atomically: true, encoding: .utf8)
            saveStatus = "Saved & Reloading..."
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
                Preset(key: "phd", name: "PhD", spaces: 9, layout: [
                    AppLayout(name: "Brave Browser", space: 1, pos: "max"),
                    AppLayout(name: "Zotero", space: 2, pos: "max"),
                    AppLayout(name: "Obsidian", space: 3, pos: "max"),
                    AppLayout(name: "Mattermost", space: 4, pos: "max"),
                    AppLayout(name: "Mail", space: 5, pos: "max"),
                    AppLayout(name: "Calendar", space: 6, pos: "max"),
                    AppLayout(name: "Marta", space: 8, pos: "max"),
                    AppLayout(name: "Spotify", space: 9, pos: "max")
                ]),
                Preset(key: "chill", name: "Chill", spaces: 4, layout: [
                    AppLayout(name: "Brave Browser", space: 1, pos: "max"),
                    AppLayout(name: "Marta", space: 4, pos: "max")
                ]),
                Preset(key: "casualCoding", name: "Casual Coding", spaces: 5, layout: [
                    AppLayout(name: "Brave Browser", space: 1, pos: "max"),
                    AppLayout(name: "Cursor", space: 2, pos: "max"),
                    AppLayout(name: "Marta", space: 4, pos: "max"),
                    AppLayout(name: "Spotify", space: 5, pos: "max")
                ]),
                Preset(key: "split", name: "Split Coding", spaces: 4, layout: [
                    AppLayout(name: "Cursor", space: 1, pos: "left"),
                    AppLayout(name: "Brave Browser", space: 1, pos: "right"),
                    AppLayout(name: "Marta", space: 2, pos: "max"),
                    AppLayout(name: "Spotify", space: 3, pos: "max")
                ])
            ],
            bindings: [
                KeyBinding(mods: ["cmd", "alt", "ctrl"], key: "P", presetKey: "phd"),
                KeyBinding(mods: ["cmd", "alt", "ctrl"], key: "C", presetKey: "chill"),
                KeyBinding(mods: ["cmd", "alt", "ctrl"], key: "D", presetKey: "casualCoding"),
                KeyBinding(mods: ["cmd", "alt", "ctrl"], key: "S", presetKey: "split")
            ]
        )
    }
    
    func generateLua(from config: AppConfig) -> String {
        var lua = "local M = {}\n\n"
        lua += "local presets = {\n"
        
        for preset in config.presets {
            // Sanitize key
            let key = preset.key.isEmpty ? "preset_\(UUID().uuidString.prefix(8))" : preset.key
            lua += "  \(key) = {\n"
            lua += "    name   = \"\(preset.name)\",\n"
            lua += "    spaces = \(preset.spaces),\n"
            lua += "    layout = {\n"
            for item in preset.layout {
                lua += "      { name = \"\(item.name)\", space = \(item.space), pos = \"\(item.pos)\" },\n"
            }
            lua += "    },\n"
            lua += "  },\n"
        }
        lua += "}\n\n"
        
        lua += "M.presets = presets\n\n"
        lua += "M.bindings = {\n"
        for binding in config.bindings {
            let modsString = binding.mods.map { "\"\($0)\"" }.joined(separator: ", ")
            // Look up if preset exists, otherwise be careful?
            // Assuming key matches.
            lua += "  { mods = {\(modsString)}, key = \"\(binding.key)\", preset = presets.\(binding.presetKey) },\n"
        }
        lua += "}\n\n"
        lua += "return M"
        return lua
    }
    
    func reloadHammerspoon() {
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
        .frame(width: 700, height: 500)
        .padding()
    }
}

struct PresetsListView: View {
    @Binding var config: AppConfig
    @State private var selectedPresetId: UUID?
    
    var body: some View {
        HSplitView {
            // Left: List of Presets
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
                        let new = Preset(key: "new", name: "New Preset", spaces: 1, layout: [])
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
                    Spacer()
                }
                .padding(5)
            }
            .frame(minWidth: 150, maxWidth: 200)
            
            // Right: Editor
            if let index = config.presets.firstIndex(where: { $0.id == selectedPresetId }) {
                PresetEditor(preset: $config.presets[index])
                    .padding()
            } else {
                Text("Select a preset to edit")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct PresetEditor: View {
    @Binding var preset: Preset
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Form {
                TextField("Name", text: $preset.name)
                TextField("Unique ID (key)", text: $preset.key)
                Stepper("Spaces: \(preset.spaces)", value: $preset.spaces, in: 1...16)
            }
            
            Divider()
            
            Text("Applications Layout")
                .font(.headline)
            
            List {
                ForEach($preset.layout) { $app in
                    HStack {
                        TextField("App Name", text: $app.name)
                            .frame(width: 120)
                        Stepper("Sp: \(app.space)", value: $app.space, in: 1...16)
                            .frame(width: 80)
                        Picker("Pos", selection: $app.pos) {
                            Text("Max").tag("max")
                            Text("Left").tag("left")
                            Text("Right").tag("right")
                        }
                        .frame(width: 100)
                    }
                }
                .onDelete { idx in
                    preset.layout.remove(atOffsets: idx)
                }
            }
            
            Button("Add App") {
                preset.layout.append(AppLayout(name: "New App", space: 1, pos: "max"))
            }
        }
    }
}

struct BindingsListView: View {
    @Binding var config: AppConfig
    
    var body: some View {
        VStack {
            List {
                HStack {
                    Text("Modifiers").bold().frame(width: 150, alignment: .leading)
                    Text("Key").bold().frame(width: 50, alignment: .center)
                    Text("Preset ID").bold().frame(width: 150, alignment: .leading)
                }
                ForEach($config.bindings) { $binding in
                    HStack {
                        // Modifiers selection is tricky in a small row, let's just use text for now or a simple toggle set
                        // For simplicity, a comma separated text field for mods?
                        // Or a MultiSelector. Let's stick to a simple text representation for now to not overengineer the UI without separate components
                        
                        TextField("mods", text: Binding(
                            get: { binding.mods.joined(separator: ", ") },
                            set: { binding.mods = $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                        ))
                        .frame(width: 150)
                        
                        TextField("Key", text: $binding.key)
                            .frame(width: 50)
                            .multilineTextAlignment(.center)
                        
                        Picker("Preset", selection: $binding.presetKey) {
                            ForEach(config.presets, id: \.key) { preset in
                                Text(preset.name).tag(preset.key)
                            }
                        }
                        .frame(width: 150)
                    }
                }
                .onDelete { idx in
                    config.bindings.remove(atOffsets: idx)
                }
            }
            
            Button("Add Binding") {
                // default to first preset
                let firstKey = config.presets.first?.key ?? ""
                config.bindings.append(KeyBinding(mods: ["cmd", "alt", "ctrl"], key: "A", presetKey: firstKey))
            }
            .padding()
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
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
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

