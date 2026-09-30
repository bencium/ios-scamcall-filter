import Foundation

/// The complete approved UK 0845 range, partitioned strictly below the observed rejection boundary.
enum BlockerPlan {
    static let firstNumber: Int64 = 448450000000
    static let endExclusive: Int64 = 448460000000
    static let counts: [Int64] = [1_800_000, 1_800_000, 1_800_000, 1_800_000, 1_800_000, 1_000_000]
    static let partCount = counts.count
    static let ids = counts.indices.map { index in
        "uk.co.bencium.ScamBlocker." + (index == 0 ? "Blocker" : "Part\(index + 1)")
    }

    static func range(forPart part: Int) -> Range<Int64>? {
        guard (1...partCount).contains(part) else { return nil }
        let start = firstNumber + counts.prefix(part - 1).reduce(0, +)
        return start..<(start + counts[part - 1])
    }
}
