import CallKit
import Foundation
import IdentityLookup
import OSLog

@MainActor
final class BlockerStatus: ObservableObject {
    @Published var enabled = Array(repeating: false, count: BlockerPlan.partCount)
    @Published var accepted = Array(repeating: false, count: BlockerPlan.partCount)
    @Published var lookupEnabled = false
    @Published var busy = false
    @Published var message = "Checking the iOS switches…"
    private let logger = Logger(subsystem: "uk.co.bencium.ScamBlocker", category: "Status")
    private let lookup = LiveCallerIDLookupManager.shared

    func refresh() async {
        guard !busy else { return }
        var states = [Bool]()
        var failed = false
        for (index, id) in BlockerPlan.ids.enumerated() {
            let result: (CXCallDirectoryManager.EnabledStatus, Error?) = await withCheckedContinuation { continuation in
                CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(withIdentifier: id) {
                    continuation.resume(returning: ($0, $1))
                }
            }
            let isEnabled = result.0 == .enabled && result.1 == nil
            states.append(isEnabled)
            failed = failed || result.1 != nil
            logger.notice("Part \(index + 1, privacy: .public) switch enabled=\(isEnabled, privacy: .public)")
        }
        enabled = states
        for index in states.indices where !states[index] { accepted[index] = false }
        if BlockerPlan.usesServerLookup {
            lookupEnabled = lookup.status(forExtensionWithIdentifier: BlockerPlan.lookupID) == .enabled
            logger.notice("Server lookup enabled=\(self.lookupEnabled, privacy: .public)")
        }
        if failed {
            message = "Could not read all switches. Full coverage is NOT confirmed."
        } else {
            updateSummary()
        }
        saveStatusFile()
    }

    private func saveStatusFile() {
        let file = StatusFile(
            written: .now,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            summary: message,
            parts: enabled.indices.map { .init(name: BlockerPlan.label(forPart: $0 + 1), on: enabled[$0]) },
            serverLookupOn: BlockerPlan.usesServerLookup ? lookupEnabled : nil,
            lastPartsCheck: StatusFile.last(.partsCheck),
            lastServerRefresh: StatusFile.last(.serverRefresh))
        do {
            try file.save()
        } catch {
            logger.error("Status file not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateSummary() {
        let total = BlockerPlan.partCount
        let onCount = enabled.filter { $0 }.count
        let checkedCount = zip(enabled, accepted).filter { $0 && $1 }.count
        let lookupText = !BlockerPlan.usesServerLookup ? "" : lookupEnabled ? " Server lookup is on." : " Server lookup is OFF."
        if checkedCount == total {
            message = "iOS accepted all \(total) parts and all switches are on.\(lookupText) A real call test is still needed."
        } else if onCount == total {
            message = "All \(total) switches are on. Tap Check enabled parts to verify the full list.\(lookupText)"
        } else {
            message = "\(onCount) of \(total) parts enabled; \(checkedCount) checked. The full list is NOT active.\(lookupText)"
        }
    }

    func reloadEnabled() async {
        guard !busy else { return }
        await refresh()
        // Recheck after awaiting because another task could have started a load.
        guard !busy else { return }
        let indices = enabled.indices.filter { enabled[$0] }
        guard !indices.isEmpty else { return }
        busy = true
        accepted = Array(repeating: false, count: BlockerPlan.partCount)
        for index in indices {
            message = "Checking part \(index + 1). Keep this screen open."
            let error: Error? = await withCheckedContinuation { continuation in
                CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: BlockerPlan.ids[index]) {
                    continuation.resume(returning: $0)
                }
            }
            if let error = error as NSError? {
                busy = false
                message = "Part \(index + 1) failed: \(error.localizedDescription) (code \(error.code)). Full coverage is NOT confirmed."
                StatusFile.record(.partsCheck, message)
                saveStatusFile()
                logger.error("Part \(index + 1, privacy: .public) failed: \(error.domain, privacy: .public) code=\(error.code, privacy: .public)")
                return
            }
            accepted[index] = true
            logger.notice("Part \(index + 1, privacy: .public) reload accepted")
        }
        StatusFile.record(.partsCheck, "iOS accepted parts \(indices.map { String($0 + 1) }.joined(separator: ", ")).")
        busy = false
        await refresh()
    }

    /// Makes iOS re-read the server address and token, then fetch fresh lookup parameters.
    /// Needed after the server database changes or the URL or token in .env changes.
    func refreshLookup() async {
        guard !busy else { return }
        busy = true
        message = "Refreshing the server lookup. Keep this screen open."
        do {
            if #available(iOS 18.1, *) {
                try await lookup.refreshExtensionContext(forExtensionWithIdentifier: BlockerPlan.lookupID)
            }
            try await lookup.refreshPIRParameters(forExtensionWithIdentifier: BlockerPlan.lookupID)
            logger.notice("Server lookup refreshed")
            StatusFile.record(.serverRefresh, "Refreshed.")
        } catch {
            let error = error as NSError
            busy = false
            message = "Server lookup refresh failed: \(error.localizedDescription) (code \(error.code))."
            StatusFile.record(.serverRefresh, message)
            saveStatusFile()
            logger.error("Server lookup refresh failed: \(error.domain, privacy: .public) code=\(error.code, privacy: .public)")
            return
        }
        busy = false
        await refresh()
    }

    func settings() {
        CXCallDirectoryManager.sharedInstance.openSettings { error in
            if let error {
                Task { @MainActor in
                    self.message = "Open Settings > Apps > Phone > Call Blocking & Identification. \(error.localizedDescription)"
                }
            }
        }
    }

    func lookupSettings() async {
        do {
            try await lookup.openSettings()
        } catch {
            message = "Open Settings > Apps > Phone > Call Blocking & Identification. \(error.localizedDescription)"
        }
    }
}
