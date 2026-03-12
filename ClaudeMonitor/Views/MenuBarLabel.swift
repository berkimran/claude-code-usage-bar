import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "brain.head.profile")

            if let rl = appState.rateLimit {
                Text(percentageText(rl.primaryPercentage))
                    .monospacedDigit()

                if appState.showCostInMenuBar, let session = appState.activeSession {
                    Text("|")
                        .foregroundColor(.secondary)
                    Text(costText(session.costUSD))
                        .monospacedDigit()
                }
            } else {
                Text("--")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func percentageText(_ pct: Double) -> String {
        if pct < 1 && pct > 0 {
            return "<1%"
        }
        return String(format: "%.0f%%", pct)
    }

    private func costText(_ cost: Double) -> String {
        if cost >= 100 {
            return String(format: "$%.0f", cost)
        } else if cost >= 10 {
            return String(format: "$%.1f", cost)
        }
        return String(format: "$%.2f", cost)
    }
}
