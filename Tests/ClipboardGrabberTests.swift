import Foundation
import Testing
@testable import MoePeek

@MainActor
@Suite struct ClipboardGrabberTests {
    @Test func cancelledWaitStillObservesDelayedPasteboardChange() async {
        var changeCount = 0
        var waitCount = 0
        var observedCancellation = false

        let task = Task { @MainActor in
            await ClipboardGrabber.waitForPasteboardChange(
                previousCount: 0,
                deadline: Date().addingTimeInterval(1),
                changeCount: { changeCount },
                wait: {
                    observedCancellation = Task.isCancelled
                    waitCount += 1
                    if waitCount == 2 {
                        changeCount = 1
                    }
                }
            )
        }
        task.cancel()

        #expect(await task.value)
        #expect(observedCancellation)
        #expect(waitCount == 2)
    }
}
