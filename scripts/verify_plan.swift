import Foundation

@main
struct VerifyConfiguredPlan {
    static func main() {
        verify0845Parts()
        verifyFallback0843Parts()
    }

    /// The full 0845 range, contiguous, in six parts each below the observed rejection boundary.
    static func verify0845Parts() {
        precondition(BlockerPlan.firstNumber == 448450000000)
        precondition(BlockerPlan.endExclusive == 448460000000)
        precondition(BlockerPlan.ranges(forPart: 0) == nil)
        precondition(BlockerPlan.ranges(forPart: 10) == nil)
        var next = BlockerPlan.firstNumber
        for part in 1...BlockerPlan.counts.count {
            guard let ranges = BlockerPlan.ranges(forPart: part), ranges.count == 1 else { fatalError("Missing part \(part)") }
            let range = ranges[0]
            precondition(range.lowerBound == next, "Gap or overlap between parts")
            precondition(range.count > 0 && range.count < 2_000_000, "At or above observed rejection boundary")
            precondition(String(range.lowerBound).hasPrefix("44845") && String(range.upperBound - 1).hasPrefix("44845"))
            next = range.upperBound
            print("0845 part \(part): \(range.lowerBound)...\(range.upperBound - 1), \(range.count) entries")
        }
        precondition(next == BlockerPlan.endExclusive)
        print("Complete 0845 range; no gaps or overlap; every part strictly below two million.")
    }

    /// Fallback only: Ofcom-allocated 0843 blocks, ascending, unique, in three parts below the boundary.
    static func verifyFallback0843Parts() {
        let blocks = FallbackBlocks.allocated0843
        precondition(blocks == blocks.sorted() && Set(blocks).count == blocks.count, "Blocks unsorted or duplicated")
        precondition(blocks.allSatisfy { String($0).hasPrefix("44843") && $0 % BlockerPlan.numbersPerBlock == 0 })
        var total = 0
        var previousEnd: Int64 = 0
        for part in BlockerPlan.fallbackParts {
            guard let ranges = BlockerPlan.ranges(forPart: part) else { fatalError("Missing fallback part \(part)") }
            let count = ranges.reduce(0) { $0 + $1.count }
            precondition(count > 0 && count < 2_000_000, "At or above observed rejection boundary")
            precondition(ranges.first!.lowerBound >= previousEnd, "Fallback parts overlap or are out of order")
            previousEnd = ranges.last!.upperBound
            total += count
            print("0843 fallback part \(part - 6): \(ranges.count) blocks, \(count) entries")
        }
        precondition(total == blocks.count * Int(BlockerPlan.numbersPerBlock), "Fallback parts miss some blocks")
        print("Fallback 0843: all \(blocks.count) allocated blocks covered once; every part below two million.")
        print("App IDs in the fallback build: app + 6 (0845) + 3 (0843, one reusing the lookup ID) = 10.")
    }
}
