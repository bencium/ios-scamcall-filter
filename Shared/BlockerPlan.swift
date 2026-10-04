import Foundation

/// What each Call Directory part submits to iOS.
///
/// Parts 1–6 always hold the full UK 0845 range, split strictly below the observed
/// two-million rejection boundary. The normal build adds a server lookup for other prefixes.
/// The fallback build (compiled with FALLBACK_0843) has no server lookup; instead parts 7–9
/// hold the 0843 blocks Ofcom lists as allocated, 189 blocks (1.89 million numbers) each.
enum BlockerPlan {
    static let firstNumber: Int64 = 448450000000
    static let endExclusive: Int64 = 448460000000
    static let counts: [Int64] = [1_800_000, 1_800_000, 1_800_000, 1_800_000, 1_800_000, 1_000_000]
    static let fallbackParts = 7...9
    static let blocksPerFallbackPart = 189
    static let numbersPerBlock: Int64 = 10_000

#if FALLBACK_0843
    static let usesServerLookup = false
    static let partCount = counts.count + fallbackParts.count
#else
    static let usesServerLookup = true
    static let partCount = counts.count
#endif
    static let ids = (1...partCount).map(id(forPart:))

    /// Prefixes answered by the private lookup server; the phone holds no list for these.
    static let serverPrefixes = ["0843", "0844", "0870", "0871", "0872", "0873"]
    static let lookupID = "uk.co.bencium.ScamBlocker.Lookup"

    /// Part 7 reuses the server-lookup extension's identifier, so the fallback build
    /// still fits the free account's 10 App IDs: app + 6 parts for 0845 + 3 parts for 0843.
    static func id(forPart part: Int) -> String {
        "uk.co.bencium.ScamBlocker." + (part == 1 ? "Blocker" : part == 7 ? "Lookup" : "Part\(part)")
    }

    static func label(forPart part: Int) -> String {
        fallbackParts.contains(part)
            ? "0843 part \(part - fallbackParts.lowerBound + 1) of \(fallbackParts.count)"
            : "0845 part \(part) of \(counts.count)"
    }

    /// The ascending number ranges a part submits, or nil for an unknown part.
    static func ranges(forPart part: Int) -> [Range<Int64>]? {
        if (1...counts.count).contains(part) {
            let start = firstNumber + counts.prefix(part - 1).reduce(0, +)
            return [start..<(start + counts[part - 1])]
        }
        guard fallbackParts.contains(part) else { return nil }
        let blocks = FallbackBlocks.allocated0843
        let first = (part - fallbackParts.lowerBound) * blocksPerFallbackPart
        let last = min(first + blocksPerFallbackPart, blocks.count)
        guard first < last else { return nil }
        return blocks[first..<last].map { $0..<($0 + numbersPerBlock) }
    }
}
