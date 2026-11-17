import SwiftUI

/// Pure geometry helpers for the draggable floating toolbar ball. Kept separate from the
/// view so clamping and persistence can be unit-tested without UI.
enum FloatingBallGeometry {
    static func clamp(
        _ point: CGPoint,
        in size: CGSize,
        safeArea: EdgeInsets,
        diameter: CGFloat,
        margin: CGFloat = 6
    ) -> CGPoint {
        let radius = diameter / 2
        let minX = safeArea.leading + margin + radius
        let maxX = size.width - safeArea.trailing - margin - radius
        let minY = safeArea.top + margin + radius
        let maxY = size.height - safeArea.bottom - margin - radius
        let x = max(minX, min(maxX, point.x))
        let y = max(minY, min(maxY, point.y))
        return CGPoint(x: x, y: y)
    }

    static func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return CGPoint(x: 0.9, y: 0.6) }
        return CGPoint(
            x: min(max(point.x / size.width, 0), 1),
            y: min(max(point.y / size.height, 0), 1)
        )
    }

    static func point(fromNormalized normalized: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(normalized.x, 0), 1) * size.width,
            y: min(max(normalized.y, 0), 1) * size.height
        )
    }
}

/// A small draggable ball that replaces the browser chrome. Tap to expand the toolbar;
/// drag to move it anywhere inside the safe area. Position is persisted by the caller.
struct FloatingToolbarBall: View {
    let containerSize: CGSize
    let safeArea: EdgeInsets
    let normalizedPosition: CGPoint
    let showsPiPBadge: Bool
    let onTap: () -> Void
    let onMoved: (CGPoint) -> Void

    @State private var position: CGPoint?
    @State private var dragOrigin: CGPoint?

    private let diameter: CGFloat = 56

    var body: some View {
        let point = currentPoint
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
            Image(systemName: "globe")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.primary)
            if showsPiPBadge {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                    .offset(x: 2, y: -2)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
        .contentShape(Circle())
        .position(point)
        .highPriorityGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    let origin = dragOrigin ?? point
                    if dragOrigin == nil { dragOrigin = origin }
                    position = FloatingBallGeometry.clamp(
                        CGPoint(
                            x: origin.x + value.translation.width,
                            y: origin.y + value.translation.height
                        ),
                        in: containerSize,
                        safeArea: safeArea,
                        diameter: diameter
                    )
                }
                .onEnded { _ in
                    dragOrigin = nil
                    if let position {
                        onMoved(FloatingBallGeometry.normalized(position, in: containerSize))
                    }
                }
        )
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("展开工具栏")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            if position == nil {
                position = FloatingBallGeometry.clamp(
                    FloatingBallGeometry.point(fromNormalized: normalizedPosition, in: containerSize),
                    in: containerSize,
                    safeArea: safeArea,
                    diameter: diameter
                )
            }
        }
        .onChange(of: containerSize) { _, newSize in
            if let position {
                self.position = FloatingBallGeometry.clamp(
                    position,
                    in: newSize,
                    safeArea: safeArea,
                    diameter: diameter
                )
            }
        }
    }

    private var currentPoint: CGPoint {
        position ?? FloatingBallGeometry.clamp(
            FloatingBallGeometry.point(fromNormalized: normalizedPosition, in: containerSize),
            in: containerSize,
            safeArea: safeArea,
            diameter: diameter
        )
    }
}
