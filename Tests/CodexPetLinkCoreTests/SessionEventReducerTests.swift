import XCTest
@testable import CodexPetLinkCore

final class SessionEventReducerTests: XCTestCase {
    func testTaskLifecycle() {
        var reducer = SessionEventReducer()

        reducer.consume(line: #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}"#)
        XCTAssertEqual(reducer.state, .running)

        reducer.consume(line: #"{"type":"response_item","payload":{"type":"custom_tool_call","name":"request_user_input","call_id":"c1"}}"#)
        XCTAssertEqual(reducer.state, .needsInput)

        reducer.consume(line: #"{"type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"c1"}}"#)
        XCTAssertEqual(reducer.state, .running)

        reducer.consume(line: #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"t1"}}"#)
        XCTAssertEqual(reducer.state, .ready)
    }

    func testFailureAndMalformedLine() {
        var reducer = SessionEventReducer()

        reducer.consume(line: "not json")
        XCTAssertEqual(reducer.invalidLineCount, 1)
        XCTAssertEqual(reducer.state, .idle)

        reducer.consume(line: #"{"type":"event_msg","payload":{"type":"stream_error"}}"#)
        XCTAssertEqual(reducer.state, .blocked)
    }

    func testUnrelatedToolDoesNotRequestInput() {
        var reducer = SessionEventReducer()
        reducer.consume(line: #"{"type":"event_msg","payload":{"type":"task_started"}}"#)
        reducer.consume(line: #"{"type":"response_item","payload":{"type":"custom_tool_call","name":"exec_command","call_id":"c2"}}"#)

        XCTAssertEqual(reducer.state, .running)
    }

    func testFailedStatusBlocksEvenWithUnknownEventType() {
        var reducer = SessionEventReducer()
        reducer.consume(line: #"{"type":"event_msg","payload":{"type":"unknown","status":"failed"}}"#)

        XCTAssertEqual(reducer.state, .blocked)
    }
}
