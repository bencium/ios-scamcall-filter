import SwiftUI

struct BlockerView: View {
    @StateObject private var status = BlockerStatus()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section("Block incoming 0845 calls") {
                    Text("The full 0845 rule uses six smaller parts. All six must be enabled for the complete rule.")
                    Text("This also blocks legitimate callers using 0845. Other prefixes and hidden numbers are not covered.")
                        .foregroundStyle(.secondary)
                }
                Section("Activation check") {
                    Text("For this diagnostic, first enable only Parts 1 and 2, one at a time. Check those before enabling the remaining parts.")
                    Text(status.message).accessibilityIdentifier("blockerStatus")
                    ForEach(0..<BlockerPlan.partCount, id: \.self) { index in
                        HStack {
                            Text("Part \(index + 1) of 6")
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
                Section("Stop blocking") {
                    Text("Turn off all six 0845 Blocker switches in iOS settings to stop this app’s rule.")
                    Button("Open settings to disable") { status.settings() }
                }
                Section("Private device test") {
                    Text("No contacts, call history, microphone, or network access is requested. This app cannot identify scammers or count blocked calls.")
                    Text("Version 0.3 · loading diagnostic")
                }
            }
            .navigationTitle("0845 Blocker")
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
}
