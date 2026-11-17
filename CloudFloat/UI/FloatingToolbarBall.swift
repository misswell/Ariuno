import SwiftUI

/// Pure geometry helpers for the draggable floating toolbar ball. Kept separate from the
/// view so clamping, edge snapping and persistence can be unit-tested without UI.
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

    /// Snaps a point to the nearest left/right edge while keeping the whole ball visible.
    static func visibleEdgePoint(
        _ point: CGPoint,
        in size: CGSize,
        safeArea: EdgeInsets,
        diameter: CGFloat,
        margin: CGFloat = 6
    ) -> CGPoint {
        let radius = diameter / 2
        let leftX = safeArea.leading + margin + radius
        let rightX = size.width - safeArea.trailing - margin - radius
        let x = point.x < size.width / 2 ? leftX : rightX
        let y = min(
            max(point.y, safeArea.top + margin + radius),
            size.height - safeArea.bottom - margin - radius
        )
        return CGPoint(x: x, y: y)
    }

    /// Idle state: half of the ball is tucked outside the nearest edge.
    static func idleEdgePoint(
        _ point: CGPoint,
        in size: CGSize,
        safeArea: EdgeInsets,
        diameter: CGFloat
    ) -> CGPoint {
        let radius = diameter / 2
        let x = point.x < size.width / 2 ? safeArea.leading : size.width - safeArea.trailing
        let y = min(
            max(point.y, safeArea.top + radius),
            size.height - safeArea.bottom - radius
        )
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

/// A draggable glass ball that replaces the browser chrome.
///
/// - Drag anywhere; on release it snaps to the nearest edge.
/// - After 3 seconds without interaction it tucks half outside the edge and fades.
/// - Tap restores the full toolbar.
struct FloatingToolbarBall: View {
    let containerSize: CGSize
    let safeArea: EdgeInsets
    let normalizedPosition: CGPoint
    let diameter: CGFloat
    let showsPiPBadge: Bool
    let onTap: () -> Void
    let onMoved: (CGPoint) -> Void

    @State private var position: CGPoint?
    @State private var dragOrigin: CGPoint?
    @State private var isIdleCollapsed = false
    @State private var idleTask: Task<Void, Never>?

    private let idleDelay: UInt64 = 3_000_000_000

    var body: some View {
        let point = currentPoint
        ZStack(alignment: .topTrailing) {
            ballBackground
            if showsPiPBadge {
                Circle()
                    .fill(Color.green)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 1))
                    .offset(x: 1, y: -1)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(isIdleCollapsed ? 0.12 : 0.22), radius: 8, y: 3)
        .opacity(isIdleCollapsed ? 0.45 : 1.0)
        .contentShape(Circle())
        .position(point)
        .animation(.easeInOut(duration: 0.25), value: isIdleCollapsed)
        .highPriorityGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    cancelIdleTask()
                    if isIdleCollapsed {
                        isIdleCollapsed = false
                    }
                    let origin = dragOrigin ?? currentPoint
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
                    let snapped = FloatingBallGeometry.visibleEdgePoint(
                        currentPoint,
                        in: containerSize,
                        safeArea: safeArea,
                        diameter: diameter
                    )
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        position = snapped
                    }
                    onMoved(FloatingBallGeometry.normalized(snapped, in: containerSize))
                    scheduleIdleCollapse()
                }
        )
        .onTapGesture {
            cancelIdleTask()
            onTap()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("展开工具栏")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            if position == nil {
                position = FloatingBallGeometry.visibleEdgePoint(
                    FloatingBallGeometry.point(fromNormalized: normalizedPosition, in: containerSize),
                    in: containerSize,
                    safeArea: safeArea,
                    diameter: diameter
                )
            }
            scheduleIdleCollapse()
        }
        .onDisappear {
            cancelIdleTask()
        }
        .onChange(of: containerSize) { _, newSize in
            guard let current = position else { return }
            position = FloatingBallGeometry.visibleEdgePoint(
                current,
                in: newSize,
                safeArea: safeArea,
                diameter: diameter
            )
        }
        .onChange(of: diameter) { _, _ in
            guard let current = position else { return }
            position = FloatingBallGeometry.visibleEdgePoint(
                current,
                in: containerSize,
                safeArea: safeArea,
                diameter: diameter
            )
        }
    }

    @ViewBuilder
    private var ballBackground: some View {
        if #available(iOS 26.0, *) {
            Circle()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            Circle()
                .fill(.ultraThinMaterial)
        }
    }

    private var currentPoint: CGPoint {
        position ?? FloatingBallGeometry.visibleEdgePoint(
            FloatingBallGeometry.point(fromNormalized: normalizedPosition, in: containerSize),
            in: containerSize,
            safeArea: safeArea,
            diameter: diameter
        )
    }

    private func scheduleIdleCollapse() {
        cancelIdleTask()
        idleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: idleDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                position = FloatingBallGeometry.idleEdgePoint(
                    currentPoint,
                    in: containerSize,
                    safeArea: safeArea,
                    diameter: diameter
                )
                isIdleCollapsed = true
            }
        }
    }

    private func cancelIdleTask() {
        idleTask?.cancel()
        idleTask = nil
    }
}
