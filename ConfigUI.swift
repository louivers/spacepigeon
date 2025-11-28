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
    var keepAlive: [String]

    init(presets: [Preset], bindings: [KeyBinding], keepAlive: [String] = []) {
        self.presets = presets
        self.bindings = bindings
        self.keepAlive = keepAlive
    }

    enum CodingKeys: String, CodingKey {
        case presets, bindings, keepAlive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presets = try container.decode([Preset].self, forKey: .presets)
        bindings = try container.decode([KeyBinding].self, forKey: .bindings)
        keepAlive = try container.decodeIfPresent([String].self, forKey: .keepAlive) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(presets, forKey: .presets)
        try container.encode(bindings, forKey: .bindings)
        try container.encode(keepAlive, forKey: .keepAlive)
    }
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
            ],
            keepAlive: ["Spotify"]
        )
    }
    
    func generateLua(from config: AppConfig) -> String {
        var lua = "local M = {}\n\n"

        lua += "-- Apps to keep alive when switching modes (e.g. Spotify)\n"
        lua += "M.keepAlive = {\n"
        for app in config.keepAlive {
            lua += "  \"\(app)\",\n"
        }
        lua += "}\n\n"

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
                    .fill(Color.primary.opacity(0.03)) // Very subtle permanent background
            )
            .onHover { hover in isHovering = hover }
    }
}

struct PresetEditor: View {
    @Binding var preset: Preset
    
    @State private var editingAppId: UUID? = nil

    func moveUp(_ app: AppLayout) {
        if let index = preset.layout.firstIndex(where: { $0.id == app.id }), index > 0 {
            withAnimation {
                preset.layout.swapAt(index, index - 1)
            }
        }
    }
    
    func moveDown(_ app: AppLayout) {
        if let index = preset.layout.firstIndex(where: { $0.id == app.id }), index < preset.layout.count - 1 {
            withAnimation {
                preset.layout.swapAt(index, index + 1)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Preset Name")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    MinimalistTextField(placeholder: "Standard", text: $preset.name)
                        .font(.title3)
                }
                
                HStack(spacing: 24) {
                    VStack(alignment: .leading) {
                        Text("Main Monitor Spaces")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Stepper(value: $preset.spaces, in: 1...16) {
                            Text("\(preset.spaces)")
                                .font(.system(.body, design: .monospaced))
                                .frame(minWidth: 20)
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Secondary Monitor Spaces")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Stepper(value: $preset.secondarySpaces, in: 0...16) {
                            Text("\(preset.secondarySpaces)")
                                .font(.system(.body, design: .monospaced))
                                .frame(minWidth: 20)
                        }
                    }
                    Spacer()
                }
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
                    preset.layout.append(AppLayout(name: "New App", monitor: "main", spaceIndex: 1, pos: "max"))
                }) {
                    Label("Add App", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            
            ScrollView {
                VStack(spacing: 10) {
                    if preset.layout.isEmpty {
                        Text("No apps configured")
                            .foregroundColor(.secondary)
                            .padding(.top, 20)
                    }
                    
                    ForEach($preset.layout) { $app in
                        HStack(spacing: 12) {
                            // Reorder controls
                            VStack(spacing: 4) {
                                Button(action: { moveUp(app) }) {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .disabled(preset.layout.first?.id == app.id)
                                .opacity(preset.layout.first?.id == app.id ? 0.3 : 0.8)
                                
                                Button(action: { moveDown(app) }) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .disabled(preset.layout.last?.id == app.id)
                                .opacity(preset.layout.last?.id == app.id ? 0.3 : 0.8)
                            }
                            .frame(width: 16)
                            
                            // App Name & Settings
                            HStack(spacing: 8) {
                                Image(systemName: "app.fill")
                                    .foregroundColor(.secondary)
                                MinimalistTextField(placeholder: "App Name", text: $app.name)
                                    .font(.system(size: 14, weight: .medium))
                                
                                Button(action: { editingAppId = app.id }) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(app.isBrowser ? .accentColor : .secondary.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: Binding(
                                    get: { editingAppId == app.id },
                                    set: { if !$0 { editingAppId = nil } }
                                )) {
                                     AppSettingsView(app: $app)
                                }
                            }
                            .frame(width: 160, alignment: .leading)

                            Divider()
                                .frame(height: 20)

                            // Monitor
                            Picker("", selection: $app.monitor) {
                                Text("Main").tag("main")
                                Text("2nd").tag("secondary")
                            }
                            .frame(width: 75)
                            .labelsHidden()
                            
                            // Space
                            let maxSpaces = app.monitor == "main" ? preset.spaces : max(1, preset.secondarySpaces)
                            HStack(spacing: 2) {
                                Text("Sp")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Stepper("", value: $app.spaceIndex, in: 1...maxSpaces)
                                    .labelsHidden()
                                Text("\(app.spaceIndex)")
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 20, alignment: .center)
                            }
                            
                            // Position
                            Picker("", selection: $app.pos) {
                                Label("Max", systemImage: "rectangle.fill").tag("max")
                                Label("Left", systemImage: "rectangle.leading.third.inset.filled").tag("left")
                                Label("Right", systemImage: "rectangle.trailing.third.inset.filled").tag("right")
                            }
                            .frame(width: 85)
                            .labelsHidden()

                            Spacer()

                            // Delete
                            Button(action: {
                                if let index = preset.layout.firstIndex(where: { $0.id == app.id }) {
                                    preset.layout.remove(at: index)
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
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
                        )
                    }
                }
                .padding(1) // Avoid clipping shadows if added
            }
        }
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
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

            // Header Row
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
                Spacer().frame(width: 20) // Trash icon space
            }
            .padding(.horizontal, 12)
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach($config.bindings) { $binding in
                        HStack(spacing: 12) {
                            // Modifiers
                            MinimalistTextField(placeholder: "Cmd, Alt...", text: Binding(
                                get: { binding.mods.joined(separator: ", ") },
                                set: { binding.mods = $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                            ))
                            .frame(width: 160)
                            
                            // Key
                            MinimalistTextField(placeholder: "K", text: $binding.key, align: .center)
                                .frame(width: 50)
                            
                            // Preset Picker
                            Picker("", selection: $binding.presetKey) {
                                ForEach(config.presets, id: \.key) { preset in
                                    Text(preset.name).tag(preset.key)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            
                            // Delete
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
            .background(Color(NSColor.windowBackgroundColor)) // Clear background
            
            Button(action: {
                // default to first preset
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
    @State private var newAppName: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Global Settings")
                .font(.headline)
            
            Divider()
            
            VStack(alignment: .leading) {
                Text("Keep Alive Apps")
                    .font(.subheadline)
                    .bold()
                Text("These apps will not be closed when switching modes. They will be moved to their assigned space if applicable.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                List {
                    ForEach(config.keepAlive, id: \.self) { appName in
                        Text(appName)
                    }
                    .onDelete { indices in
                        config.keepAlive.remove(atOffsets: indices)
                    }
                }
                .frame(height: 200)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                
                HStack {
                    TextField("App Name (e.g. Spotify)", text: $newAppName)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Add") {
                        let name = newAppName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty && !config.keepAlive.contains(name) {
                            config.keepAlive.append(name)
                            newAppName = ""
                        }
                    }
                    .disabled(newAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            
            Spacer()
        }
        .padding()
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

