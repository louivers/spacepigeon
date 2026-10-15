import SwiftUI
import Cocoa

// MARK: - Log model
//
// Reads ~/.hammerspoon/spacepigeon.log, written by lua/log.lua. Every line is
// one JSON object: ts, run, lvl, ev, msg, ms, step, data.

struct LogEntry: Identifiable {
    let id: Int
    let ts: Double
    let run: String
    let level: String
    let event: String
    let message: String
    let ms: Double?
    let step: String?
    let detail: String?
}

struct LogRun: Identifiable {
    let id: String
    var name: String
    var start: Double
    var end: Double?
    var totalMs: Double?
    var entries: [LogEntry]

    var isFinished: Bool { end != nil }
    var isAppLog: Bool { id == "app" }

    var worstLevel: String {
        if entries.contains(where: { $0.level == "error" }) { return "error" }
        if entries.contains(where: { $0.level == "warn" }) { return "warn" }
        return "info"
    }

    var warningCount: Int { entries.filter { $0.level == "warn" }.count }
    var errorCount: Int { entries.filter { $0.level == "error" }.count }
}

func formatDuration(_ ms: Double) -> String {
    if ms >= 1000 {
        return String(format: "%.2f s", ms / 1000)
    }
    return String(format: "%.0f ms", ms)
}

final class LogStore: ObservableObject {
    @Published var runs: [LogRun] = []
    @Published var live: Bool = true

    let url: URL
    private var timer: Timer?
    private var lastModified: Date?
    private var lastSize: Int = -1

    init() {
        url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hammerspoon/spacepigeon.log")
        reload(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.live else { return }
            self.reload(force: false)
        }
    }

    deinit {
        timer?.invalidate()
    }

    func reload(force: Bool) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = attributes?[.modificationDate] as? Date
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        if !force && modified == lastModified && size == lastSize {
            return
        }
        lastModified = modified
        lastSize = size

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            runs = []
            return
        }
        runs = LogStore.parse(text)
    }

    func clear() {
        try? Data().write(to: url)
        reload(force: true)
    }

    static func parse(_ text: String) -> [LogRun] {
        var order: [String] = []
        var byId: [String: LogRun] = [:]
        var index = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data),
                  let object = parsed as? [String: Any] else {
                continue
            }
            index += 1

            let ts = (object["ts"] as? NSNumber)?.doubleValue ?? 0
            let runId = object["run"] as? String ?? "app"
            let level = object["lvl"] as? String ?? "info"
            let event = object["ev"] as? String ?? "log"
            let message = object["msg"] as? String ?? ""
            let ms = (object["ms"] as? NSNumber)?.doubleValue
            let step = object["step"] as? String

            var detail: String? = nil
            if let value = object["data"], !(value is NSNull) {
                if JSONSerialization.isValidJSONObject(value),
                   let encoded = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                   let string = String(data: encoded, encoding: .utf8) {
                    if string != "{}" && string != "[]" {
                        detail = string
                    }
                } else {
                    detail = String(describing: value)
                }
            }

            let entry = LogEntry(id: index, ts: ts, run: runId, level: level, event: event,
                                 message: message, ms: ms, step: step, detail: detail)

            if byId[runId] == nil {
                order.append(runId)
                byId[runId] = LogRun(id: runId,
                                     name: runId == "app" ? "Hammerspoon" : "Workspace",
                                     start: ts, end: nil, totalMs: nil, entries: [])
            }
            if var run = byId[runId] {
                if event == "run_start", let name = object["name"] as? String {
                    run.name = name
                    run.start = ts
                }
                if event == "run_end" {
                    run.end = ts
                    run.totalMs = ms
                }
                run.entries.append(entry)
                byId[runId] = run
            }
        }

        // Newest first, the general Hammerspoon log last.
        var result: [LogRun] = order.reversed().compactMap { byId[$0] }
        if let appIndex = result.firstIndex(where: { $0.isAppLog }) {
            let appRun = result.remove(at: appIndex)
            result.append(appRun)
        }
        return result
    }
}

// MARK: - Views

struct LogView: View {
    @StateObject private var store = LogStore()
    @State private var selectedRunId: String? = nil
    @State private var levelFilter: String = "all"
    @State private var search: String = ""

    private var selectedRun: LogRun? {
        if let id = selectedRunId, let run = store.runs.first(where: { $0.id == id }) {
            return run
        }
        return store.runs.first
    }

    var body: some View {
        HSplitView {
            List(selection: $selectedRunId) {
                ForEach(store.runs) { run in
                    LogRunRow(run: run)
                        .tag(Optional(run.id))
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)

            VStack(spacing: 0) {
                toolbar
                Divider()
                if let run = selectedRun {
                    LogEntriesView(run: run, levelFilter: levelFilter, search: search)
                } else {
                    VStack {
                        Spacer()
                        Text("No logs yet. Trigger a workspace with its hotkey.")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(minWidth: 560)
        }
        .frame(minWidth: 860, minHeight: 480)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $levelFilter) {
                Text("All").tag("all")
                Text("Warnings").tag("warn")
                Text("Errors").tag("error")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 230)

            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            Spacer()

            Toggle("Live", isOn: $store.live)
                .toggleStyle(.checkbox)
                .help("Refresh every second while new lines are written")

            Button("Copy Run") {
                copyToPasteboard(selectedRun)
            }
            .disabled(selectedRun == nil)
            .help("Copy this run as text, e.g. to paste into a bug report")

            Button("Show File") {
                NSWorkspace.shared.activateFileViewerSelecting([store.url])
            }

            Button("Clear") {
                store.clear()
                selectedRunId = nil
            }
        }
        .padding(8)
    }

    private func copyToPasteboard(_ run: LogRun?) {
        guard let run = run else { return }
        var lines: [String] = []
        lines.append("\(run.name)  \(LogRunRow.dateFormatter.string(from: Date(timeIntervalSince1970: run.start)))"
                     + (run.totalMs.map { "  total \(formatDuration($0))" } ?? ""))
        for entry in run.entries {
            var line = String(format: "+%7.2fs  ", max(0, entry.ts - run.start))
            line += entry.level.padding(toLength: 6, withPad: " ", startingAt: 0)
            line += entry.message
            if let ms = entry.ms {
                line += "  [\(formatDuration(ms))]"
            }
            if let detail = entry.detail {
                line += "  \(detail)"
            }
            lines.append(line)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

struct LogRunRow: View {
    let run: LogRun

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm:ss"
        return formatter
    }()

    private var icon: String {
        if run.isAppLog { return "terminal" }
        if !run.isFinished { return "hourglass" }
        switch run.worstLevel {
        case "error": return "xmark.octagon.fill"
        case "warn": return "exclamationmark.triangle.fill"
        default: return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        if run.isAppLog || !run.isFinished { return .secondary }
        switch run.worstLevel {
        case "error": return .red
        case "warn": return .orange
        default: return .green
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.name)
                    .font(.system(size: 13, weight: .medium))
                Text(LogRunRow.dateFormatter.string(from: Date(timeIntervalSince1970: run.start)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let total = run.totalMs {
                Text(formatDuration(total))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct LogEntriesView: View {
    let run: LogRun
    let levelFilter: String
    let search: String

    private var visibleEntries: [LogEntry] {
        let query = search.lowercased()
        return run.entries.filter { entry in
            switch levelFilter {
            case "warn":
                if entry.level != "warn" && entry.level != "error" { return false }
            case "error":
                if entry.level != "error" { return false }
            default:
                break
            }
            if query.isEmpty { return true }
            return entry.message.lowercased().contains(query)
                || (entry.detail?.lowercased().contains(query) ?? false)
                || (entry.step?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Text(run.name)
                    .font(.headline)
                Text(LogRunRow.dateFormatter.string(from: Date(timeIntervalSince1970: run.start)))
                    .foregroundColor(.secondary)
                if let total = run.totalMs {
                    Text("Total \(formatDuration(total))")
                        .foregroundColor(.secondary)
                } else if !run.isAppLog {
                    Text("Running...")
                        .foregroundColor(.secondary)
                }
                Spacer()
                if run.warningCount > 0 {
                    Label("\(run.warningCount)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
                if run.errorCount > 0 {
                    Label("\(run.errorCount)", systemImage: "xmark.octagon.fill")
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleEntries) { entry in
                            LogEntryRow(entry: entry, runStart: run.start)
                                .id(entry.id)
                            Divider().opacity(0.4)
                        }
                    }
                }
                .onAppear {
                    if let last = visibleEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: run.entries.count) { _ in
                    if let last = visibleEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct LogEntryRow: View {
    let entry: LogEntry
    let runStart: Double

    private var levelColor: Color {
        switch entry.level {
        case "error": return .red
        case "warn": return .orange
        case "debug": return .secondary
        default: return .accentColor
        }
    }

    private var isRunEdge: Bool {
        entry.event == "run_start" || entry.event == "run_end"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(format: "+%.2fs", max(0, entry.ts - runStart)))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            Text(entry.level.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(levelColor)
                .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.system(size: 12, weight: isRunEdge ? .semibold : .regular))
                    .foregroundColor(entry.level == "debug" ? .secondary : .primary)
                    .textSelection(.enabled)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            if let ms = entry.ms {
                Text(formatDuration(ms))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(ms >= 1000 ? .orange : .secondary)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(isRunEdge ? Color.accentColor.opacity(0.07) : Color.clear)
    }
}

// MARK: - Window

class LogWindowManager {
    static let shared = LogWindowManager()
    var windowController: NSWindowController?

    func show() {
        if let controller = windowController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: LogView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpacePigeon Logs"
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.center()
        window.setFrameAutosaveName("SpacePigeonLogs")

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

func openLogWindow() {
    LogWindowManager.shared.show()
}
