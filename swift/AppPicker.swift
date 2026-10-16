import SwiftUI
import Cocoa
import UniformTypeIdentifiers

// MARK: - Installed apps

struct InstalledApp: Identifiable, Hashable {
    var id: String { url.path }
    /// The app's file name without ".app": what `open -a` and SpacePigeon use.
    let name: String
    let url: URL
}

enum InstalledApps {
    private static var cached: [InstalledApp]?

    /// Apps in the usual folders (and one folder deeper, for apps that come in
    /// a folder of their own), plus running apps from anywhere else. Sorted by
    /// name, one entry per name.
    static func all(refresh: Bool = false) -> [InstalledApp] {
        if let cached = cached, !refresh { return cached }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let folders = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
        ]

        // Not .skipsHiddenFiles: on recent macOS /Applications/Safari.app is a
        // hidden symlink into a system cryptex.
        func list(_ folder: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? [])
                .filter { !$0.lastPathComponent.hasPrefix(".") }
        }

        var urls: [URL] = []
        for folder in folders {
            for item in list(folder) {
                if item.pathExtension == "app" {
                    urls.append(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                          !folders.contains(item) {
                    urls.append(contentsOf: list(item).filter { $0.pathExtension == "app" })
                }
            }
        }
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
            if let url = running.bundleURL { urls.append(url) }
        }

        var seen = Set<String>()
        let apps = urls
            .map { InstalledApp(name: $0.deletingPathExtension().lastPathComponent, url: $0.resolvingSymlinksInPath()) }
            .filter { seen.insert($0.name.lowercased()).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cached = apps
        return apps
    }

    static func url(named name: String) -> URL? {
        let wanted = name.lowercased()
        return all().first { $0.name.lowercased() == wanted }?.url
    }

    /// Asks for an app anywhere on the Mac. Returns its name, or nil.
    static func chooseWithPanel() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.deletingPathExtension().lastPathComponent
    }
}

// MARK: - Views

/// The app's icon, or a generic one when no app with this name is found.
struct AppIconView: View {
    let name: String
    var size: CGFloat = 18

    var body: some View {
        if let url = InstalledApps.url(named: name) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.8))
                .foregroundColor(.secondary)
                .frame(width: size, height: size)
        }
    }
}

/// A searchable list of installed apps. Calls `onPick` with the chosen name.
struct AppPickerView: View {
    let onPick: (String) -> Void
    @State private var search = ""
    @State private var apps: [InstalledApp] = []
    @FocusState private var searchFocused: Bool

    var filtered: [InstalledApp] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search apps", text: $search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit {
                    if let first = filtered.first { onPick(first.name) }
                }

            List(filtered) { app in
                Button(action: { onPick(app.name) }) {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(app.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)

            HStack {
                Text("\(filtered.count) app(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Other…") {
                    if let name = InstalledApps.chooseWithPanel() { onPick(name) }
                }
                .help("Choose an app from another folder")
            }
        }
        .padding(10)
        .frame(width: 300, height: 380)
        .onAppear {
            apps = InstalledApps.all(refresh: true)
            searchFocused = true
        }
    }
}
