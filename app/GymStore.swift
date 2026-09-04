import Foundation
import SwiftUI
import Combine

/// Owns the Scriptable folder, the log file, and the config file.
///
/// Access works through a security-scoped bookmark from a one-time folder pick.
/// That needs no entitlement, so this runs fine on a free Personal Team.
@MainActor
final class GymStore: ObservableObject {

    @Published var config: GymConfig = .fallback
    @Published var entries: [LogEntry] = []
    @Published var folderName: String?
    @Published var lastError: String?
    /// True when the folder is linked but no config exists yet, so the
    /// app should walk the person through setup instead of guessing.
    @Published var needsSetup = false

    private let bookmarkKey = "scriptableFolderBookmark"
    private var folderURL: URL?

    var engine: GymEngine { GymEngine(config: config, entries: entries) }
    var isLinked: Bool { folderURL != nil }

    init() { restoreFolder() }

    // MARK: - Folder

    /// Called once from the folder picker. Everything after this is automatic.
    func linkFolder(_ url: URL) {
        // The picker hands back a security-scoped URL. Access has to be open
        // before the bookmark is made, or bookmarkData fails with a
        // misleading "file does not exist" error.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            folderURL = url
            folderName = url.lastPathComponent
            lastError = nil
            reload()
        } catch {
            lastError = "Could not save folder access: \(error.localizedDescription)"
        }
    }

    private func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            folderURL = url
            folderName = url.lastPathComponent
            reload()
        } catch {
            lastError = "Folder link expired. Pick the Scriptable folder again."
        }
    }

    private func withFolder<T>(_ body: (URL) throws -> T) -> T? {
        guard let folder = folderURL else {
            lastError = "No folder linked yet."
            return nil
        }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        do {
            return try body(folder)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Load

    func reload() {
        loadConfig()
        loadLog()
    }

    private func loadLog() {
        _ = withFolder { folder in
            let url = folder.appendingPathComponent("gym_log.txt")
            guard FileManager.default.fileExists(atPath: url.path) else {
                entries = []
                return
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            entries = text
                .split(separator: "\n")
                .compactMap { LogEntry.parse(String($0)) }
                .sorted { $0.stamp < $1.stamp }
        }
    }

    private func loadConfig() {
        _ = withFolder { folder in
            let url = folder.appendingPathComponent("gym_config.json")
            guard FileManager.default.fileExists(atPath: url.path) else {
                // Nothing written yet. Do not invent numbers, ask instead.
                config = .fallback
                needsSetup = true
                return
            }
            let data = try Data(contentsOf: url)
            config = try JSONDecoder().decode(GymConfig.self, from: data)
            needsSetup = false
        }
    }

    // MARK: - Save

    /// Called at the end of onboarding.
    func completeSetup(_ new: GymConfig) {
        saveConfig(new)
        needsSetup = false
    }

    func saveConfig(_ new: GymConfig) {
        config = new
        _ = withFolder { folder in
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(new)
            try data.write(to: folder.appendingPathComponent("gym_config.json"), options: .atomic)
        }
    }

    private func writeLog() {
        _ = withFolder { folder in
            let text = entries
                .sorted { $0.stamp < $1.stamp }
                .map(\.line)
                .joined(separator: "\n")
            let body = text.isEmpty ? "" : text + "\n"
            try body.write(
                to: folder.appendingPathComponent("gym_log.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    // MARK: - Editing

    /// Credit a day you actually attended but the geofence missed.
    func markAttended(_ day: Date) {
        let noon = GymDate.cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        entries.append(LogEntry(tag: "MANUAL", stamp: noon))
        writeLog()
    }

    /// Remove every entry on a day. Undoes a false positive.
    func clearDay(_ day: Date) {
        let k = GymDate.key(day)
        entries.removeAll { GymDate.key($0.stamp) == k }
        writeLog()
    }

    /// Mark a day as excused. No money burnt, no session owed.
    func toggleSkip(_ day: Date) {
        let k = GymDate.key(day)
        var c = config
        if let i = c.skipDates.firstIndex(of: k) {
            c.skipDates.remove(at: i)
        } else {
            c.skipDates.append(k)
            c.skipDates.sort()
        }
        saveConfig(c)
    }

    /// Spend a weekend session to repair a broken day. Never automatic.
    func repair(_ day: Date) {
        let k = GymDate.key(day)
        var c = config
        guard !c.restored.contains(k) else { return }
        c.restored.append(k)
        c.restored.sort()
        saveConfig(c)
    }

    func unrepair(_ day: Date) {
        var c = config
        c.restored.removeAll { $0 == GymDate.key(day) }
        saveConfig(c)
    }

    func deleteEntry(_ entry: LogEntry) {
        entries.removeAll { $0.id == entry.id }
        writeLog()
    }
}
