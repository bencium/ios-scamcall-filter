import SwiftUI

struct BlockerView: View {
    @StateObject private var status = BlockerStatus()
    @StateObject private var stats = StatsModel()
    /// Launching with --details opens the Details screen straight away (used for screenshots).
    @State private var showsDetails = ProcessInfo.processInfo.arguments.contains("--details")
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { StatsView(stats: stats, status: status) } label: { Text(protectionSummary) }
                }
                Section("Block incoming 0845 calls") {
                    Text("The full 0845 rule uses six smaller parts stored on this phone. All six must be enabled for the complete rule.")
                    if !BlockerPlan.usesServerLookup {
                        Text("This fallback build also stores the 0843 number blocks Ofcom lists as allocated, in three more parts.")
                    }
                    Text("This also blocks legitimate callers using these numbers. Hidden numbers are not covered.")
                        .foregroundStyle(.secondary)
                }
                Section("Activation check") {
                    Text(status.message).accessibilityIdentifier("blockerStatus")
                    ForEach(0..<BlockerPlan.partCount, id: \.self) { index in
                        HStack {
                            Text(BlockerPlan.label(forPart: index + 1))
                            Spacer()
                            Text(status.enabled[index]
                                 ? (status.accepted[index] ? "On · checked" : "On") : "Off")
                                .foregroundStyle(status.enabled[index] ? .primary : .secondary)
                        }
                    }
                    if status.busy { ProgressView("Checking…") }
                    Button("Open iOS blocking settings") { status.settings() }
                    Button("Check enabled parts") { Task { await status.reloadEnabled() } }
                        .disabled(!status.enabled.contains(true) || status.busy)
                }
                if BlockerPlan.usesServerLookup { serverLookupSection }
                stopSection
                Section("Private device test") {
                    Text("No contacts, call history, or microphone access is requested. The 0845 parts never use the network. The server lookup sends only an encrypted query to your own server.")
                    Text(BlockerPlan.usesServerLookup ? "Version 0.4 · server lookup" : "Version 0.4 · on-device fallback")
                }
            }
            .navigationTitle("084x Blocker")
            .navigationDestination(isPresented: $showsDetails) { StatsView(stats: stats, status: status) }
            .task {
                async let fetched: Void = stats.refresh()
                await status.refresh()
                await fetched
                if ProcessInfo.processInfo.arguments.contains("--check-enabled") {
                    await status.reloadEnabled()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await status.refresh(); await stats.refresh() } }
            }
        }
    }

    private var protectionSummary: String {
        guard status.hasReadSwitches else { return "Checking protection…" }
        let complete = !status.enabled.contains(false) && (!BlockerPlan.usesServerLookup || status.lookupEnabled)
        let summary = complete ? "Protection ON" : "Protection INCOMPLETE"
        // Only a recent report says anything about this week, and only if its call history was
        // fresh when it ran: a copy that stopped days earlier shows quiet days that weren't quiet.
        guard let report = stats.stats?.phone, report.generatedAt.timeIntervalSinceNow > -2 * 86400,
              let newestCall = report.latestCallInHistory,
              newestCall.timeIntervalSince(report.generatedAt) > -2 * 86400
        else { return summary }
        return summary + ", \(report.blockedLast7Days) blocked this week"
    }

    private var serverLookupSection: some View {
        Section("Server lookup (\(BlockerPlan.serverPrefixes.joined(separator: ", ")))") {
            Text("Calls from these prefixes are checked against your private server as they arrive. The server cannot see which number called.")
            HStack {
                Text("Server lookup")
                Spacer()
                Text(status.lookupEnabled ? "On" : "Off")
                    .foregroundStyle(status.lookupEnabled ? .primary : .secondary)
            }
            Text("Needs mobile data at the moment of the call and adds a short delay before unknown callers ring. Calls from your contacts are not affected.")
                .foregroundStyle(.secondary)
            Button("Open lookup settings") { Task { await status.lookupSettings() } }
            Button("Refresh server data") { Task { await status.refreshLookup() } }
                .disabled(!status.lookupEnabled || status.busy)
        }
    }

    private var stopSection: some View {
        Section("Stop blocking") {
            Text("Turn off every 084x Blocker switch in iOS settings to stop this app’s rules.")
            Button("Open settings to disable") { status.settings() }
        }
    }
}
