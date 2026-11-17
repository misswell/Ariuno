import SwiftUI

/// Pure geometry helpers for the draggable floating toolbar ball. Kept separate from the
/// view so clamping, four-edge snapping and persistence can be unit-tested without UI.
enum FloatingBallGeometry {
    enum Edge: Equatable {
        case left, right, top, bottom
    }

    static func clamp(
        _ point: CGPoint,
        in size: CGSize,
        safeArea: EdgeInsets,
        diameter: CGFloat,
        margin: CGFloat = 6
    ) -> CGPoint {
        let radius = diameter / 2
        let leading = max(0, safeArea.leading)
        let trailing = max(0, safeArea.trailing)
        let top = max(0, safeArea.top)
        let bottom = max(0, safeArea.bottom)
        let minX = leading + margin + radius
        let maxX = size.width - trailing - margin - radius
        let minY = top + margin + radius
        let maxY = size.height - bottom - margin - radius
        let x = max(minX, min(maxX, point.x))
        let y = max(minY, min(maxY, point.y))
        return CGPoint(x: x, y: y)
    }

    /// Chooses the nearest of the four safe-area edges. Corner cases resolve deterministically
    /// to the smaller distance (left/right before top/bottom on ties).
    static func nearestEdge(
        _ point: CGPoint,
        in size: CGSize,
        safeArea: EdgeInsets
    ) -> Edge {
        let left = max(0, point.x - max(0, safeArea.leading))
        let right = max(0, size.width - max(0, safeArea.trailing) - point.x)
        let top = max(0, point.y - max(0, safeArea.top))
        let bottom = max(0, size.height - max(0, safeArea.bottom) - point.y)
        let minimum = min(min(left, right), min(top, bottom))
        if minimum == left { return .left }
        if minimum == right { return .right }
        if minimum == top { return .top }
        return .bottom
    }

    /// Snaps to an edge while keeping the whole ball visible.
    static func visibleEdgePoint(
        _ point: CGPoint,
        in size: CGSize,
        safeArea: EdgeInsets,
        diameter: CGFloat,
        edge: Edge? = nil,
        margin: CGFloat = 6
    ) -> CGPoint {
        let radius = diameter / 2
        let leading = max(0, safeArea.leading)
        let trailing = max(0, safeArea.trailing)
        let top = max(0, safeArea.top)
        let bottom = max(0, safeArea.bottom)
        let minX = leading + margin + radius
        let maxX = size.width - trailing - margin - radius
        let minY = top + margin + radius
        let maxY = size.height - bottom - margin - radius
        let resolved = edge ?? nearestEdge(point, in: size, safeArea: safeArea)
        switch resolved {
        case .left:
            return CGPoint(x: minX, y: max(minY, min(maxY, point.y)))
        case .right:
            return CGPoint(x: maxX, y: max(minY, min(maxY, point.y)))
        case .top:
            return CGPoint(x: max(minX, min(maxX, point.x)), y: minY)
        case .bottom:
            return CGPoint(x: max(minX, min(maxX, point.x)), y: maxY)
        }
    }

    /// Idle state: half of the ball is tucked outside the nearest edge.
    static func idleEdgePoint(
        _ point: CGPoint,
        in size: CGSize,
        safeArea: EdgeInsets,
        diameter: CGFloat,
        edge: Edge? = nil
    ) -> CGPoint {
        let radius = diameter / 2
        let leading = max(0, safeArea.leading)
        let trailing = max(0, safeArea.trailing)
        let top = max(0, safeArea.top)
        let bottom = max(0, safeArea.bottom)
        let resolved = edge ?? nearestEdge(point, in: size, safeArea: safeArea)
        let minX = leading + radius
        let maxX = size.width - trailing - radius
        let minY = top + radius
        let maxY = size.height - bottom - radius
        switch resolved {
        case .left:
            return CGPoint(x: leading, y: max(minY, min(maxY, point.y)))
        case .right:
            return CGPoint(x: size.width - trailing, y: max(minY, min(maxY, point.y)))
        case .top:
            return CGPoint(x: max(minX, min(maxX, point.x)), y: top)
        case .bottom:
            return CGPoint(x: max(minX, min(maxX, point.x)), y: size.height - bottom)
        }
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
/// - Drag anywhere; on release it snaps to the nearest of the four safe-area edges.
/// - After 3 seconds without interaction it tucks half outside that edge and fades.
/// - Tap restores the full toolbar.
/// - Position is kept as a normalized anchor so orientation/PiP layout changes remap it
///   instead of leaving the ball at a stale absolute point.
struct FloatingToolbarBall: View {
    let containerSize: CGSize
    let safeArea: EdgeInsets
    let normalizedPosition: CGPoint
    let diameter: CGFloat
    let showsPiPBadge: Bool
    let onTap: () -> Void
    let onMoved: (CGPoint) -> Void

    @State private var position: CGPoint?
    @State private var normalizedAnchor: CGPoint?
    @State private var lastContainerSize: CGSize = .zero
    @State private var dragOrigin: CGPoint?
    @State private var preferredEdge: FloatingBallGeometry.Edge?
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
                    let edge = FloatingBallGeometry.nearestEdge(
                        currentPoint,
                        in: containerSize,
                        safeArea: safeArea
                    )
                    let snapped = FloatingBallGeometry.visibleEdgePoint(
                        currentPoint,
                        in: containerSize,
                        safeArea: safeArea,
                        diameter: diameter,
                        edge: edge
                    )
                    preferredEdge = edge
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        position = snapped
                    }
                    persist(snapped)
                    scheduleIdleCollapse()
                }
        )
        .onTapGesture {
            cancelIdleTask()
            onTap()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("展开工具栏")
        .accessibilityValue(accessibilityEdgeValue)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            if position == nil {
                let anchor = normalizedPosition
                normalizedAnchor = anchor
                let mapped = FloatingBallGeometry.point(fromNormalized: anchor, in: containerSize)
                let edge = FloatingBallGeometry.nearestEdge(
                    mapped,
                    in: containerSize,
                    safeArea: safeArea
                )
                preferredEdge = edge
                position = FloatingBallGeometry.visibleEdgePoint(
                    mapped,
                    in: containerSize,
                    safeArea: safeArea,
                    diameter: diameter,
                    edge: edge
                )
                persist(position!)
            }
            lastContainerSize = containerSize
            scheduleIdleCollapse()
        }
        .onDisappear {
            cancelIdleTask()
        }
        .onChange(of: containerSize) { oldSize, newSize in
            relayout(from: oldSize, to: newSize)
        }
        .onChange(of: safeArea) { _, _ in
            relayout(from: containerSize, to: containerSize)
        }
        .onChange(of: diameter) { _, _ in
            relayout(from: containerSize, to: containerSize)
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

    private var accessibilityEdgeValue: String {
        let edge = preferredEdge ?? FloatingBallGeometry.nearestEdge(
            currentPoint,
            in: containerSize,
            safeArea: safeArea
        )
        let name: String
        switch edge {
        case .left: name = "左侧"
        case .right: name = "右侧"
        case .top: name = "顶部"
        case .bottom: name = "底部"
        }
        return isIdleCollapsed ? "\(name)，已半收" : name
    }

    private var currentPoint: CGPoint {
        position ?? FloatingBallGeometry.visibleEdgePoint(
            FloatingBallGeometry.point(fromNormalized: normalizedPosition, in: containerSize),
            in: containerSize,
            safeArea: safeArea,
            diameter: diameter
        )
    }

    /// Re-maps the normalized anchor into the new layout, then snaps it to the nearest edge
    /// (or keeps the half-tucked idle position). This is what fixes portrait/landscape and
    /// PiP-induced layout changes.
    private func relayout(from oldSize: CGSize, to newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        let anchor: CGPoint
        if let stored = normalizedAnchor {
            anchor = stored
        } else if oldSize.width > 0, oldSize.height > 0 {
            anchor = FloatingBallGeometry.normalized(currentPoint, in: oldSize)
        } else {
            anchor = normalizedPosition
        }
        let mapped = FloatingBallGeometry.point(fromNormalized: anchor, in: newSize)
        let edge = preferredEdge ?? FloatingBallGeometry.nearestEdge(
            mapped,
            in: newSize,
            safeArea: safeArea
        )
        let snapped = FloatingBallGeometry.visibleEdgePoint(
            mapped,
            in: newSize,
            safeArea: safeArea,
            diameter: diameter,
            edge: edge
        )
        preferredEdge = edge
        withAnimation(.easeInOut(duration: 0.2)) {
            if isIdleCollapsed {
                position = FloatingBallGeometry.idleEdgePoint(
                    snapped,
                    in: newSize,
                    safeArea: safeArea,
                    diameter: diameter,
                    edge: edge
                )
            } else {
                position = snapped
            }
        }
        normalizedAnchor = FloatingBallGeometry.normalized(snapped, in: newSize)
        lastContainerSize = newSize
        persist(snapped)
    }

    private func persist(_ point: CGPoint) {
        let normalized = FloatingBallGeometry.normalized(point, in: containerSize)
        normalizedAnchor = normalized
        onMoved(normalized)
    }

    private func scheduleIdleCollapse() {
        cancelIdleTask()
        idleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: idleDelay)
            guard !Task.isCancelled else { return }
            let edge = preferredEdge ?? FloatingBallGeometry.nearestEdge(
                currentPoint,
                in: containerSize,
                safeArea: safeArea
            )
            let snapped = FloatingBallGeometry.idleEdgePoint(
                currentPoint,
                in: containerSize,
                safeArea: safeArea,
                diameter: diameter,
                edge: edge
            )
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                position = snapped
                isIdleCollapsed = true
            }
        }
    }

    private func cancelIdleTask() {
        idleTask?.cancel()
        idleTask = nil
    }
}
