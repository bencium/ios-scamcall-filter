import CallKit
import Foundation
import OSLog

final class CallDirectoryHandler: CXCallDirectoryProvider, CXCallDirectoryExtensionContextDelegate {
    private let logger = Logger(subsystem: "uk.co.bencium.ScamBlocker", category: "Loading")

    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self
        guard let part = Bundle.main.object(forInfoDictionaryKey: "BlockerPart") as? Int,
              let range = BlockerPlan.range(forPart: part) else {
            context.cancelRequest(withError: NSError(domain: "ScamBlocker.Configuration", code: 1))
            return
        }
        if context.isIncremental { context.removeAllBlockingEntries() }
        // Exactly two million failed on this device; stay below that boundary.
        var next: CXCallDirectoryPhoneNumber = range.lowerBound
        let end = range.upperBound
        logger.notice("Submitting part \(part, privacy: .public); count=\(range.count, privacy: .public)")
        while next < end {
            autoreleasepool {
                let batchEnd = min(next + 10_000, end)
                while next < batchEnd {
                    context.addBlockingEntry(withNextSequentialPhoneNumber: next)
                    next += 1
                }
            }
        }
        context.completeRequest { [logger] expired in
            logger.notice("Part \(part, privacy: .public) submission completed; expired=\(expired, privacy: .public)")
        }
    }

    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: Error) {
        let error = error as NSError
        logger.error("Loading failed: \(error.domain, privacy: .public) code=\(error.code, privacy: .public)")
    }
}
