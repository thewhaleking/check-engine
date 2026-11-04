import OBDKit
import SwiftUI

struct ValueTile: View {
    let descriptor: PIDDescriptor
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(descriptor.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(valueText)
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(descriptor.unit)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(value == nil ? .gray : .accentColor)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeOut(duration: 0.2), value: value)
    }

    private var valueText: String {
        guard let value else { return "—" }
        return Self.format(value)
    }

    private var fraction: Double {
        guard let value else { return 0 }
        let r = descriptor.range
        return min(1, max(0, (value - r.lowerBound) / (r.upperBound - r.lowerBound)))
    }

    static func format(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.05 || abs(v) >= 1000 { return String(format: "%.0f", v) }
        return String(format: "%.1f", v)
    }
}
