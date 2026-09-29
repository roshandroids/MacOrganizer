import SwiftUI

/// Liquid Glass styling shared across the app, with a user-controlled
/// transparency dial (Settings → Appearance → Transparency, 0...1).
///
/// On macOS 26+ this blends between a solid panel and real Liquid Glass
/// (`View.glassEffect`, the system material introduced with Liquid Glass —
/// see `SwiftUICore.Glass`). On earlier systems it blends between solid and
/// a translucent `Material` as a close approximation, so the transparency
/// dial always does something regardless of OS version.
enum GlassStyle {
    static let cornerRadius: CGFloat = 14
}

private struct GlassPanel<S: Shape>: ViewModifier {
    let intensity: Double
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                shape.fill(Color(nsColor: .controlBackgroundColor))
                    .opacity(1 - intensity)
                glassLayer
                    .opacity(intensity)
            }
        }
    }

    @ViewBuilder
    private var glassLayer: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(Glass.regular.interactive(interactive), in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

extension View {
    /// Applies the app's Liquid Glass panel treatment behind this view,
    /// scaled by the user's transparency setting (0 = solid, 1 = full glass).
    func glassPanel(intensity: Double, cornerRadius: CGFloat = GlassStyle.cornerRadius, interactive: Bool = false) -> some View {
        modifier(GlassPanel(intensity: intensity, shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: interactive))
    }
}

/// A primary/secondary action button that uses real Liquid Glass button
/// styles on macOS 26+ (`.glass` / `.glassProminent`), falling back to the
/// classic bordered styles on earlier systems or when the user has dialed
/// transparency down to 0.
struct GlassActionButton<Label: View>: View {
    let prominent: Bool
    let intensity: Double
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        if intensity > 0.01, #available(macOS 26.0, *) {
            if prominent {
                Button(action: action, label: label).buttonStyle(.glassProminent)
            } else {
                Button(action: action, label: label).buttonStyle(.glass)
            }
        } else {
            if prominent {
                Button(action: action, label: label).buttonStyle(.borderedProminent)
            } else {
                Button(action: action, label: label).buttonStyle(.bordered)
            }
        }
    }
}
