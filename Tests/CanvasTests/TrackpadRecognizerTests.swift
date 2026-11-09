import XCTest
@testable import Canvas

final class TrackpadRecognizerTests: XCTestCase {
    private let three: Set<Int32> = [1, 2, 3]

    /// Feeds centroids (trackpad widths, y up) for one three-finger touch, then lifts; returns every phase.
    /// The frames are `interval` apart, so a ten-step path at the default is a quick stroke.
    private func touch(_ path: [CGPoint], interval: Double = 0.01, swipeUp: Bool = false) -> [TrackpadPan.Phase] {
        var r = TrackpadRecognizer()
        r.swipeUpSeesAll = swipeUp
        var phases: [TrackpadPan.Phase] = []
        for (i, p) in path.enumerated() {
            phases += r.update(device: 1, fingers: three, centroid: p, now: Double(i) * interval)
        }
        phases += r.update(device: 1, fingers: [], centroid: .zero, now: Double(path.count) * interval)
        return phases
    }

    private func line(from a: CGPoint, to b: CGPoint, steps: Int = 10) -> [CGPoint] {
        (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    private func travel(in phases: [TrackpadPan.Phase]) -> [CGVector] {
        phases.compactMap { if case .changed(let v) = $0 { v } else { nil } }
    }

    // MARK: Tap

    /// Three fingers landing together at `at`, still for `held` seconds, then lifting together.
    private func tap(held: Double, at start: Double = 0, drift: CGFloat = 0) -> [TrackpadPan.Phase] {
        var r = TrackpadRecognizer()
        var phases: [TrackpadPan.Phase] = []
        phases += r.update(device: 1, fingers: three, centroid: CGPoint(x: 0.5, y: 0.5), now: start)
        phases += r.update(device: 1, fingers: three, centroid: CGPoint(x: 0.5 + drift, y: 0.5), now: start + held / 2)
        phases += r.update(device: 1, fingers: three, centroid: CGPoint(x: 0.5 + drift, y: 0.5), now: start + held)
        phases += r.update(device: 1, fingers: [1, 2], centroid: CGPoint(x: 0.5 + drift, y: 0.5), now: start + held + 0.01)
        phases += r.update(device: 1, fingers: [], centroid: .zero, now: start + held + 0.02)
        return phases
    }

    func testAThreeFingerTapIsSeeAllOnce() {
        XCTAssertEqual(tap(held: 0.12), [.seeAll])
    }

    func testAHandRestingOnTheTrackpadIsNotATap() {
        XCTAssertEqual(tap(held: 0.6), [])
    }

    func testFingersThatShiftedAreNotATap() {
        XCTAssertFalse(tap(held: 0.12, drift: 0.05).contains(.seeAll))
    }

    func testAThirdFingerJoiningATwoFingerTouchLateIsNotATap() {
        var r = TrackpadRecognizer()
        var phases: [TrackpadPan.Phase] = []
        phases += r.update(device: 1, fingers: [1, 2], centroid: CGPoint(x: 0.5, y: 0.5), now: 0)
        phases += r.update(device: 1, fingers: three, centroid: CGPoint(x: 0.5, y: 0.5), now: 0.25)
        phases += r.update(device: 1, fingers: [], centroid: .zero, now: 0.3)
        XCTAssertEqual(phases, [])
    }

    func testAQuickStrokeUpPansLikeAnyDrag() {
        let phases = touch(line(from: CGPoint(x: 0.5, y: 0.2), to: CGPoint(x: 0.51, y: 0.5)))
        XCTAssertEqual(phases.first, .began)
        XCTAssertEqual(phases.last, .ended)
        XCTAssertFalse(phases.contains(.seeAll))
        // Even a mostly vertical stroke preserves the sideways movement.
        XCTAssertTrue(travel(in: phases).allSatisfy { $0.dx > 0 && $0.dy < 0 })
    }

    func testNearlyVerticalDragPreservesBothAxes() {
        let phases = touch(line(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.49, y: 0.2)))
        XCTAssertEqual(phases.first, .began)
        XCTAssertEqual(phases.last, .ended)
        XCTAssertFalse(phases.contains(.seeAll))
        // y down in the travel: the fingers went down the trackpad, so the content follows them down.
        XCTAssertTrue(travel(in: phases).allSatisfy { $0.dx < 0 && $0.dy > 0 })
    }

    func testAHandNudgingWithinTheSlopDoesNothing() {
        // Half a second on the trackpad, too long for a tap, moving less than the slop.
        let phases = touch(line(from: CGPoint(x: 0.5, y: 0.3), to: CGPoint(x: 0.5, y: 0.315)), interval: 0.05)
        XCTAssertEqual(phases, [])
    }

    // MARK: Swipe up (Settings › Trackpad)

    func testWithSwipeUpChosenAQuickStrokeUpIsSeeAllAndEndsThePan() {
        let phases = touch(line(from: CGPoint(x: 0.5, y: 0.2), to: CGPoint(x: 0.51, y: 0.5)), swipeUp: true)
        XCTAssertEqual(phases.first, .began)
        XCTAssertEqual(phases.last, .seeAll)
        XCTAssertEqual(phases.filter { $0 == .seeAll }.count, 1)
        XCTAssertFalse(phases.contains(.ended))
    }

    func testWithSwipeUpChosenASlowDragUpPans() {
        let phases = touch(line(from: CGPoint(x: 0.5, y: 0.1), to: CGPoint(x: 0.5, y: 0.8), steps: 30), interval: 0.1, swipeUp: true)
        XCTAssertEqual(phases.first, .began)
        XCTAssertEqual(phases.last, .ended)
        XCTAssertFalse(phases.contains(.seeAll))
    }

    func testWithSwipeUpChosenSpeedingUpLateIsStillADrag() {
        let slow = line(from: CGPoint(x: 0.5, y: 0.2), to: CGPoint(x: 0.5, y: 0.25), steps: 6)
        let fast = line(from: CGPoint(x: 0.5, y: 0.25), to: CGPoint(x: 0.5, y: 0.6), steps: 6)
        XCTAssertFalse(touch(slow + fast, interval: 0.1, swipeUp: true).contains(.seeAll))
    }

    func testWithSwipeUpChosenATapDoesNothing() {
        var r = TrackpadRecognizer()
        r.swipeUpSeesAll = true
        var phases: [TrackpadPan.Phase] = []
        phases += r.update(device: 1, fingers: three, centroid: CGPoint(x: 0.5, y: 0.5), now: 0)
        phases += r.update(device: 1, fingers: three, centroid: CGPoint(x: 0.5, y: 0.5), now: 0.1)
        phases += r.update(device: 1, fingers: [], centroid: .zero, now: 0.12)
        XCTAssertEqual(phases, [])
    }

    // MARK: Drag

    func testNearlyHorizontalDragPreservesBothAxes() {
        let phases = touch(line(from: CGPoint(x: 0.2, y: 0.5), to: CGPoint(x: 0.6, y: 0.55)))
        XCTAssertEqual(phases.first, .began)
        XCTAssertEqual(phases.last, .ended)
        let travel = travel(in: phases)
        XCTAssertFalse(travel.isEmpty)
        XCTAssertTrue(travel.allSatisfy { $0.dy < 0 && $0.dx > 0 })
        XCTAssertFalse(phases.contains(.seeAll))
    }

    func testDiagonalDragPansFreely() {
        let phases = touch(line(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertEqual(phases.first, .began)
        XCTAssertTrue(phases.contains { if case .changed(let v) = $0 { v.dx > 0 && v.dy < 0 } else { false } })
        XCTAssertFalse(phases.contains(.seeAll))
    }

    func testAPanCanTurnAfterStartingOnEitherAxis() {
        let paths: [[CGPoint]] = [
            [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.3, y: 0.2), CGPoint(x: 0.3, y: 0.4),
             CGPoint(x: 0.25, y: 0.35), CGPoint(x: 0.4, y: 0.25)],
            [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.4, y: 0.3),
             CGPoint(x: 0.35, y: 0.25), CGPoint(x: 0.25, y: 0.4)],
        ]
        for path in paths {
            let phases = touch(path)
            XCTAssertEqual(phases.first, .began)
            XCTAssertEqual(phases.last, .ended)
            XCTAssertFalse(phases.contains(.seeAll))
            let movements = travel(in: phases)
            XCTAssertEqual(movements.count, path.count - 1)
            for (movement, (a, b)) in zip(movements, zip(path, path.dropFirst())) {
                XCTAssertEqual(movement.dx, b.x - a.x, accuracy: 1e-9)
                XCTAssertEqual(movement.dy, a.y - b.y, accuracy: 1e-9)
            }
        }
    }

    func testOnlyThreeContactsStartAGesture() {
        for count in [1, 2, 4, 5] {
            var r = TrackpadRecognizer()
            let fingers = Set((1...count).map(Int32.init))
            let path = line(from: CGPoint(x: 0.2, y: 0.2), to: CGPoint(x: 0.6, y: 0.5))
            for (i, point) in path.enumerated() {
                XCTAssertEqual(r.update(device: 1, fingers: fingers, centroid: point, now: 10 + Double(i) * 0.01), [])
            }
            XCTAssertEqual(r.update(device: 1, fingers: [], centroid: .zero, now: 10.2), [])
            XCTAssertEqual(r.dropDockControlUntil, 0)
        }
    }

    func testLiftingOneFingerEndsAPanWithoutSeeingAll() {
        var r = TrackpadRecognizer()
        _ = r.update(device: 1, fingers: three, centroid: CGPoint(x: 0.2, y: 0.2), now: 10)
        _ = r.update(device: 1, fingers: three, centroid: CGPoint(x: 0.3, y: 0.3), now: 10.05)
        XCTAssertEqual(r.update(device: 1, fingers: [1, 2], centroid: CGPoint(x: 0.3, y: 0.3), now: 10.1), [.ended])
        XCTAssertGreaterThan(r.dropDockControlUntil, 10.1, "suppress the system swipe while the remaining fingers lift")
        XCTAssertEqual(r.update(device: 1, fingers: [], centroid: .zero, now: 10.2), [])
    }

    // MARK: Spread

    /// One three-finger touch with the centroid held still and the fingers' spread going from `a` to `b`.
    private func spreading(from a: CGFloat, to b: CGFloat, steps: Int = 10) -> [TrackpadPan.Phase] {
        var r = TrackpadRecognizer()
        var phases: [TrackpadPan.Phase] = []
        for i in 0...steps {
            let spread = a + (b - a) * CGFloat(i) / CGFloat(steps)
            phases += r.update(device: 1, fingers: three, centroid: CGPoint(x: 0.5, y: 0.3), spread: spread, now: 0)
        }
        phases += r.update(device: 1, fingers: [], centroid: .zero, now: 0)
        return phases
    }

    func testSpreadingTheFingersIsShowDesktopOnce() {
        XCTAssertEqual(spreading(from: 0.06, to: 0.3), [.spread])
    }

    func testPinchingThemTogetherDoesNothing() {
        XCTAssertEqual(spreading(from: 0.3, to: 0.06), [])
    }

    func testASmallSpreadIsNotOne() {
        XCTAssertEqual(spreading(from: 0.1, to: 0.13), [])
    }

    /// A thumb and two fingers on a 16 cm trackpad, measured as `TrackpadPan.frame` measures them:
    /// the thumb moves down and left, the fingers up and right, each point by `cm` centimetres.
    private func hand(parted cm: CGFloat) -> (centroid: CGPoint, spread: CGFloat) {
        let w: CGFloat = 16
        let d = cm / w
        let points = [CGPoint(x: 0.40 - d * 0.7, y: 0.30 - d * 0.7),
                      CGPoint(x: 0.50 + d * 0.3, y: 0.55 + d * 0.9),
                      CGPoint(x: 0.66 + d * 0.8, y: 0.54 + d * 0.6)]
        let n = CGFloat(points.count)
        let c = CGPoint(x: points.map(\.x).reduce(0, +) / n, y: points.map(\.y).reduce(0, +) / n)
        let s = points.map { hypot($0.x - c.x, $0.y - c.y) }.reduce(0, +) / n
        return (c, s)
    }

    func testARealHandSpreadingTwoCentimetresIsShowDesktop() {
        var r = TrackpadRecognizer()
        var phases: [TrackpadPan.Phase] = []
        for i in 0...10 {
            let h = hand(parted: 2 * CGFloat(i) / 10)
            phases += r.update(device: 1, fingers: three, centroid: h.centroid, spread: h.spread, now: Double(i) * 0.02)
        }
        phases += r.update(device: 1, fingers: [], centroid: .zero, now: 0.3)
        XCTAssertEqual(phases, [.spread])
    }

    func testAPanWithTheHandHeldTheSameStillPans() {
        var r = TrackpadRecognizer()
        var phases: [TrackpadPan.Phase] = []
        for p in line(from: CGPoint(x: 0.2, y: 0.5), to: CGPoint(x: 0.6, y: 0.5)) {
            phases += r.update(device: 1, fingers: three, centroid: p, spread: 0.1, now: 0)
        }
        XCTAssertEqual(phases.first, .began)
        XCTAssertFalse(phases.contains(.spread))
    }
}

extension TrackpadRecognizerTests {
    /// Sunlight off: the Mac's own three-finger swipes go through, so the Dock-control events aren't dropped.
    func testDockControlIsLeftAloneWhileInactive() {
        var r = TrackpadRecognizer()
        r.active = false
        _ = r.update(device: 1, fingers: three, centroid: CGPoint(x: 0.5, y: 0.5), now: 10)
        XCTAssertEqual(r.dropDockControlUntil, 0)
        var on = TrackpadRecognizer()
        _ = on.update(device: 1, fingers: three, centroid: CGPoint(x: 0.5, y: 0.5), now: 10)
        XCTAssertGreaterThan(on.dropDockControlUntil, 10)
    }
}
