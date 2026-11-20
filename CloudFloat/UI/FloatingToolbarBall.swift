import SwiftUI

/// Pure geometry helpers for draggable floating controls. Kept separate from the view so
/// clamping, four-edge snapping and persistence can be unit-tested without UI.
///
/// The ball intentionally uses the physical screen edges (not the system safe area): on
/// rounded phones the safe-area top/bottom can be 60+ pt, which made a top/bottom-snapped
/// ball look "far from the edge". A small fixed margin keeps all four edges consistent.
enum FloatingBallGeometry {
    enum Edge: String, Equatable {
        case left, right, top, bottom
    }

    static func clamp(
        _ point: CGPoint,
        in size: CGSize,
        diameter: CGFloat,
        margin: CGFloat = 6,
        topSafeInset: CGFloat = 0
    ) -> CGPoint {
        let radius = diameter / 2
        let minX = margin + radius
        let maxX = size.width - margin - radius
        let minY = max(margin + radius, topSafeInset + radius)
        let maxY = size.height - margin - radius
        return CGPoint(
            x: max(minX, min(maxX, point.x)),
            y: max(minY, min(maxY, point.y))
        )
    }

    /// Chooses the nearest of the four screen edges.
    static func nearestEdge(_ point: CGPoint, in size: CGSize) -> Edge {
        let left = max(0, point.x)
        let right = max(0, size.width - point.x)
        let top = max(0, point.y)
        let bottom = max(0, size.height - point.y)
        let minimum = min(min(left, right), min(top, bottom))
        if minimum == left { return .left }
        if minimum == right { return .right }
        if minimum == top { return .top }
        return .bottom
    }

    /// Snaps to an edge while keeping the whole control visible.
    static func visibleEdgePoint(
        _ point: CGPoint,
        in size: CGSize,
        diameter: CGFloat,
        edge: Edge? = nil,
        margin: CGFloat = 6,
        topSafeInset: CGFloat = 0
    ) -> CGPoint {
        let radius = diameter / 2
        let minX = margin + radius
        let maxX = size.width - margin - radius
        let minY = max(margin + radius, topSafeInset + radius)
        let maxY = size.height - margin - radius
        let resolved = edge ?? nearestEdge(point, in: size)
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

    /// Idle state: half of the control is tucked outside the nearest edge.
    static func idleEdgePoint(
        _ point: CGPoint,
        in size: CGSize,
        diameter: CGFloat,
        edge: Edge? = nil,
        topSafeInset: CGFloat = 0
    ) -> CGPoint {
        // The floating control is the only way out of fullscreen. Do not tuck it half
        // outside the screen; keep the whole glass button and its exit icon findable.
        visibleEdgePoint(
            point,
            in: size,
            diameter: diameter,
            edge: edge,
            topSafeInset: topSafeInset
        )
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

/// A draggable glass control that can represent either the collapsed toolbar or PiP.
///
/// - Drag anywhere; on release it snaps to the nearest of the four edges.
/// - After 3 seconds without interaction it tucks half outside that edge and fades.
/// - Tap invokes `onTap`.
/// - Layout changes (portrait/landscape/PiP) remap the normalized anchor without forcing a
///   new edge, so the control keeps the same relative position; only idle controls re-tuck.
struct FloatingEdgeControl: View {
    let containerSize: CGSize
    let normalizedPosition: CGPoint
    let preferredEdge: FloatingBallGeometry.Edge?
    var topSafeInset: CGFloat = 0
    let diameter: CGFloat
    let tint: Color
    let icon: String?
    let showsCenterDot: Bool
    let showsPiPBadge: Bool
    let accessibilityLabel: String
    let onTap: () -> Void
    let onMoved: (CGPoint) -> Void
    let onEdgeChanged: (FloatingBallGeometry.Edge) -> Void

    @State private var position: CGPoint?
    @State private var normalizedAnchor: CGPoint?
    @State private var dragOrigin: CGPoint?
    @State private var lastEdge: FloatingBallGeometry.Edge?
    @State private var isIdleCollapsed = false
    @State private var idleTask: Task<Void, Never>?

    private let idleDelay: UInt64 = 3_000_000_000

    var body: some View {
        let point = currentPoint
        ZStack {
            ballBackground
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: diameter * 0.36, weight: .semibold))
                    .foregroundStyle(.primary)
            } else if showsCenterDot {
                Circle()
                    .fill(tint.opacity(0.9))
                    .frame(width: max(5, diameter * 0.11), height: max(5, diameter * 0.11))
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsPiPBadge {
                Circle()
                    .fill(Color.green)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 1))
                    .offset(x: 1, y: -1)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(isIdleCollapsed ? 0.12 : 0.24), radius: 9, y: 3)
        .opacity(isIdleCollapsed ? 0.9 : 1.0)
        .scaleEffect(isIdleCollapsed ? 0.92 : 1.0)
        .contentShape(Circle())
        .position(point)
        .animation(.easeInOut(duration: 0.25), value: isIdleCollapsed)
        .highPriorityGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    cancelIdleTask()
                    if isIdleCollapsed { isIdleCollapsed = false }
                    let origin = dragOrigin ?? currentPoint
                    if dragOrigin == nil { dragOrigin = origin }
                    position = FloatingBallGeometry.clamp(
                        CGPoint(
                            x: origin.x + value.translation.width,
                            y: origin.y + value.translation.height
                        ),
                        in: containerSize,
                        diameter: diameter,
                        topSafeInset: topSafeInset
                    )
                }
                .onEnded { _ in
                    dragOrigin = nil
                    let edge = FloatingBallGeometry.nearestEdge(currentPoint, in: containerSize)
                    lastEdge = edge
                    onEdgeChanged(edge)
                    let snapped = FloatingBallGeometry.visibleEdgePoint(
                        currentPoint,
                        in: containerSize,
                        diameter: diameter,
                        edge: edge,
                        topSafeInset: topSafeInset
                    )
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityEdgeValue)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            if position == nil {
                normalizedAnchor = normalizedPosition
                let mapped = FloatingBallGeometry.point(
                    fromNormalized: normalizedPosition,
                    in: containerSize
                )
                let edge = preferredEdge ?? FloatingBallGeometry.nearestEdge(mapped, in: containerSize)
                lastEdge = edge
                position = FloatingBallGeometry.visibleEdgePoint(
                    mapped,
                    in: containerSize,
                    diameter: diameter,
                    edge: edge
                )
                onEdgeChanged(edge)
                persist(position!)
            }
            scheduleIdleCollapse()
        }
        .onDisappear {
            cancelIdleTask()
        }
        .onChange(of: containerSize) { oldSize, newSize in
            relayout(from: oldSize, to: newSize)
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
                .glassEffect(.regular.tint(tint.opacity(0.35)).interactive(), in: Circle())
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(tint.opacity(0.12)))
        }
    }

    private var accessibilityEdgeValue: String {
        let edge = lastEdge ?? FloatingBallGeometry.nearestEdge(currentPoint, in: containerSize)
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
            diameter: diameter
        )
    }

    /// Maps the stored normalized anchor into the new layout without forcing a new edge.
    /// This is the fix for portrait/landscape/PiP changes: the control keeps its relative
    /// position instead of jumping to a different edge.
    private func relayout(from oldSize: CGSize, to newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }

        // SwiftUI can deliver the first container-size change (for example when the keyboard
        // dismisses as the toolbar collapses) before onAppear. Initialise from the persisted
        // normalized anchor here instead of deriving an anchor from a stale old size.
        if position == nil, lastEdge == nil {
            normalizedAnchor = normalizedPosition
            let mapped = FloatingBallGeometry.point(
                fromNormalized: normalizedPosition,
                in: newSize
            )
            let edge = preferredEdge ?? FloatingBallGeometry.nearestEdge(mapped, in: newSize)
            lastEdge = edge
            let placed = FloatingBallGeometry.visibleEdgePoint(
                mapped,
                in: newSize,
                diameter: diameter,
                edge: edge
            )
            position = placed
            onEdgeChanged(edge)
            persist(placed)
            return
        }

        let anchor: CGPoint
        if let stored = normalizedAnchor {
            anchor = stored
        } else if oldSize.width > 0, oldSize.height > 0 {
            anchor = FloatingBallGeometry.normalized(currentPoint, in: oldSize)
        } else {
            anchor = normalizedPosition
        }
        let mapped = FloatingBallGeometry.point(fromNormalized: anchor, in: newSize)
        let finalPoint: CGPoint
        if isIdleCollapsed {
            finalPoint = FloatingBallGeometry.idleEdgePoint(
                mapped,
                in: newSize,
                diameter: diameter,
                edge: lastEdge
            )
        } else if let edge = lastEdge {
            // Keep the ball hugging the same screen edge after portrait/landscape/PiP
            // changes; only the position along that edge follows the normalized anchor.
            finalPoint = FloatingBallGeometry.visibleEdgePoint(
                mapped,
                in: newSize,
                diameter: diameter,
                edge: edge
            )
        } else {
            finalPoint = FloatingBallGeometry.clamp(
                mapped,
                in: newSize,
                diameter: diameter
            )
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            position = finalPoint
        }
        let normalized = FloatingBallGeometry.normalized(finalPoint, in: newSize)
        normalizedAnchor = normalized
        onMoved(normalized)
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
            let snapped = FloatingBallGeometry.idleEdgePoint(
                currentPoint,
                in: containerSize,
                diameter: diameter,
                edge: lastEdge,
                topSafeInset: topSafeInset
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
