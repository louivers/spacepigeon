import SwiftUI
import Cocoa

// MARK: - Data Models

struct AppLayout: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var monitor: String // "main" or "secondary"
    var spaceIndex: Int // 1-based index relative to the monitor
    var pos: String // "max", "left", "right"
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
            // Legacy fallback: Assume everything is on "main" for now, or try to guess?
            // Better to just default to Main Space 1 and let user fix it, 
            // rather than complex migration logic here without knowing total spaces.
            // Or we could look for the old 'space' key manually.
            monitor = "main"
            spaceIndex = 1 
            
            // Attempt to read legacy 'space' key from a dynamic container
            // (Simulated since we defined CodingKeys strictly above. 
            // To do this properly, we'd need a separate keys enum or dynamic decoding.
            // For now, let's just accept that old configs might reset to Main 1.
            // Or we can add 'space' to CodingKeys temporarily.)
        }
    }
}

struct Preset: Codable, Identifiable, Hashable {
    var id = UUID()
    var key: String // Internal key for Lua table
    var name: String
    var spaces: Int // Main monitor spaces
    var secondarySpaces: Int // Secondary monitor spaces
    var layout: [AppLayout]
    
    init(id: UUID = UUID(), key: String, name: String, spaces: Int, secondarySpaces: Int, layout: [AppLayout]) {
        self.id = id
        self.key = key
        self.name = name
        self.spaces = spaces
        self.secondarySpaces = secondarySpaces
        self.layout = layout
    }
    
    enum CodingKeys: String, CodingKey {
        case key, name, spaces, secondarySpaces, layout
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        name = try container.decode(String.self, forKey: .name)
        spaces = try container.decode(Int.self, forKey: .spaces)
        layout = try container.decode([AppLayout].self, forKey: .layout)
        
        // New field with default
        secondarySpaces = try container.decodeIfPresent(Int.self, forKey: .secondarySpaces) ?? 0
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
                Preset(key: "standard", name: "Standard", spaces: 3, secondarySpaces: 1, layout: [
                    AppLayout(name: "Safari", monitor: "main", spaceIndex: 1, pos: "max"),
                    AppLayout(name: "Terminal", monitor: "main", spaceIndex: 2, pos: "left"),
                    AppLayout(name: "Notes", monitor: "main", spaceIndex: 2, pos: "right"),
                    AppLayout(name: "Music", monitor: "main", spaceIndex: 3, pos: "max")
                ])
            ],
            bindings: [
                KeyBinding(mods: ["cmd", "alt", "ctrl"], key: "S", presetKey: "standard")
            ]
        )
    }
    
    func generateLua(from config: AppConfig) -> String {
        var lua = "local M = {}\n\n"
        lua += "local presets = {\n"
        
        for preset in config.presets {
            // Sanitize key
            let key = preset.key.isEmpty ? "preset_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))" : preset.key
            lua += "  [\"\(key)\"] = {\n"
            lua += "    name   = \"\(preset.name)\",\n"
            lua += "    spaces = { main = \(preset.spaces), secondary = \(preset.secondarySpaces) },\n"
            lua += "    layout = {\n"
            for item in preset.layout {
                let urlPart = item.url.isEmpty ? "" : ", url = \"\(item.url)\""
                lua += "      { name = \"\(item.name)\", monitor = \"\(item.monitor)\", space = \(item.spaceIndex), pos = \"\(item.pos)\"\(urlPart) },\n"
            }
            lua += "    },\n"
            lua += "  },\n"
        }
        lua += "}\n\n"
        
        lua += "M.presets = presets\n\n"
        lua += "M.bindings = {\n"
        for binding in config.bindings {
            let modsString = binding.mods.map { "\"\($0)\"" }.joined(separator: ", ")
            lua += "  { mods = {\(modsString)}, key = \"\(binding.key)\", preset = presets[\"\(binding.presetKey)\"] },\n"
        }
        lua += "}\n\n"
        lua += "return M"
        return lua
    }
    
    func reloadHammerspoon() {
        // Method 1: URL Scheme (requires updated init.lua)
        if let url = URL(string: "hammerspoon://reloadConfig") {
            NSWorkspace.shared.open(url)
        }

        // Method 2: AppleScript (Fallback)
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
                    // Clear URL if not browser/enabled
                    if !app.isBrowser {
                        app.url = ""
                    }
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .padding()
        .frame(width: 400, height: 250)
    }
}

struct PresetEditor: View {
    @Binding var preset: Preset
    
    @State private var editingAppId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Form {
                TextField("Name", text: $preset.name)
                HStack {
                    Stepper("Main Spaces: \(preset.spaces)", value: $preset.spaces, in: 1...16)
                    Spacer()
                    Stepper("2nd Monitor Spaces: \(preset.secondarySpaces)", value: $preset.secondarySpaces, in: 0...16)
                }
            }
            
            Divider()
            
            Text("Applications Layout")
                .font(.headline)
            
            List {
                ForEach($preset.layout) { $app in
                    HStack {
                        TextField("App", text: $app.name)
                            .frame(width: 100)
                        
                        // Advanced Settings Gear
                        Button(action: {
                            editingAppId = app.id
                        }) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(app.isBrowser ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: Binding(
                            get: { editingAppId == app.id },
                            set: { if !$0 { editingAppId = nil } }
                        )) {
                             AppSettingsView(app: $app)
                        }

                        Picker("", selection: $app.monitor) {
                            Text("Main").tag("main")
                            Text("2nd").tag("secondary")
                        }
                        .frame(width: 70)
                        .pickerStyle(.menu)
                        
                        // Cap the stepper based on selected monitor's config
                        let maxSpaces = app.monitor == "main" ? preset.spaces : max(1, preset.secondarySpaces)
                        Stepper("Sp \(app.spaceIndex)", value: $app.spaceIndex, in: 1...maxSpaces)
                            .frame(width: 60)

                        Picker("", selection: $app.pos) {
                            Text("Max").tag("max")
                            Text("Left").tag("left")
                            Text("Right").tag("right")
                        }
                        .frame(width: 80)

                        Button(action: {
                            if let index = preset.layout.firstIndex(where: { $0.id == app.id }) {
                                preset.layout.remove(at: index)
                            }
                        }) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onDelete { idx in
                    preset.layout.remove(atOffsets: idx)
                }
                .onMove { indices, newOffset in
                    preset.layout.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            
            Button("Add App") {
                preset.layout.append(AppLayout(name: "New App", monitor: "main", spaceIndex: 1, pos: "max"))
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
                        
                        Button(action: {
                            if let index = config.bindings.firstIndex(where: { $0.id == binding.id }) {
                                config.bindings.remove(at: index)
                            }
                        }) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
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
