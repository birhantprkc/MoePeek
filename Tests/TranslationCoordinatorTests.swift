import Defaults
import SwiftUI
import Testing
@testable import MoePeek

@Suite(.serialized)
@MainActor
struct TranslationCoordinatorTests {
    @Test func keepsOnDemandProviderIdleUntilRequestedAndResetsForNewText() async {
        let saved = saveProviderDefaults()
        defer { restoreProviderDefaults(saved) }

        Defaults[.enabledProviders] = ["automatic", "manual"]
        Defaults[.onDemandProviderIDs] = ["manual"]
        Defaults[.providerOrder] = ["automatic", "manual"]

        let recorder = ProviderCallRecorder()
        let automatic = RecordingProvider(id: "automatic", recorder: recorder)
        let manual = RecordingProvider(id: "manual", recorder: recorder)
        let coordinator = TranslationCoordinator(
            permissionManager: PermissionManager(),
            registry: TranslationProviderRegistry(providers: [automatic, manual])
        )

        coordinator.translate("first")

        #expect(coordinator.activeSlots.map(\.id) == ["automatic", "manual"])
        #expect(coordinator.providerStates["manual"] == .awaitingUser)
        #expect(!coordinator.copyResult(atDisplayIndex: 1))
        #expect(await eventually { isCompleted(coordinator.providerStates["automatic"]) })
        #expect(await recorder.count(for: "automatic") == 1)
        #expect(await recorder.count(for: "manual") == 0)
        #expect(coordinator.allFinished)

        coordinator.translateProvider(manual)

        #expect(!coordinator.allFinished)
        #expect(await eventually { isCompleted(coordinator.providerStates["manual"]) })
        #expect(await recorder.count(for: "manual") == 1)
        #expect(coordinator.allFinished)

        coordinator.translate("second")

        #expect(coordinator.providerStates["manual"] == .awaitingUser)
        #expect(await eventually { isCompleted(coordinator.providerStates["automatic"]) })
        #expect(await recorder.count(for: "automatic") == 2)
        #expect(await recorder.count(for: "manual") == 1)
    }

    @Test func appliesProviderSettingToEveryModelSlot() async {
        let saved = saveProviderDefaults()
        defer { restoreProviderDefaults(saved) }

        Defaults[.enabledProviders] = ["multi"]
        Defaults[.onDemandProviderIDs] = ["multi"]
        Defaults[.providerOrder] = ["multi"]

        let recorder = ProviderCallRecorder()
        let provider = RecordingProvider(
            id: "multi",
            models: ["model-a", "model-b"],
            recorder: recorder
        )
        let coordinator = TranslationCoordinator(
            permissionManager: PermissionManager(),
            registry: TranslationProviderRegistry(providers: [provider])
        )

        coordinator.translate("hello")

        #expect(coordinator.activeSlots.map(\.id) == ["multi:model-a", "multi:model-b"])
        #expect(coordinator.providerStates.values.allSatisfy { $0 == .awaitingUser })
        #expect(await recorder.allSlots().isEmpty)
        #expect(coordinator.allFinished)

        coordinator.translateProvider(coordinator.activeSlots[1])

        #expect(await eventually { isCompleted(coordinator.providerStates["multi:model-b"]) })
        #expect(await recorder.allSlots() == ["multi:model-b"])
        #expect(coordinator.providerStates["multi:model-a"] == .awaitingUser)
        #expect(coordinator.allFinished)
    }

    @Test func cancelledRequestCannotOverwriteNewOnDemandState() async {
        let saved = saveProviderDefaults()
        defer { restoreProviderDefaults(saved) }

        Defaults[.enabledProviders] = ["provider"]
        Defaults[.onDemandProviderIDs] = []
        Defaults[.providerOrder] = ["provider"]

        let recorder = ProviderCallRecorder()
        let provider = RecordingProvider(id: "provider", recorder: recorder)
        let coordinator = TranslationCoordinator(
            permissionManager: PermissionManager(),
            registry: TranslationProviderRegistry(providers: [provider])
        )

        coordinator.translate("first")
        Defaults[.onDemandProviderIDs] = ["provider"]
        coordinator.translate("second")
        await Task.yield()

        #expect(coordinator.providerStates["provider"] == .awaitingUser)
        #expect(await recorder.count(for: "provider") == 0)
        #expect(coordinator.allFinished)
    }

    @Test func retriesOnlyAnErroredProvider() async {
        let saved = saveProviderDefaults()
        defer { restoreProviderDefaults(saved) }

        Defaults[.enabledProviders] = ["flaky"]
        Defaults[.onDemandProviderIDs] = []
        Defaults[.providerOrder] = ["flaky"]

        let recorder = ProviderCallRecorder()
        let provider = RecordingProvider(id: "flaky", recorder: recorder, failsFirstAttempt: true)
        let coordinator = TranslationCoordinator(
            permissionManager: PermissionManager(),
            registry: TranslationProviderRegistry(providers: [provider])
        )

        coordinator.translate("hello")

        #expect(await eventually { isError(coordinator.providerStates["flaky"]) })
        #expect(coordinator.allFinished)

        coordinator.retryProvider(provider)

        #expect(await eventually { isCompleted(coordinator.providerStates["flaky"]) })
        #expect(await recorder.count(for: "flaky") == 2)
        #expect(coordinator.allFinished)
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func isCompleted(_ state: TranslationCoordinator.ProviderState?) -> Bool {
        if case .some(.completed) = state { return true }
        return false
    }

    private func isError(_ state: TranslationCoordinator.ProviderState?) -> Bool {
        if case .some(.error) = state { return true }
        return false
    }

    private func saveProviderDefaults() -> ProviderDefaultsSnapshot {
        ProviderDefaultsSnapshot(
            enabled: Defaults[.enabledProviders],
            onDemand: Defaults[.onDemandProviderIDs],
            order: Defaults[.providerOrder]
        )
    }

    private func restoreProviderDefaults(_ snapshot: ProviderDefaultsSnapshot) {
        Defaults[.enabledProviders] = snapshot.enabled
        Defaults[.onDemandProviderIDs] = snapshot.onDemand
        Defaults[.providerOrder] = snapshot.order
    }
}

private struct ProviderDefaultsSnapshot {
    let enabled: Set<String>
    let onDemand: Set<String>
    let order: [String]
}

private actor ProviderCallRecorder {
    private var slots: [String] = []

    func record(_ slot: String) -> Int {
        slots.append(slot)
        return slots.count { $0 == slot }
    }

    func count(for slot: String) -> Int {
        slots.count { $0 == slot }
    }

    func allSlots() -> [String] {
        slots
    }
}

private struct RecordingProvider: TranslationProvider {
    let id: String
    var models: [String] = []
    let recorder: ProviderCallRecorder
    var failsFirstAttempt = false

    var displayName: String { id }
    let iconSystemName = "character.bubble"
    let supportsStreaming = false
    let isAvailable = true
    var activeModels: [String] { models }
    @MainActor var isConfigured: Bool { true }

    func translateStream(
        _ text: String,
        from sourceLang: String?,
        to targetLang: String
    ) -> AsyncThrowingStream<String, Error> {
        stream(text: text, slot: id)
    }

    func translateStream(
        _ text: String,
        from sourceLang: String?,
        to targetLang: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        stream(text: text, slot: "\(id):\(model)")
    }

    @MainActor func makeSettingsView() -> AnyView {
        AnyView(EmptyView())
    }

    private func stream(text: String, slot: String) -> AsyncThrowingStream<String, Error> {
        singleResultStream {
            let attempt = await recorder.record(slot)
            if failsFirstAttempt, attempt == 1 {
                throw RecordingProviderError.failed
            }
            return "\(slot): \(text)"
        }
    }
}

private enum RecordingProviderError: Error {
    case failed
}
