import SwiftUI
import XCTest
@testable import Ariuno

final class FloatingBallGeometryTests: XCTestCase {
    private let size = CGSize(width: 390, height: 844)
    private let safeArea = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

    func testClampKeepsBallInsideSafeArea() {
        let topLeft = FloatingBallGeometry.clamp(
            CGPoint(x: -100, y: -100),
            in: size,
            safeArea: safeArea,
            diameter: 56
        )
        XCTAssertEqual(topLeft.x, 34, accuracy: 0.01)
        XCTAssertEqual(topLeft.y, 93, accuracy: 0.01)

        let bottomRight = FloatingBallGeometry.clamp(
            CGPoint(x: 10_000, y: 10_000),
            in: size,
            safeArea: safeArea,
            diameter: 56
        )
        XCTAssertEqual(bottomRight.x, 356, accuracy: 0.01)
        XCTAssertEqual(bottomRight.y, 776, accuracy: 0.01)
    }

    func testVisibleEdgePointSnapsToNearestEdge() {
        let left = FloatingBallGeometry.visibleEdgePoint(
            CGPoint(x: 80, y: 400),
            in: size,
            safeArea: safeArea,
            diameter: 56
        )
        XCTAssertEqual(left.x, 34, accuracy: 0.01)

        let right = FloatingBallGeometry.visibleEdgePoint(
            CGPoint(x: 320, y: 400),
            in: size,
            safeArea: safeArea,
            diameter: 56
        )
        XCTAssertEqual(right.x, 356, accuracy: 0.01)
    }

    func testNearestEdgeSupportsTopAndBottom() {
        XCTAssertEqual(
            FloatingBallGeometry.nearestEdge(CGPoint(x: 200, y: 70), in: size, safeArea: safeArea),
            .top
        )
        XCTAssertEqual(
            FloatingBallGeometry.nearestEdge(CGPoint(x: 200, y: 800), in: size, safeArea: safeArea),
            .bottom
        )
        XCTAssertEqual(
            FloatingBallGeometry.nearestEdge(CGPoint(x: 20, y: 400), in: size, safeArea: safeArea),
            .left
        )
        XCTAssertEqual(
            FloatingBallGeometry.nearestEdge(CGPoint(x: 370, y: 400), in: size, safeArea: safeArea),
            .right
        )
    }

    func testVisibleEdgePointSnapsTopAndBottom() {
        let top = FloatingBallGeometry.visibleEdgePoint(
            CGPoint(x: 200, y: 70),
            in: size,
            safeArea: safeArea,
            diameter: 56
        )
        XCTAssertEqual(top.y, 93, accuracy: 0.01)
        XCTAssertEqual(top.x, 200, accuracy: 0.01)

        let bottom = FloatingBallGeometry.visibleEdgePoint(
            CGPoint(x: 200, y: 800),
            in: size,
            safeArea: safeArea,
            diameter: 56
        )
        XCTAssertEqual(bottom.y, 776, accuracy: 0.01)
        XCTAssertEqual(bottom.x, 200, accuracy: 0.01)
    }

    func testIdleEdgePointTucksTopAndBottomHalfOutside() {
        let top = FloatingBallGeometry.idleEdgePoint(
            CGPoint(x: 200, y: 70),
            in: size,
            safeArea: safeArea,
            diameter: 56
        )
        XCTAssertEqual(top.y, safeArea.top, accuracy: 0.01)

        let bottom = FloatingBallGeometry.idleEdgePoint(
            CGPoint(x: 200, y: 800),
            in: size,
            safeArea: safeArea,
            diameter: 56
        )
        XCTAssertEqual(bottom.y, size.height - safeArea.bottom, accuracy: 0.01)
    }

    func testIdleEdgePointTucksHalfOutside() {
        let left = FloatingBallGeometry.idleEdgePoint(
            CGPoint(x: 80, y: 400),
            in: size,
            safeArea: safeArea,
            diameter: 56
        )
        XCTAssertEqual(left.x, safeArea.leading, accuracy: 0.01)

        let right = FloatingBallGeometry.idleEdgePoint(
            CGPoint(x: 320, y: 400),
            in: size,
            safeArea: safeArea,
            diameter: 56
        )
        XCTAssertEqual(right.x, size.width - safeArea.trailing, accuracy: 0.01)
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
            safeArea: EdgeInsets(),
            diameter: 56
        )
        XCTAssertGreaterThanOrEqual(point.x, 34)
        XCTAssertGreaterThanOrEqual(point.y, 34)
    }
}
