import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusLabel: NSTextField!
    var installButton: NSButton!
    var editConfigButton: NSButton!
    var progressBar: NSProgressIndicator!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Window Setup
        let windowSize = NSSize(width: 400, height: 300)
        let screenSize = NSScreen.main?.frame.size ?? NSSize(width: 1000, height: 800)
        let rect = NSMakeRect(
            (screenSize.width - windowSize.width) / 2,
            (screenSize.height - windowSize.height) / 2,
            windowSize.width,
            windowSize.height
        )
        
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpacePigeon Setup"
        window.center()
        
        let contentView = NSView(frame: window.contentView!.bounds)
        window.contentView = contentView

        // UI Elements
        let titleLabel = NSTextField(labelWithString: "SpacePigeon")
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        titleLabel.frame = NSMakeRect(20, 240, 360, 30)
        titleLabel.alignment = .center
        contentView.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: "Install configuration to ~/.hammerspoon")
        descLabel.font = NSFont.systemFont(ofSize: 13)
        descLabel.frame = NSMakeRect(20, 210, 360, 20)
        descLabel.alignment = .center
        descLabel.textColor = .secondaryLabelColor
        contentView.addSubview(descLabel)

        installButton = NSButton(title: "Install & Reload", target: self, action: #selector(installClicked))
        installButton.frame = NSMakeRect(100, 150, 200, 40)
        installButton.bezelStyle = .rounded
        contentView.addSubview(installButton)

        editConfigButton = NSButton(title: "Edit Config", target: self, action: #selector(editConfigClicked))
        editConfigButton.frame = NSMakeRect(100, 110, 200, 40)
        editConfigButton.bezelStyle = .rounded
        contentView.addSubview(editConfigButton)

        progressBar = NSProgressIndicator(frame: NSMakeRect(50, 90, 300, 10))
        progressBar.style = .bar
        progressBar.isIndeterminate = true
        progressBar.isHidden = true
        contentView.addSubview(progressBar)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSMakeRect(20, 40, 360, 20)
        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    @objc func editConfigClicked() {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let configPath = home.appendingPathComponent(".hammerspoon/config.lua")
        
        if fileManager.fileExists(atPath: configPath.path) {
            NSWorkspace.shared.open(configPath)
        } else {
            let alert = NSAlert()
            alert.messageText = "Config Not Found"
            alert.informativeText = "Please install the configuration first."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc func installClicked() {
        installButton.isEnabled = false
        progressBar.isHidden = false
        progressBar.startAnimation(nil)
        statusLabel.stringValue = "Checking environment..."

        DispatchQueue.global(qos: .userInitiated).async {
            self.performInstall()
        }
    }

    func performInstall() {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let targetDir = home.appendingPathComponent(".hammerspoon")
        
        func updateStatus(_ text: String) {
            DispatchQueue.main.async {
                self.statusLabel.stringValue = text
            }
        }

        // 1. Check Hammerspoon presence on disk
        updateStatus("Checking for Hammerspoon...")
        let hsApps = [
            "/Applications/Hammerspoon.app",
            "\(home.path)/Applications/Hammerspoon.app"
        ]
        
        let hsInstalled = hsApps.contains { fileManager.fileExists(atPath: $0) }
        
        if !hsInstalled {
            DispatchQueue.main.async {
                self.progressBar.stopAnimation(nil)
                self.progressBar.isHidden = true
                self.installButton.isEnabled = true
                self.statusLabel.stringValue = "Error: Hammerspoon not found."
                let alert = NSAlert()
                alert.messageText = "Hammerspoon Missing"
                alert.informativeText = "Please install Hammerspoon from hammerspoon.org first."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }

        // 2. Create Directory
        do {
            try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            updateStatus("Error creating directory: \(error.localizedDescription)")
            return
        }

        // 3. Copy Files
        updateStatus("Copying configuration files...")
        guard let resourcePath = Bundle.main.resourcePath else {
            updateStatus("Error: No resource path found.")
            return
        }

        let filesToCopy = ["init.lua", "layout.lua", "space_utils.lua", "workspaces.lua", "config.lua"]
        
        for file in filesToCopy {
            let src = URL(fileURLWithPath: resourcePath).appendingPathComponent(file)
            let dst = targetDir.appendingPathComponent(file)
            
            do {
                if fileManager.fileExists(atPath: dst.path) {
                    try fileManager.removeItem(at: dst)
                }
                try fileManager.copyItem(at: src, to: dst)
            } catch {
                print("Failed to copy \(file): \(error)")
            }
        }

        // 4. Reload or Launch Hammerspoon
        updateStatus("Reloading Hammerspoon...")
        
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        let hsApp = runningApps.first { $0.bundleIdentifier == "org.hammerspoon.Hammerspoon" }
        
        if hsApp != nil {
            // Hammerspoon IS running. Reload config using AppleScript without activating.
            // Note: 'tell application "Hammerspoon"' might activate it if not careful,
            // but usually only if we ask for UI.
            
            let source = """
            tell application "Hammerspoon"
                execute lua code "hs.reload()"
            end tell
            """
            if let script = NSAppleScript(source: source) {
                var errorDict: NSDictionary?
                script.executeAndReturnError(&errorDict)
                if let err = errorDict {
                     print("HS Reload Error: \(err)")
                }
            }
        } else {
            // Hammerspoon is NOT running. Launch it.
            // This will likely open its Console or Dock icon depending on user prefs.
            if let url = workspace.urlForApplication(withBundleIdentifier: "org.hammerspoon.Hammerspoon") {
                workspace.open(url)
            }
        }

        DispatchQueue.main.async {
            self.progressBar.stopAnimation(nil)
            self.progressBar.isHidden = true
            self.installButton.isEnabled = true
            self.installButton.title = "Re-install"
            self.statusLabel.stringValue = "Success! Configuration loaded."
            
            let alert = NSAlert()
            alert.messageText = "Installation Complete"
            alert.informativeText = "Your SpacePigeon configuration has been installed and Hammerspoon reloaded."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
