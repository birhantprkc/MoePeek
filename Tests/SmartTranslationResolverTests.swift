import Foundation
import Testing
@testable import MoePeek

@MainActor
@Suite struct SmartTranslationResolverTests {
    @Test func snapshotsClipboardBeforeGrabbingSelection() async {
        var events: [String] = []
        let selection = RichSourceDocument.plain("selected")

        let result = await SmartTranslationResolver.resolve(
            captureClipboardSnapshot: {
                events.append("snapshot")
                return .init(rtfd: nil, rtf: nil, html: nil, plain: "clipboard")
            },
            grabSelection: {
                events.append("selection")
                return selection
            }
        )

        #expect(events == ["snapshot", "selection"])
        #expect(result == .selection(selection))
    }

    @Test func fallsBackToInvocationTimeClipboardSnapshot() async {
        var clipboard = "before shortcut"

        let result = await SmartTranslationResolver.resolve(
            captureClipboardSnapshot: {
                .init(rtfd: nil, rtf: nil, html: nil, plain: clipboard)
            },
            grabSelection: {
                clipboard = "written by simulated copy"
                return nil
            }
        )

        #expect(result == .clipboard(.plain("before shortcut")))
    }

    @Test func entersManualInputWhenSelectionAndClipboardAreEmpty() async {
        let result = await SmartTranslationResolver.resolve(
            captureClipboardSnapshot: { nil },
            grabSelection: { nil }
        )

        #expect(result == .manualInput)
    }

    @Test func preservesRichSelectionAttachments() async {
        let attachment = SourceImageAttachment(id: "img-1", data: Data([1, 2, 3]))
        let selection = RichSourceDocument(
            markdown: "![img-1](moepeek-attachment:img-1)",
            attachments: ["img-1": attachment]
        )

        let result = await SmartTranslationResolver.resolve(
            captureClipboardSnapshot: {
                .init(rtfd: nil, rtf: nil, html: nil, plain: "clipboard")
            },
            grabSelection: { selection }
        )

        #expect(result == .selection(selection))
    }

    @Test func preservesRichClipboardSnapshotWhenSelectionIsEmpty() async {
        let html = Data("<p><b>Bold</b> clipboard</p>".utf8)

        let result = await SmartTranslationResolver.resolve(
            captureClipboardSnapshot: {
                .init(rtfd: nil, rtf: nil, html: html, plain: "Bold clipboard")
            },
            grabSelection: { nil }
        )

        #expect(result == .clipboard(.init(markdown: "**Bold** clipboard", attachments: [:])))
    }

    @Test func cancelledResolutionDoesNotApplyCapturedContent() async {
        let task = Task { @MainActor in
            await SmartTranslationResolver.resolve(
                captureClipboardSnapshot: {
                    .init(rtfd: nil, rtf: nil, html: nil, plain: "clipboard")
                },
                grabSelection: { .plain("selected") }
            )
        }
        task.cancel()

        #expect(await task.value == .cancelled)
    }
}
