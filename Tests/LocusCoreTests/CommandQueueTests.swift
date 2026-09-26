import Foundation
import XCTest
@testable import LocusCore

final class CommandQueueTests: XCTestCase {
    func testStopWaitsForRunningWriteAndDiscardsQueuedOldWrites() {
        let queue = LocationCommandQueue()
        let generation = queue.beginSession()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let completed = expectation(description: "clear barrier completed")
        var events: [String] = [] // accessed only on the command queue
        queue.perform(generation: generation, cancelled: false, operation: {
            events.append("write-start")
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
            events.append("write-end")
            return true
        }, completion: { _ in })
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        queue.perform(generation: generation, cancelled: false, operation: {
            XCTFail("A stopped route must not send a queued coordinate")
            return true
        }, completion: { sent in XCTAssertFalse(sent) })
        _ = queue.beginSession() // Stop invalidates synchronously
        queue.barrier(operation: { events.append("clear") }, completion: { _ in
            XCTAssertEqual(events, ["write-start", "write-end", "clear"])
            completed.fulfill()
        })
        release.signal()
        wait(for: [completed], timeout: 5)
        XCTAssertFalse(queue.isCurrent(generation), "A late UI completion must also be ignored")
    }

    func testOldTaskCannotSendEvenIfItEnqueuesAfterClear() {
        let queue = LocationCommandQueue()
        let old = queue.beginSession()
        let new = queue.beginSession()
        let completed = expectation(description: "new movement accepted")
        queue.barrier(operation: {}, completion: { _ in })
        queue.perform(generation: old, cancelled: false, operation: {
            XCTFail("Late old task resurrected simulation")
            return true
        }, completion: { value in XCTAssertFalse(value) })
        queue.perform(generation: new, cancelled: false, operation: { true }, completion: { value in
            XCTAssertTrue(value)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 5)
    }
}
