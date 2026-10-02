import XCTest
@testable import App

final class TimerActivityAttributesTests: XCTestCase {
    func testAttributesRoundTripRunIdentityAndGoal() throws {
        let attributes = TimerActivityAttributes(runID: UUID(), goalSeconds: 2_700, restSeconds: 300, loops: true)

        let restored = try JSONDecoder().decode(TimerActivityAttributes.self, from: JSONEncoder().encode(attributes))

        XCTAssertEqual(restored, attributes)
    }

    func testAllContentStatesRoundTripIncludingFractionalTimeAndOptionalDeadline() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000.25)
        let states = [
            TimerActivityAttributes.ContentState(deadline: date, remainingSeconds: 123.75, isPaused: false, isComplete: false),
            TimerActivityAttributes.ContentState(deadline: nil, remainingSeconds: 123.75, isPaused: true, isComplete: false),
            TimerActivityAttributes.ContentState(deadline: nil, remainingSeconds: 0, isPaused: false, isComplete: true),
        ]

        let restored = try JSONDecoder().decode([TimerActivityAttributes.ContentState].self, from: JSONEncoder().encode(states))

        XCTAssertEqual(restored, states)
        XCTAssertEqual(Set(restored).count, 3)
    }
}
