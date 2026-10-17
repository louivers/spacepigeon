import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate, URLSessionTaskDelegate {
    var window: NSWindow!
    var statusLabel: NSTextField!
    var installButton: NSButton!
    var editConfigButton: NSButton!
    var logsButton: NSButton!
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

        let descLabel = NSTextField(labelWithString: Profile.name.map { "Profile \"\($0)\": your own setup is not touched" } ?? "Install configuration to ~/.hammerspoon")
        descLabel.font = NSFont.systemFont(ofSize: 13)
        descLabel.frame = NSMakeRect(20, 210, 360, 20)
        descLabel.alignment = .center
        descLabel.textColor = .secondaryLabelColor
        contentView.addSubview(descLabel)

        installButton = NSButton(title: "Install & Reload", target: self, action: #selector(installClicked))
        installButton.frame = NSMakeRect(100, 160, 200, 40)
        installButton.bezelStyle = .rounded
        contentView.addSubview(installButton)

        editConfigButton = NSButton(title: "Edit Config", target: self, action: #selector(editConfigClicked))
        editConfigButton.frame = NSMakeRect(100, 120, 200, 40)
        editConfigButton.bezelStyle = .rounded
        contentView.addSubview(editConfigButton)

        logsButton = NSButton(title: "View Logs", target: self, action: #selector(logsClicked))
        logsButton.frame = NSMakeRect(100, 80, 200, 40)
        logsButton.bezelStyle = .rounded
        contentView.addSubview(logsButton)

        progressBar = NSProgressIndicator(frame: NSMakeRect(50, 62, 300, 10))
        progressBar.style = .bar
        progressBar.isIndeterminate = true
        progressBar.isHidden = true
        contentView.addSubview(progressBar)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSMakeRect(20, 30, 360, 20)
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
        appMenu.addItem(withTitle: "Show Logs", action: #selector(logsClicked), keyEquivalent: "l")
        appMenu.addItem(NSMenuItem.separator())
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

        // `open -a SpacePigeon --args --logs` opens straight to the log window.
        if CommandLine.arguments.contains("--logs") {
            openLogWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    @objc func editConfigClicked() {
        openConfigWindow()
    }

    @objc func logsClicked() {
        openLogWindow()
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

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request)
    }

    func downloadAndInstallHammerspoon(statusUpdater: @escaping (String) -> Void) -> (Bool, String?) {
        statusUpdater("Downloading Hammerspoon...")
        guard let url = URL(string: "https://github.com/Hammerspoon/hammerspoon/releases/download/0.9.100/Hammerspoon-0.9.100.zip") else {
            return (false, "Invalid URL")
        }

        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        if !FileManager.default.fileExists(atPath: userApps.path) {
            do {
                try FileManager.default.createDirectory(at: userApps, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return (false, "Could not create ~/Applications: \(error.localizedDescription)")
            }
        }

        let zipPath = userApps.appendingPathComponent("Hammerspoon.zip")
        let appPath = userApps.appendingPathComponent("Hammerspoon.app")

        let downloadGroup = DispatchGroup()
        downloadGroup.enter()

        var success = false
        var errorMsg: String? = nil

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        let task = session.downloadTask(with: url) { location, response, error in
            if let error = error {
                errorMsg = "Download failed: \(error.localizedDescription)"
            } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                errorMsg = "HTTP Error: \(httpResponse.statusCode)"
            } else if let location = location {
                do {
                    let attr = try FileManager.default.attributesOfItem(atPath: location.path)
                    if let size = attr[.size] as? Int64, size < 1000 {
                         errorMsg = "Download too small (\(size) bytes). Likely blocked or invalid URL."
                    } else {
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

        if !NSWorkspace.shared.open(zipPath) {
             return (false, "Failed to open zip file with System Archive Utility")
        }

        var tries = 0
        let maxTries = 60
        while !FileManager.default.fileExists(atPath: appPath.path) && tries < maxTries {
            Thread.sleep(forTimeInterval: 0.5)
            tries += 1
        }

        if FileManager.default.fileExists(atPath: appPath.path) {
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

        updateStatus("Checking for Hammerspoon...")
        let hsApps = [
            "/Applications/Hammerspoon.app",
            "\(home.path)/Applications/Hammerspoon.app"
        ]

        var hsInstalled = hsApps.contains { fileManager.fileExists(atPath: $0) }
        if !hsInstalled {
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

        do {
            try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            updateStatus("Error creating directory: \(error.localizedDescription)")
            return
        }

        updateStatus("Copying configuration files...")
        guard let resourcePath = Bundle.main.resourcePath else {
            updateStatus("Error: No resource path found.")
            return
        }

        let changed = BundleInstaller.installRuntimeFiles(from: resourcePath, to: targetDir)
        print("Installed: \(changed)")
        Profile.activate()

        updateStatus("Reloading Hammerspoon...")
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        let hsApp = runningApps.first { $0.bundleIdentifier == "org.hammerspoon.Hammerspoon" }

        if hsApp != nil {
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
                if let err = errorDict {
                     print("HS Reload Error: \(err)")
                }
            }
        } else {
            if let url = workspace.urlForApplication(withBundleIdentifier: "org.hammerspoon.Hammerspoon") {
                workspace.open(url)
            } else if let userUrl = workspace.urlForApplication(withBundleIdentifier: "org.hammerspoon.Hammerspoon") {
                 workspace.open(userUrl)
            } else {
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

/// Copies the runtime files shipped in the app bundle (init.lua, every
/// lua/*.lua, bin/spacectl) into ~/.hammerspoon. Shared by "Install & Reload"
/// and the config editor's "Save & Reload", so a rebuilt app never leaves
/// Hammerspoon running stale Lua. lua/config.lua is only installed when
/// missing: the config editor owns it and it is never overwritten.
enum BundleInstaller {
    static let userConfigFile = "lua/config.lua"

    static var hammerspoonDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hammerspoon")
    }

    /// Relative paths of the runtime files present in the bundle.
    static func runtimeFiles(in resourcePath: String) -> [String] {
        let fileManager = FileManager.default
        let luaDir = (resourcePath as NSString).appendingPathComponent("lua")
        let luaFiles = ((try? fileManager.contentsOfDirectory(atPath: luaDir)) ?? [])
            .filter { $0.hasSuffix(".lua") }
            .sorted()
            .map { "lua/\($0)" }
        let files = ["init.lua"] + luaFiles + ["bin/spacectl"] // spacectl moves windows between Spaces with SIP on
        return files.filter { fileManager.fileExists(atPath: (resourcePath as NSString).appendingPathComponent($0)) }
    }

    /// Copies every bundled runtime file that is missing or differs from the
    /// installed one. Returns the relative paths it wrote.
    @discardableResult
    static func installRuntimeFiles(from resourcePath: String? = Bundle.main.resourcePath,
                                    to targetDir: URL = hammerspoonDir) -> [String] {
        guard let resourcePath = resourcePath else { return [] }
        let fileManager = FileManager.default
        var written: [String] = []

        for file in runtimeFiles(in: resourcePath) {
            let src = URL(fileURLWithPath: resourcePath).appendingPathComponent(file)
            let dst = targetDir.appendingPathComponent(file)

            if fileManager.fileExists(atPath: dst.path) {
                if file == userConfigFile { continue }
                if fileManager.contentsEqual(atPath: src.path, andPath: dst.path) { continue }
            }

            do {
                try fileManager.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                if fileManager.fileExists(atPath: dst.path) {
                    try fileManager.removeItem(at: dst)
                }
                try fileManager.copyItem(at: src, to: dst)
                written.append(file)
            } catch {
                print("Failed to copy \(file): \(error)")
            }
        }
        return written
    }
}

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
