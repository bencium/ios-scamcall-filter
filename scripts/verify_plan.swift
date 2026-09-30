import Foundation

@main
struct VerifyConfiguredPlan {
    static func main() {
        // Check the actual production configuration against the user-approved entire 0845 range.
        precondition(BlockerPlan.firstNumber == 448450000000)
        precondition(BlockerPlan.endExclusive == 448460000000)
        precondition(BlockerPlan.partCount == 6)
        precondition(Set(BlockerPlan.ids).count == BlockerPlan.partCount)
        precondition(BlockerPlan.range(forPart: 0) == nil)
        precondition(BlockerPlan.range(forPart: 7) == nil)
        var next = BlockerPlan.firstNumber
        var total: Int64 = 0
        for part in 1...BlockerPlan.partCount {
            guard let range = BlockerPlan.range(forPart: part) else { fatalError("Missing part") }
            precondition(range.lowerBound == next, "Gap or overlap between parts")
            let count = range.upperBound - range.lowerBound
            precondition(count > 0 && count < 2_000_000, "At or above observed rejection boundary")
            precondition(String(range.lowerBound).hasPrefix("44845"))
            precondition(String(range.upperBound - 1).hasPrefix("44845"))
            next = range.upperBound
            total += count
            print("Part \(part): \(range.lowerBound)...\(range.upperBound - 1), \(count) entries")
        }
        precondition(next == BlockerPlan.endExclusive)
        precondition(total == 10_000_000)
        print("Complete configured 0845 range; no gaps or overlap; every part strictly below two million.")
    }
}
