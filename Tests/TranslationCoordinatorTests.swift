import SwiftUI
import Testing
@testable import MoePeek

@Suite(.serialized)
@MainActor
struct TranslationCoordinatorTests {
    @Test func keepsOnDemandProviderIdleUntilRequestedAndResetsForNewText() async {
        let preferences = ProviderTestPreferences(
            enabled: ["automatic", "manual"],
            onDemand: ["manual"],
            order: ["automatic", "manual"]
        )

        let recorder = ProviderCallRecorder()
        let automatic = RecordingProvider(id: "automatic", recorder: recorder)
        let manual = RecordingProvider(id: "manual", recorder: recorder)
        let coordinator = TranslationCoordinator(
            permissionManager: PermissionManager(),
            registry: preferences.registry(providers: [automatic, manual])
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
        let preferences = ProviderTestPreferences(
            enabled: ["multi"],
            onDemand: ["multi"],
            order: ["multi"]
        )

        let recorder = ProviderCallRecorder()
        let provider = RecordingProvider(
            id: "multi",
            models: ["model-a", "model-b"],
            recorder: recorder
        )
        let coordinator = TranslationCoordinator(
            permissionManager: PermissionManager(),
            registry: preferences.registry(providers: [provider])
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
        let preferences = ProviderTestPreferences(
            enabled: ["provider"],
            onDemand: [],
            order: ["provider"]
        )

        let recorder = ProviderCallRecorder()
        let provider = RecordingProvider(id: "provider", recorder: recorder)
        let coordinator = TranslationCoordinator(
            permissionManager: PermissionManager(),
            registry: preferences.registry(providers: [provider])
        )

        coordinator.translate("first")
        preferences.onDemand = ["provider"]
        coordinator.translate("second")
        await Task.yield()

        #expect(coordinator.providerStates["provider"] == .awaitingUser)
        #expect(await recorder.count(for: "provider") == 0)
        #expect(coordinator.allFinished)
    }

    @Test func retriesOnlyAnErroredProvider() async {
        let preferences = ProviderTestPreferences(
            enabled: ["flaky"],
            onDemand: [],
            order: ["flaky"]
        )

        let recorder = ProviderCallRecorder()
        let provider = RecordingProvider(id: "flaky", recorder: recorder, failsFirstAttempt: true)
        let coordinator = TranslationCoordinator(
            permissionManager: PermissionManager(),
            registry: preferences.registry(providers: [provider])
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
}

@MainActor
private final class ProviderTestPreferences {
    let enabled: Set<String>
    var onDemand: Set<String>
    let order: [String]

    init(enabled: Set<String>, onDemand: Set<String>, order: [String]) {
        self.enabled = enabled
        self.onDemand = onDemand
        self.order = order
    }

    func registry(providers: [any TranslationProvider]) -> TranslationProviderRegistry {
        TranslationProviderRegistry(
            providers: providers,
            enabledProviderIDs: { [self] in enabled },
            providerOrder: { [self] in order },
            onDemandProviderIDs: { [self] in onDemand }
        )
    }
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
