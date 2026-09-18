@MainActor
enum SmartTranslationTaskCleanup {
    /// Cancels a smart request and waits for any in-flight clipboard restoration to finish.
    /// Returns whether a task existed, allowing clipboard observers to refresh stale baselines.
    static func cancelAndWait(_ task: Task<Void, Never>?) async -> Bool {
        guard let task else { return false }
        task.cancel()
        await task.value
        return true
    }
}
