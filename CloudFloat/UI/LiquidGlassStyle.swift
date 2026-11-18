import SwiftUI

/// Shared iOS 26 Liquid Glass surfaces with a material fallback for iOS 17–25.
///
/// The glass effect samples whatever is behind the view, so it is only useful on top of
/// real content (the start-page gradient, web pages, or the dark chrome backdrop).
extension View {
    @ViewBuilder
    func liquidGlass(
        cornerRadius: CGFloat,
        tint: Color = .clear,
        interactive: Bool = false
    ) -> some View {
        self.background {
            if #available(iOS 26.0, *) {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                if interactive {
                    shape
                        .fill(.clear)
                        .glassEffect(.regular.tint(tint).interactive(), in: shape)
                } else {
                    shape
                        .fill(.clear)
                        .glassEffect(.regular.tint(tint), in: shape)
                }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.10))
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.24), .white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    func liquidGlassCircle(tint: Color = .clear, interactive: Bool = false) -> some View {
        self.background {
            if #available(iOS 26.0, *) {
                if interactive {
                    Circle()
                        .fill(.clear)
                        .glassEffect(.regular.tint(tint).interactive(), in: Circle())
                } else {
                    Circle()
                        .fill(.clear)
                        .glassEffect(.regular.tint(tint), in: Circle())
                }
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(tint.opacity(0.10)))
            }
        }
        .overlay {
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.26), .white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    func liquidGlassCapsule(tint: Color = .clear, interactive: Bool = false) -> some View {
        self.background {
            if #available(iOS 26.0, *) {
                if interactive {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.regular.tint(tint).interactive(), in: Capsule())
                } else {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.regular.tint(tint), in: Capsule())
                }
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(tint.opacity(0.10)))
            }
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.24), .white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
        }
    }
}
