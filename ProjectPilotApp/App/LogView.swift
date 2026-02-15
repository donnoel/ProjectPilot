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
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onChange(of: logs.count) { _ in
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
}
