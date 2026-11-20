import SwiftUI
import XCTest
@testable import Ariuno

final class FloatingBallGeometryTests: XCTestCase {
    private let size = CGSize(width: 390, height: 844)
    private let diameter: CGFloat = 56

    func testClampKeepsControlInsideScreenEdges() {
        let topLeft = FloatingBallGeometry.clamp(
            CGPoint(x: -100, y: -100),
            in: size,
            diameter: diameter
        )
        XCTAssertEqual(topLeft.x, 34, accuracy: 0.01)
        XCTAssertEqual(topLeft.y, 34, accuracy: 0.01)

        let bottomRight = FloatingBallGeometry.clamp(
            CGPoint(x: 10_000, y: 10_000),
            in: size,
            diameter: diameter
        )
        XCTAssertEqual(bottomRight.x, 356, accuracy: 0.01)
        XCTAssertEqual(bottomRight.y, 810, accuracy: 0.01)
    }

    func testNearestEdgeSupportsAllFourSides() {
        XCTAssertEqual(FloatingBallGeometry.nearestEdge(CGPoint(x: 20, y: 400), in: size), .left)
        XCTAssertEqual(FloatingBallGeometry.nearestEdge(CGPoint(x: 370, y: 400), in: size), .right)
        XCTAssertEqual(FloatingBallGeometry.nearestEdge(CGPoint(x: 200, y: 70), in: size), .top)
        XCTAssertEqual(FloatingBallGeometry.nearestEdge(CGPoint(x: 200, y: 800), in: size), .bottom)
    }

    func testVisibleEdgePointSnapsToNearestSideEdge() {
        let left = FloatingBallGeometry.visibleEdgePoint(
            CGPoint(x: 80, y: 400),
            in: size,
            diameter: diameter
        )
        XCTAssertEqual(left.x, 34, accuracy: 0.01)

        let right = FloatingBallGeometry.visibleEdgePoint(
            CGPoint(x: 320, y: 400),
            in: size,
            diameter: diameter
        )
        XCTAssertEqual(right.x, 356, accuracy: 0.01)
    }

    func testVisibleEdgePointSnapsToTopAndBottomUsingScreenEdges() {
        let top = FloatingBallGeometry.visibleEdgePoint(
            CGPoint(x: 200, y: 70),
            in: size,
            diameter: diameter
        )
        XCTAssertEqual(top.y, 34, accuracy: 0.01, "顶部吸附应贴近屏幕边缘，而不是系统安全区下沿")
        XCTAssertEqual(top.x, 200, accuracy: 0.01)

        let bottom = FloatingBallGeometry.visibleEdgePoint(
            CGPoint(x: 200, y: 800),
            in: size,
            diameter: diameter
        )
        XCTAssertEqual(bottom.y, 810, accuracy: 0.01, "底部吸附应贴近屏幕边缘")
        XCTAssertEqual(bottom.x, 200, accuracy: 0.01)
    }

    func testIdleEdgePointStaysFullyVisibleOnSideEdges() {
        let left = FloatingBallGeometry.idleEdgePoint(
            CGPoint(x: 80, y: 400),
            in: size,
            diameter: diameter
        )
        XCTAssertEqual(left.x, 34, accuracy: 0.01)

        let right = FloatingBallGeometry.idleEdgePoint(
            CGPoint(x: 320, y: 400),
            in: size,
            diameter: diameter
        )
        XCTAssertEqual(right.x, 356, accuracy: 0.01)
    }

    func testIdleEdgePointStaysFullyVisible() {
        let top = FloatingBallGeometry.idleEdgePoint(
            CGPoint(x: 200, y: 70),
            in: size,
            diameter: diameter
        )
        XCTAssertEqual(top.y, 34, accuracy: 0.01)

        let bottom = FloatingBallGeometry.idleEdgePoint(
            CGPoint(x: 200, y: 800),
            in: size,
            diameter: diameter
        )
        XCTAssertEqual(bottom.y, 810, accuracy: 0.01)
    }

    func testNormalizationRoundTrip() {
        let point = CGPoint(x: 200, y: 400)
        let normalized = FloatingBallGeometry.normalized(point, in: size)
        let restored = FloatingBallGeometry.point(fromNormalized: normalized, in: size)
        XCTAssertEqual(restored.x, point.x, accuracy: 0.01)
        XCTAssertEqual(restored.y, point.y, accuracy: 0.01)
    }

    func testNormalizationClampsOutOfBounds() {
        let normalized = FloatingBallGeometry.normalized(
            CGPoint(x: -50, y: 2_000),
            in: size
        )
        XCTAssertEqual(normalized.x, 0, accuracy: 0.001)
        XCTAssertEqual(normalized.y, 1, accuracy: 0.001)
    }

    func testTinyContainerDoesNotProduceInvertedBounds() {
        let point = FloatingBallGeometry.clamp(
            CGPoint(x: 10, y: 10),
            in: CGSize(width: 20, height: 20),
            diameter: diameter
        )
        XCTAssertGreaterThanOrEqual(point.x, 34)
        XCTAssertGreaterThanOrEqual(point.y, 34)
    }
}
