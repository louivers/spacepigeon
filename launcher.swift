import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate, URLSessionTaskDelegate {
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

        // Setup Menu Bar (Critical for Copy/Paste)
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit SpacePigeon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit Menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    @objc func editConfigClicked() {
        openConfigWindow()
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
    
    // URLSession Delegate to follow redirects
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request)
    }

    func downloadAndInstallHammerspoon(statusUpdater: @escaping (String) -> Void) -> (Bool, String?) {
        statusUpdater("Downloading Hammerspoon...")
        
        // Fallback to specific version URL if "latest" redirect fails
        // Using 0.9.100 release asset directly which is robust
        guard let url = URL(string: "https://github.com/Hammerspoon/hammerspoon/releases/download/0.9.100/Hammerspoon-0.9.100.zip") else {
            return (false, "Invalid URL")
        }
        
        // Use User's Applications folder (~/Applications)
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        
        // Create ~/Applications if it doesn't exist
        if !FileManager.default.fileExists(atPath: userApps.path) {
            do {
                try FileManager.default.createDirectory(at: userApps, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return (false, "Could not create ~/Applications: \(error.localizedDescription)")
            }
        }
        
        // Destination zip path: ~/Applications/Hammerspoon.zip
        let zipPath = userApps.appendingPathComponent("Hammerspoon.zip")
        let appPath = userApps.appendingPathComponent("Hammerspoon.app")

        let downloadGroup = DispatchGroup()
        downloadGroup.enter()
        
        var success = false
        var errorMsg: String? = nil
        
        // Configure session to follow redirects
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        let task = session.downloadTask(with: url) { location, response, error in
            if let error = error {
                errorMsg = "Download failed: \(error.localizedDescription)"
            } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                errorMsg = "HTTP Error: \(httpResponse.statusCode)"
            } else if let location = location {
                do {
                    // Validate size (avoid 0 byte error pages)
                    let attr = try FileManager.default.attributesOfItem(atPath: location.path)
                    if let size = attr[.size] as? Int64, size < 1000 {
                         errorMsg = "Download too small (\(size) bytes). Likely blocked or invalid URL."
                    } else {
                        // Remove old zip if exists
                        if FileManager.default.fileExists(atPath: zipPath.path) {
                            try FileManager.default.removeItem(at: zipPath)
                        }
                        try FileManager.default.moveItem(at: location, to: zipPath)
                        success = true
                    }
                } catch {
                    errorMsg = "File move error: \(error.localizedDescription)"
                }
            }
            downloadGroup.leave()
        }
        task.resume()
        
        downloadGroup.wait()
        
        if !success { return (false, errorMsg ?? "Download failed") }
        
        statusUpdater("Unzipping Hammerspoon...")
        
        // Use NSWorkspace to unzip via Archive Utility (Native, Trusted, Robust)
        if !NSWorkspace.shared.open(zipPath) {
             return (false, "Failed to open zip file with System Archive Utility")
        }
        
        // Wait for Hammerspoon.app to appear (Timeout 30s)
        var tries = 0
        let maxTries = 60
        while !FileManager.default.fileExists(atPath: appPath.path) && tries < maxTries {
            Thread.sleep(forTimeInterval: 0.5)
            tries += 1
        }
        
        if FileManager.default.fileExists(atPath: appPath.path) {
             // Cleanup zip
             try? FileManager.default.removeItem(at: zipPath)
             return (true, nil)
        } else {
             return (false, "Unzip timed out. Please unzip ~/Applications/Hammerspoon.zip manually.")
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
        
        var hsInstalled = hsApps.contains { fileManager.fileExists(atPath: $0) }
        
        if !hsInstalled {
            // Auto-install Hammerspoon
            let (installed, errorMsg) = downloadAndInstallHammerspoon(statusUpdater: updateStatus)
            if !installed {
                DispatchQueue.main.async {
                    self.progressBar.stopAnimation(nil)
                    self.progressBar.isHidden = true
                    self.installButton.isEnabled = true
                    self.statusLabel.stringValue = "Error: \(errorMsg ?? "Unknown error")"
                    let alert = NSAlert()
                    alert.messageText = "Installation Failed"
                    alert.informativeText = "Could not download Hammerspoon automatically.\n\nReason: \(errorMsg ?? "Unknown")\n\nPlease install it manually from hammerspoon.org."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                return
            }
            hsInstalled = true
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
            
            // Special handling for config.lua: Don't overwrite if it exists
            if file == "config.lua" && fileManager.fileExists(atPath: dst.path) {
                print("Skipping \(file) - already exists")
                continue
            }
            
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
            // Hammerspoon IS running. Reload config using AppleScript.
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
            if let url = workspace.urlForApplication(withBundleIdentifier: "org.hammerspoon.Hammerspoon") {
                workspace.open(url)
            } else if let userUrl = workspace.urlForApplication(withBundleIdentifier: "org.hammerspoon.Hammerspoon") {
                 // Fallback check if urlForApplication finds it in user dir
                 workspace.open(userUrl)
            } else {
                // Manual launch from user apps if workspace doesn't see it yet
                let userAppPath = home.appendingPathComponent("Applications/Hammerspoon.app")
                workspace.open(userAppPath)
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
@main
struct AppEntry {
    static let delegate = AppDelegate()
    
    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
