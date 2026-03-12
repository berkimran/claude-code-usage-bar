import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Rate Limit Usage (primary)
            if let rl = appState.rateLimit {
                rateLimitSection(rl)
            } else if let error = appState.lastError {
                errorView(error)
            }

            Divider()

            // Active session info
            if let session = appState.activeSession {
                activeSessionSection(session)
                Divider()
            }

            // Recent Projects
            projectsSection

            Divider()

            footerView
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Rate Limit

    @ViewBuilder
    private func rateLimitSection(_ rl: RateLimitInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Usage Limits")
                    .font(.headline)
                Spacer()
                statusBadge(rl)
            }

            // 5-hour window (primary)
            UsageBarView(
                label: "5-Hour Window",
                percentage: rl.primaryPercentage,
                resetString: rl.fiveHourResetString
            )

            // 7-day window
            UsageBarView(
                label: "7-Day Window",
                percentage: rl.weeklyPercentage,
                resetString: rl.sevenDayResetString
            )

            if !rl.overageDisabledReason.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("Extra usage: \(rl.overageDisabledReason.replacingOccurrences(of: "_", with: " "))")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }

            Text("Updated \(timeAgo(rl.lastUpdated))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func statusBadge(_ rl: RateLimitInfo) -> some View {
        if rl.isRejected {
            Text("LIMIT REACHED")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.2))
                .foregroundColor(.red)
                .cornerRadius(4)
        } else if rl.isWarning {
            Text("WARNING")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .foregroundColor(.orange)
                .cornerRadius(4)
        }
    }

    // MARK: - Active Session

    @ViewBuilder
    private func activeSessionSection(_ session: SessionUsage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Active Session")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Text(session.model)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(3)
            }

            Text(session.shortProjectPath)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack {
                Label("\(session.apiCallCount) calls", systemImage: "arrow.up.arrow.down")
                Spacer()
                Text(costString(session.costUSD))
                    .bold()
                Spacer()
                Label(session.durationString, systemImage: "clock")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            // Context window compact view
            HStack(spacing: 4) {
                Text("Context:")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(contextColor(session.contextPercentage))
                            .frame(width: geo.size.width * min(CGFloat(session.contextPercentage) / 100, 1.0), height: 6)
                    }
                }
                .frame(height: 6)

                Text(String(format: "%.0f%%", session.contextPercentage))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
    }

    // MARK: - Error

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.orange)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Check Claude Code login status")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent Projects")
                .font(.caption)
                .foregroundColor(.secondary)

            if appState.projects.isEmpty {
                Text("No project data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(appState.projects.prefix(5)) { project in
                    HStack {
                        Text(project.shortPath)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.head)

                        Spacer()

                        Text(costString(project.cost))
                            .font(.system(.caption, design: .monospaced).bold())
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button {
                appState.openSettings()
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                appState.refreshAll()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
    }

    // MARK: - Helpers

    private func costString(_ cost: Double) -> String {
        if cost >= 100 {
            return String(format: "$%.0f", cost)
        } else if cost >= 10 {
            return String(format: "$%.1f", cost)
        }
        return String(format: "$%.2f", cost)
    }

    private func contextColor(_ pct: Double) -> Color {
        switch pct {
        case 0..<60: return .green
        case 60..<80: return .yellow
        case 80..<90: return .orange
        default: return .red
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
