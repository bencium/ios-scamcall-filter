import SwiftUI

struct BlockerView: View {
    @StateObject private var status = BlockerStatus()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
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
            .task {
                await status.refresh()
                if ProcessInfo.processInfo.arguments.contains("--check-enabled") {
                    await status.reloadEnabled()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await status.refresh() } }
            }
        }
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
