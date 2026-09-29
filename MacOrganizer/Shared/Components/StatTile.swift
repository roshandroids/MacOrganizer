import SwiftUI

/// A compact label/value pair used on Overview and Report — not a decorative
/// "card", just aligned text with an accent-colored value.
struct StatTile: View {
    let title: String
    let value: String
    var tint: Color = .primary
    var symbolName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.subheadline)
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint == .primary ? .primary : tint)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
