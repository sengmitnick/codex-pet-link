import Foundation
import XCTest
@testable import CodexPetLinkCore

final class AppServerTitleClientTests: XCTestCase {
    func testRequestsThreadSummaryAndReturnsSanitizedName() throws {
        let transport = RecordingAppServerTransport(response: [
            "id": 1,
            "result": ["thread": ["id": "s1", "name": "  优化引导  "]],
        ])
        let client = AppServerTitleClient(transport: transport)

        let title = try client.title(threadID: "s1")

        XCTAssertEqual(title, "优化引导")
        XCTAssertEqual(transport.method, "thread/read")
        XCTAssertEqual(transport.params?["threadId"] as? String, "s1")
        XCTAssertEqual(transport.params?["includeTurns"] as? Bool, false)
    }

    func testReturnsNilWhenThreadHasNoName() throws {
        let transport = RecordingAppServerTransport(response: [
            "result": ["thread": ["id": "s1", "name": NSNull()]],
        ])

        XCTAssertNil(try AppServerTitleClient(transport: transport).title(threadID: "s1"))
    }

    func testRejectsResponseForAnotherThread() throws {
        let transport = RecordingAppServerTransport(response: [
            "result": ["thread": ["id": "other", "name": "不应显示"]],
        ])

        XCTAssertNil(try AppServerTitleClient(transport: transport).title(threadID: "s1"))
    }
}

private final class RecordingAppServerTransport: AppServerRequesting, @unchecked Sendable {
    let response: [String: Any]
    var method: String?
    var params: [String: Any]?

    init(response: [String: Any]) {
        self.response = response
    }

    func request(method: String, params: [String: Any], timeout: TimeInterval) throws -> [String: Any] {
        self.method = method
        self.params = params
        return response
    }
}
