import Testing
@testable import MoePeek

@MainActor
@Suite struct SmartTranslationTaskCleanupTests {
    @Test func waitsForCancelledTaskCleanupBeforeReturning() async {
        var cleanupFinished = false
        let task = Task { @MainActor in
            while !Task.isCancelled {
                await Task.yield()
            }
            cleanupFinished = true
        }

        let didWait = await SmartTranslationTaskCleanup.cancelAndWait(task)

        #expect(didWait)
        #expect(cleanupFinished)
    }

    @Test func reportsWhenThereIsNoCleanupToWaitFor() async {
        #expect(await SmartTranslationTaskCleanup.cancelAndWait(nil) == false)
    }
}
