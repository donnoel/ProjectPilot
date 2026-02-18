import SwiftUI

struct LogView: View {
    let logs: [ProjectPilotViewModel.LogEvent]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(logs) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Text(symbol(for: event.level))
                                .foregroundStyle(symbolColor(for: event.level))
                                .frame(width: 18, alignment: .leading)
                            Text(event.message)
                                .font(.caption)
                                .textSelection(.enabled)
                            Spacer()
                        }
                        .id(event.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.40),
                                        .white.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: logs.count) { _, _ in
                if let last = logs.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func symbol(for level: ProjectPilotViewModel.LogEvent.Level) -> String {
        switch level {
        case .info: return "•"
        case .success: return "✓"
        case .error: return "!"
        }
    }

    private func symbolColor(for level: ProjectPilotViewModel.LogEvent.Level) -> Color {
        switch level {
        case .info: return .blue
        case .success: return .green
        case .error: return .red
        }
    }
}

extension ProjectPilotViewModel {
    /// UI log event used by `LogView`.
    struct LogEvent: Identifiable, Hashable {
        enum Level: String, Hashable {
            case info
            case success
            case error
        }

        let id: UUID
        let level: Level
        let message: String

        init(id: UUID = UUID(), level: Level, message: String) {
            self.id = id
            self.level = level
            self.message = message
        }
    }
}
