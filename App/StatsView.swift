import SwiftUI

/// The Details screen: what the server, the Mac's call report and the phone itself report.
struct StatsView: View {
    @ObservedObject var stats: StatsModel
    @ObservedObject var status: BlockerStatus

    var body: some View {
        Form {
            serverSection
            databaseSection
            blockedSection
            phoneSection
        }
        .navigationTitle("Details")
        .refreshable { await stats.refresh() }
    }

    @ViewBuilder private var serverSection: some View {
        Section("Server") {
            switch stats.state {
            case .loading:
                ProgressView("Asking the server…")
            case .noServer:
                Text("This build has no server lookup or no dashboard password.")
            case let .failed(reason):
                row("Status", "Not reachable: \(reason)")
            case let .loaded(stats, answeredIn):
                row("Status", answered(answeredIn))
                row("Running since", stats.server.started.formatted(date: .abbreviated, time: .shortened))
                row("Unknown callers checked",
                    "\(stats.callsChecked.last24h) in 24 hours, \(stats.callsChecked.last7d) in 7 days")
                if let last = stats.callsChecked.last {
                    row("Last unknown caller", last.formatted(date: .abbreviated, time: .shortened))
                }
                row("Errors, last 7 days", "\(stats.errors7d)")
            }
        }
    }

    @ViewBuilder private var databaseSection: some View {
        Section {
            if let database = stats.stats?.mac?.database {
                row("On the server", "\(database.numbers.formatted()) numbers")
                Text(database.prefixes.joined(separator: ", ")).foregroundStyle(.secondary)
            }
            row("On the phone", "\(BlockerPlan.numbersOnPhone.formatted()) numbers")
            if let check = stats.stats?.mac?.ofcomCheck {
                row("Ofcom list", "\(check.at.formatted(date: .abbreviated, time: .shortened)): \(describe(check))")
            }
        } header: {
            Text("Numbers blocked")
        } footer: {
            Text("The server blocks every number Ofcom has issued or opened for issuing in these ranges, written both as +44… and 0…. The Mac checks Ofcom's list every month.")
        }
    }

    @ViewBuilder private var blockedSection: some View {
        Section {
            if let report = stats.stats?.phone {
                row("Last 7 days", "\(report.blockedLast7Days)")
                row("Last \(report.daily.count) days", "\(report.blockedInReport)")
                ForEach(report.byPrefix.filter { $0.blockedServer + $0.blockedPhone > 0 }, id: \.prefix) { prefix in
                    row(prefix.prefix, "\(prefix.blockedServer + prefix.blockedPhone)")
                }
                ForEach(Array(report.blockedCalls.prefix(5).enumerated()), id: \.offset) { _, call in
                    VStack(alignment: .leading) {
                        Text(call.number).monospacedDigit()
                        Text("\(call.time.formatted(date: .abbreviated, time: .shortened)), blocked by \(call.by)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else if stats.stats != nil {
                Text("No call report yet. On the Mac, run scripts/call_history.sh, then python3 scripts/report.py --upload.")
            }
        } header: {
            Text("Blocked calls")
        } footer: {
            if let report = stats.stats?.phone {
                Text("From the Mac's call report of \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))\(newest(report)). The counts change only when that report runs again.")
            }
        }
    }

    private var phoneSection: some View {
        Section("Phone") {
            row("Filter", filterSummary)
            if let expiry = SigningProfile.expiry {
                row("Re-sign due", "\(expiry.formatted(date: .abbreviated, time: .shortened)) (\(daysLeft(until: expiry)))")
            }
        }
    }

    private var filterSummary: String {
        let on = status.enabled.filter { $0 }.count
        let parts = "\(on) of \(status.enabled.count) parts on"
        guard BlockerPlan.usesServerLookup else { return parts }
        return parts + (status.lookupEnabled ? ", server lookup on" : ", server lookup OFF")
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) { Text(value).multilineTextAlignment(.trailing) }
    }

    private func answered(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let text = "Answered in \(seconds.formatted(.number.precision(.fractionLength(1)))) s"
        // Measured on 4 October: about 0.2 s when awake, about 1 s when woken from sleep.
        return seconds >= 0.8 ? text + ", likely woke from sleep" : text
    }

    private func describe(_ check: ServerStats.MacNotes.OfcomCheck) -> String {
        switch check.result {
        case "no change": return "no change"
        case "changed": return "changed, \((check.added ?? 0).formatted()) to add, \((check.removed ?? 0).formatted()) to remove. Rebuild needed."
        default: return "check failed"
        }
    }

    private func newest(_ report: ServerStats.PhoneReport) -> String {
        guard let latest = report.latestCallInHistory else { return "" }
        return ", newest call in it \(latest.formatted(date: .abbreviated, time: .shortened))"
    }

    private func daysLeft(until date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        return days < 0 ? "expired" : days == 0 ? "today" : days == 1 ? "in 1 day" : "in \(days) days"
    }
}
