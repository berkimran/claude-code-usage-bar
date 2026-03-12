import SwiftUI

struct TokenBreakdownView: View {
    let session: SessionUsage

    private var items: [(String, Int, Double)] {
        let total = max(session.contextTokens, 1)
        return [
            ("Cache Read", session.lastCacheRead, Double(session.lastCacheRead) / Double(total) * 100),
            ("Output", session.lastOutputTokens, Double(session.lastOutputTokens) / Double(total) * 100),
            ("Cache Created", session.lastCacheCreation, Double(session.lastCacheCreation) / Double(total) * 100),
            ("Input", session.lastInputTokens, Double(session.lastInputTokens) / Double(total) * 100),
        ].filter { $0.1 > 0 }
         .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Token Breakdown")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            ForEach(items, id: \.0) { item in
                HStack {
                    Text(item.0)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 100, alignment: .leading)

                    Text(formatNumber(item.1))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 70, alignment: .trailing)

                    Text(String(format: "%.1f%%", item.2))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
