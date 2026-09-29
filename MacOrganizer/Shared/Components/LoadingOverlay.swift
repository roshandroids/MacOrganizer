import SwiftUI

/// Blocking progress overlay shown while a destructive/irreversible-feeling
/// action (Apply, Move to Trash) is actually running, so the app never looks
/// frozen mid-operation.
struct LoadingOverlay: View {
    let message: String
    var detail: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(.callout.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(minWidth: 220)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 20, y: 8)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
