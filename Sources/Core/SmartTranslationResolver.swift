import AppKit
import Defaults

enum SmartTranslationResult: Sendable, Equatable {
    case selection(RichSourceDocument)
    case clipboard(RichSourceDocument)
    case manualInput
    case cancelled
}

/// Resolves the smart shortcut without ever using clipboard contents written by selection capture
/// as its fallback. The clipboard payload is copied into memory before any simulated ⌘C occurs.
@MainActor
enum SmartTranslationResolver {
    static func resolve(
        captureClipboardSnapshot: @MainActor () -> RichTextImporter.Payload? = makeClipboardSnapshot,
        grabSelection: @MainActor () async -> RichSourceDocument? = TextSelectionManager.grabSelectedDocument
    ) async -> SmartTranslationResult {
        let clipboardSnapshot = captureClipboardSnapshot()
        guard !Task.isCancelled else { return .cancelled }

        if let selection = await grabSelection(),
           !selection.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard !Task.isCancelled else { return .cancelled }
            return .selection(selection)
        }

        guard !Task.isCancelled else { return .cancelled }
        if let clipboardSnapshot,
           let document = await RichTextImporter.document(from: clipboardSnapshot) {
            guard !Task.isCancelled else { return .cancelled }
            return .clipboard(document)
        }

        return .manualInput
    }

    private static func makeClipboardSnapshot() -> RichTextImporter.Payload? {
        let pasteboard = NSPasteboard.general
        if Defaults[.captureRichText] {
            return RichTextImporter.payload(from: pasteboard)
        }

        guard let plain = pasteboard.string(forType: .string),
              !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return RichTextImporter.Payload(rtfd: nil, rtf: nil, html: nil, plain: plain)
    }
}
