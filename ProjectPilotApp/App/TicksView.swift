import SwiftUI
import TickCore

struct TicksView: View {
    @ObservedObject var model: TicksViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let session = model.activeSession {
                VStack(alignment: .leading, spacing: 8) {
                    Label(session.pausedAt == nil ? "Tick running" : "Tick paused",
                          systemImage: session.pausedAt == nil ? "record.circle" : "pause.circle")
                        .font(.subheadline)
                    Text(model.activeSpaceName)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.durationText(session.duration(at: context.date)))
                            .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                            .accessibilityLabel("Elapsed time")
                            .accessibilityValue(Self.spokenDuration(session.duration(at: context.date)))
                    }
                    Button("Stop Tick", systemImage: "stop.fill") {
                        Task { await model.stop() }
                    }
                    .disabled(!model.canStop)
                    .accessibilityHint("Stops the current Tick and saves its recorded time.")
                    .accessibilityIdentifier("ticks.stop")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }

            if model.spaces.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .center, spacing: 12) {
                Picker("Space", selection: $model.selectedSpaceID) {
                    ForEach(model.spaces) { space in
                        Text(space.name).tag(Optional(space.id))
                    }
                }
                .accessibilityIdentifier("ticks.spaces")
                .disabled(model.activeSession != nil || model.isBusy)

                if model.activeSession == nil {
                    Button("Start Tick", systemImage: "play.fill") {
                        Task { await model.start() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canStart)
                    .accessibilityHint("Starts recording time for the selected Space.")
                    .accessibilityIdentifier("ticks.start")
                }
                }
            }

            weeklySummary

            HStack {
                Text(model.syncStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ticks.syncStatus")
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .controlSize(.small)
                .disabled(model.isBusy)
            }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ticks.error")
            }
        }
        .padding(.vertical, 4)
        .task {
            model.isVisible = true
            model.beginMonitoring()
            await model.refresh()
        }
        .onDisappear { model.isVisible = false }
    }

    private var emptyMessage: String {
        if !model.hasLoaded { return "Loading your Spaces…" }
        if model.errorMessage != nil { return "Your Spaces aren't available yet. Check the iCloud connection below." }
        return "Create a Space in Ticks on your iPhone or iPad. It will appear here after syncing with the same iCloud account."
    }

    private var weeklySummary: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let summary = model.weeklySummary(at: context.date)
            let total = summary.spaces.reduce(0) { $0 + $1.duration }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This week").font(.headline)
                        Text("\(summary.count) Ticks · All Spaces")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Self.summaryDuration(total))
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .accessibilityLabel("This week, \(Self.summaryDuration(total))")
                }
                if !model.hasLoaded {
                    Text("Loading your weekly summary…").font(.caption).foregroundStyle(.secondary)
                } else if summary.spaces.isEmpty {
                    Text("No time recorded this week. Start a Tick above to begin.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(summary.spaces) { space in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(space.name).lineLimit(2)
                                        Spacer(minLength: 12)
                                        Text(Self.summaryDuration(space.duration))
                                            .monospacedDigit().foregroundStyle(.secondary)
                                    }
                                    .font(.callout)
                                    ProgressView(value: space.duration, total: max(total, 1))
                                        .tint(.accentColor)
                                        .accessibilityHidden(true)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .frame(height: CGFloat(min(summary.spaces.count, 4)) * 49)
                }
            }
            .padding(14)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private static func summaryDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(max(0, duration)) / 60
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = Int(max(0, duration))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    private static func spokenDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(max(0, duration))
        return "\(seconds / 3600) hours, \((seconds % 3600) / 60) minutes, \(seconds % 60) seconds"
    }
}
