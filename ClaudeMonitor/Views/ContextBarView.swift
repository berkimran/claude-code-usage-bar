import SwiftUI

struct UsageBarView: View {
    let label: String
    let percentage: Double
    let resetString: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.bold())
                Spacer()
                Text("Resets in \(resetString)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * min(CGFloat(percentage) / 100, 1.0), height: 12)
                }
            }
            .frame(height: 12)

            HStack {
                Text(String(format: "%.0f%% used", percentage))
                    .font(.system(.title2, design: .rounded).bold())
                    .foregroundColor(barColor)

                Spacer()
            }
        }
    }

    private var barColor: Color {
        switch percentage {
        case 0..<Constants.greenMax: return .green
        case Constants.greenMax..<Constants.yellowMax: return .yellow
        case Constants.yellowMax..<Constants.orangeMax: return .orange
        default: return .red
        }
    }
}
