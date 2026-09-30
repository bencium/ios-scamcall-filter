import CallKit
import Foundation
import OSLog

@MainActor
final class BlockerStatus: ObservableObject {
    @Published var enabled = Array(repeating: false, count: BlockerPlan.partCount)
    @Published var accepted = Array(repeating: false, count: BlockerPlan.partCount)
    @Published var busy = false
    @Published var message = "Checking the iOS switches…"
    private let logger = Logger(subsystem: "uk.co.bencium.ScamBlocker", category: "Status")

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
        if failed {
            message = "Could not read all switches. Full coverage is NOT confirmed."
        } else {
            updateSummary()
        }
    }

    private func updateSummary() {
        let onCount = enabled.filter { $0 }.count
        let checkedCount = zip(enabled, accepted).filter { $0 && $1 }.count
        if checkedCount == BlockerPlan.partCount {
            message = "iOS accepted all six parts and all switches are on. The full 0845 rule is loaded. A real call test is still needed."
        } else if onCount == BlockerPlan.partCount {
            message = "All six switches are on. Tap Check enabled parts to verify the full list."
        } else {
            message = "\(onCount) of 6 parts enabled; \(checkedCount) checked. The full 0845 range is NOT active."
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
                logger.error("Part \(index + 1, privacy: .public) failed: \(error.domain, privacy: .public) code=\(error.code, privacy: .public)")
                return
            }
            accepted[index] = true
            logger.notice("Part \(index + 1, privacy: .public) reload accepted")
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
}
