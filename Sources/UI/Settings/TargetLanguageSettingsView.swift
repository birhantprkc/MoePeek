import SwiftUI

/// Manages the ordered shortlist used by target-language pickers.
struct TargetLanguageSettingsView: View {
    @Binding var targetLanguage: String
    @Binding var favoriteTargetLanguages: [String]

    private var selectedCodes: [String] {
        SupportedLanguages.normalizedTargetCodes(favoriteTargetLanguages)
    }

    private var availableCodes: [String] {
        SupportedLanguages.codes.filter { !selectedCodes.contains($0) }
    }

    var body: some View {
        DisclosureGroup("Favorite Target Languages") {
            VStack(spacing: 6) {
                ForEach(Array(selectedCodes.enumerated()), id: \.element) { index, code in
                    HStack(spacing: 8) {
                        Text(displayName(for: code))
                        Spacer()

                        Button {
                            move(code, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == selectedCodes.startIndex)
                        .help("Move Up")

                        Button {
                            move(code, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == selectedCodes.index(before: selectedCodes.endIndex))
                        .help("Move Down")

                        Button {
                            remove(code)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(selectedCodes.count == 1)
                        .help("Remove")
                    }
                }

                HStack {
                    Menu("Add Language") {
                        ForEach(availableCodes, id: \.self) { code in
                            Button(displayName(for: code)) {
                                favoriteTargetLanguages = selectedCodes + [code]
                            }
                        }
                    }
                    .disabled(availableCodes.isEmpty)

                    Spacer()
                }
            }
            .padding(.top, 6)

            Text("Choose and order the languages shown in target-language menus. Source detection still uses the full language catalog.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: reconcilePersistedValues)
    }

    private func displayName(for code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    private func move(_ code: String, by offset: Int) {
        var codes = selectedCodes
        guard let sourceIndex = codes.firstIndex(of: code) else { return }
        let destinationIndex = sourceIndex + offset
        guard codes.indices.contains(destinationIndex) else { return }
        codes.swapAt(sourceIndex, destinationIndex)
        favoriteTargetLanguages = codes
    }

    private func remove(_ code: String) {
        let remaining = selectedCodes.filter { $0 != code }
        guard !remaining.isEmpty else { return }
        favoriteTargetLanguages = remaining
        targetLanguage = SupportedLanguages.resolvedTarget(targetLanguage, favoriteCodes: remaining)
    }

    private func reconcilePersistedValues() {
        let normalized = SupportedLanguages.normalizedTargetCodes(favoriteTargetLanguages)
        favoriteTargetLanguages = normalized.isEmpty
            ? SupportedLanguages.defaultTargetCodes
            : normalized
        targetLanguage = SupportedLanguages.resolvedTarget(
            targetLanguage,
            favoriteCodes: favoriteTargetLanguages
        )
    }
}
