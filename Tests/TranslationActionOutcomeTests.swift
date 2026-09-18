import Foundation
import SwiftUI
import Testing
@testable import MoePeek

@MainActor
@Suite struct TranslationActionOutcomeTests {
    @Test func missingSelectionPreservesIdleWithoutShowingAnError() async {
        let coordinator = makeCoordinator(grabSelection: { nil })

        let outcome = await coordinator.translateSelection()

        #expect(outcome == .preserve)
        #expect(!outcome.shouldPresent)
        expectIdle(coordinator)
        #expect(coordinator.globalError == nil)
        #expect(coordinator.sourceText.isEmpty)
    }

    @Test func blankSelectionPreservesIdleWithoutShowingAnError() async {
        let coordinator = makeCoordinator(grabSelection: { .plain(" \n\t") })

        let outcome = await coordinator.translateSelection()

        #expect(outcome == .preserve)
        #expect(!outcome.shouldPresent)
        expectIdle(coordinator)
        #expect(coordinator.globalError == nil)
    }

    @Test func cancelledOCRPreservesIdleWithoutShowingAnError() async {
        let coordinator = makeCoordinator(captureOCR: { throw OCRError.captureCancelled })

        let outcome = await coordinator.ocrAndTranslate()

        #expect(outcome == .preserve)
        #expect(!outcome.shouldPresent)
        expectIdle(coordinator)
        #expect(coordinator.globalError == nil)
    }

    @Test func cancelledOCRPreservesExistingResultAndAttachments() async {
        let coordinator = makeCoordinator(captureOCR: { throw OCRError.captureCancelled })
        let attachment = SourceImageAttachment(id: "img-1", data: Data([1, 2, 3]))
        let document = RichSourceDocument(
            markdown: "existing source",
            attachments: [attachment.id: attachment]
        )

        coordinator.translate(document: document)
        for _ in 0 ..< 100 where !coordinator.hasAnyResult {
            await Task.yield()
        }

        #expect(coordinator.hasAnyResult)
        let sourceText = coordinator.sourceText
        let sourceAttachments = coordinator.sourceAttachments
        let providerStates = coordinator.providerStates

        let missingSelectionOutcome = await coordinator.translateSelection()

        #expect(missingSelectionOutcome == .preserve)
        #expect(!missingSelectionOutcome.shouldPresent)
        expectActive(coordinator)
        #expect(coordinator.sourceText == sourceText)
        #expect(coordinator.sourceAttachments == sourceAttachments)
        #expect(coordinator.providerStates == providerStates)
        #expect(coordinator.globalError == nil)

        let cancelledOCROutcome = await coordinator.ocrAndTranslate()

        #expect(cancelledOCROutcome == .preserve)
        #expect(!cancelledOCROutcome.shouldPresent)
        expectActive(coordinator)
        #expect(coordinator.sourceText == sourceText)
        #expect(coordinator.sourceAttachments == sourceAttachments)
        #expect(coordinator.providerStates == providerStates)
        #expect(coordinator.globalError == nil)
    }

    @Test func staleSelectionDoesNotRestoreOverNewInputSession() async {
        var finishGrab: CheckedContinuation<RichSourceDocument?, Never>?
        let coordinator = makeCoordinator(
            grabSelection: {
                await withCheckedContinuation { continuation in
                    finishGrab = continuation
                }
                return nil
            }
        )

        let staleTask = Task { @MainActor in
            await coordinator.translateSelection()
        }

        for _ in 0 ..< 100 where finishGrab == nil {
            await Task.yield()
        }
        guard let finishGrab else {
            Issue.record("Selection grab did not reach its continuation")
            staleTask.cancel()
            _ = await staleTask.value
            return
        }

        coordinator.prepareInputMode()
        coordinator.translate("new translation")
        for _ in 0 ..< 100 where !coordinator.hasAnyResult {
            await Task.yield()
        }
        #expect(coordinator.hasAnyResult)
        let newSourceText = coordinator.sourceText
        let newProviderStates = coordinator.providerStates

        finishGrab.resume(returning: nil)
        let outcome = await staleTask.value

        #expect(outcome == .preserve)
        expectActive(coordinator)
        #expect(coordinator.sourceText == newSourceText)
        #expect(coordinator.providerStates == newProviderStates)
    }

    @Test func staleOCRCancellationDoesNotRestoreOverNewInputSession() async {
        var finishOCR: CheckedContinuation<String, Error>?
        let coordinator = makeCoordinator(
            captureOCR: {
                try await withCheckedThrowingContinuation { continuation in
                    finishOCR = continuation
                }
                return "unreachable"
            }
        )

        let staleTask = Task { @MainActor in
            await coordinator.ocrAndTranslate()
        }

        for _ in 0 ..< 100 where finishOCR == nil {
            await Task.yield()
        }
        guard let finishOCR else {
            Issue.record("OCR capture did not reach its continuation")
            staleTask.cancel()
            _ = await staleTask.value
            return
        }

        coordinator.prepareInputMode()
        coordinator.translate("new translation")
        for _ in 0 ..< 100 where !coordinator.hasAnyResult {
            await Task.yield()
        }
        #expect(coordinator.hasAnyResult)
        let newSourceText = coordinator.sourceText
        let newProviderStates = coordinator.providerStates

        finishOCR.resume(throwing: OCRError.captureCancelled)
        let outcome = await staleTask.value

        #expect(outcome == .preserve)
        expectActive(coordinator)
        #expect(coordinator.sourceText == newSourceText)
        #expect(coordinator.providerStates == newProviderStates)
    }

    @Test func overlappingEmptyCapturesKeepIdleState() async {
        var continuations: [CheckedContinuation<RichSourceDocument?, Never>] = []
        let coordinator = makeCoordinator(grabSelection: {
            await withCheckedContinuation { continuations.append($0) }
        })
        let first = Task { await coordinator.translateSelection() }
        while continuations.count < 1 { await Task.yield() }
        let second = Task { await coordinator.translateSelection() }
        while continuations.count < 2 { await Task.yield() }

        expectIdle(coordinator)
        continuations[0].resume(returning: nil)
        continuations[1].resume(returning: nil)
        #expect(await first.value == .preserve)
        #expect(await second.value == .preserve)
        expectIdle(coordinator)
    }

    @Test func cancelledSmartCapturePreservesExistingInput() async {
        var finish: CheckedContinuation<SmartTranslationResult, Never>?
        let coordinator = makeCoordinator(resolveSmart: {
            await withCheckedContinuation { finish = $0 }
        })
        coordinator.prepareInputMode()
        let task = Task { await coordinator.translateSmart() }
        while finish == nil { await Task.yield() }

        expectActive(coordinator)
        task.cancel()
        finish?.resume(returning: .manualInput)
        #expect(await task.value == .cancelled)
        expectActive(coordinator)
    }

    @Test func staleSmartResultCannotReplaceNewInput() async {
        var finish: CheckedContinuation<SmartTranslationResult, Never>?
        let coordinator = makeCoordinator(resolveSmart: {
            await withCheckedContinuation { finish = $0 }
        })
        let task = Task { await coordinator.translateSmart() }
        while finish == nil { await Task.yield() }

        coordinator.prepareInputMode()
        finish?.resume(returning: .selection(.plain("obsolete selection")))
        #expect(await task.value == .cancelled)
        expectActive(coordinator)
        #expect(coordinator.sourceText.isEmpty)
        #expect(coordinator.providerStates.isEmpty)
    }

    @Test func permissionErrorsRemainPresentable() async {
        let selectionCoordinator = makeCoordinator(accessibilityGranted: false)
        let selectionOutcome = await selectionCoordinator.translateSelection()

        #expect(selectionOutcome.shouldPresent)
        expectActive(selectionCoordinator)
        #expect(selectionCoordinator.globalError != nil)

        let ocrCoordinator = makeCoordinator(screenRecordingGranted: false)
        let ocrOutcome = await ocrCoordinator.ocrAndTranslate()

        #expect(ocrOutcome.shouldPresent)
        expectActive(ocrCoordinator)
        #expect(ocrCoordinator.globalError != nil)
    }

    @Test func OCRReadAndRecognitionErrorsRemainPresentable() async {
        let readFailureCoordinator = makeCoordinator(captureOCR: { throw OCRError.captureReadFailed })
        let readFailureOutcome = await readFailureCoordinator.ocrAndTranslate()

        #expect(readFailureOutcome.shouldPresent)
        expectActive(readFailureCoordinator)
        #expect(readFailureCoordinator.globalError != nil)

        let recognitionFailureCoordinator = makeCoordinator(captureOCR: { throw OCRError.noTextRecognized })
        let recognitionFailureOutcome = await recognitionFailureCoordinator.ocrAndTranslate()

        #expect(recognitionFailureOutcome.shouldPresent)
        expectActive(recognitionFailureCoordinator)
        #expect(recognitionFailureCoordinator.globalError != nil)
    }

    private func makeCoordinator(
        accessibilityGranted: Bool = true,
        screenRecordingGranted: Bool = true,
        grabSelection: @escaping @MainActor () async -> RichSourceDocument? = { nil },
        captureOCR: @escaping @MainActor () async throws -> String = { throw OCRError.captureCancelled },
        resolveSmart: @escaping @MainActor () async -> SmartTranslationResult = { .cancelled }
    ) -> TranslationCoordinator {
        let provider = TestTranslationProvider()
        let registry = TranslationProviderRegistry(
            providers: [provider],
            enabledProviderIDs: { [provider.id] },
            providerOrder: { [] },
            onDemandProviderIDs: { [] }
        )
        let permissions = TestPermissionManager(
            accessibilityGranted: accessibilityGranted,
            screenRecordingGranted: screenRecordingGranted
        )

        return TranslationCoordinator(
            permissionManager: permissions,
            registry: registry,
            grabSelection: grabSelection,
            captureOCR: captureOCR,
            resolveSmart: resolveSmart
        )
    }

    private func expectIdle(_ coordinator: TranslationCoordinator) {
        guard case .idle = coordinator.phase else {
            Issue.record("Expected an idle coordinator phase")
            return
        }
    }

    private func expectActive(_ coordinator: TranslationCoordinator) {
        guard case .active = coordinator.phase else {
            Issue.record("Expected an active coordinator phase")
            return
        }
    }
}

@MainActor
private final class TestPermissionManager: PermissionChecking {
    let isAccessibilityGranted: Bool
    let isScreenRecordingGranted: Bool

    init(accessibilityGranted: Bool, screenRecordingGranted: Bool) {
        isAccessibilityGranted = accessibilityGranted
        isScreenRecordingGranted = screenRecordingGranted
    }
}

private struct TestTranslationProvider: TranslationProvider {
    let id = "openai"
    let displayName = "Test provider"
    let iconSystemName = "globe"
    let supportsStreaming = false
    let isAvailable = true

    @MainActor var isConfigured: Bool { true }

    func translateStream(
        _: String,
        from _: String?,
        to _: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("translated")
            continuation.finish()
        }
    }

    @MainActor func makeSettingsView() -> AnyView {
        AnyView(EmptyView())
    }
}
