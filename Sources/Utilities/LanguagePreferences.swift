import Foundation

extension SupportedLanguages {
    /// Removes unknown and duplicate values while preserving the user's order.
    static func normalizedTargetCodes(_ storedCodes: [String]) -> [String] {
        var seen: Set<String> = []
        return storedCodes.filter { codeSet.contains($0) && seen.insert($0).inserted }
    }

    /// An empty or invalid persisted list falls back to the pre-existing target list.
    static func effectiveTargetCodes(_ storedCodes: [String]) -> [String] {
        let normalized = normalizedTargetCodes(storedCodes)
        return normalized.isEmpty ? defaultTargetCodes : normalized
    }

    /// Keeps a persisted target usable after its language is removed from favorites.
    static func resolvedTarget(_ target: String, favoriteCodes: [String]) -> String {
        let normalized = normalizedTargetCodes(favoriteCodes)
        if normalized.isEmpty {
            return defaultTargetCodes.contains(target) ? target : "zh-Hans"
        }
        return normalized.contains(target) ? target : normalized[0]
    }

    /// Keeps a valid swapped source visible without silently adding it to favorites.
    static func targetPickerCodes(_ favoriteCodes: [String], selectedTarget: String) -> [String] {
        var available = effectiveTargetCodes(favoriteCodes)
        if codeSet.contains(selectedTarget), !available.contains(selectedTarget) {
            available.append(selectedTarget)
        }
        return available
    }

    /// Auto-flips to the first favorite outside the detected language family.
    /// With the default list this preserves the existing English/Chinese behavior.
    static func resolvedTarget(
        _ target: String,
        detectedLanguage: String?,
        favoriteCodes: [String]
    ) -> String {
        let available = effectiveTargetCodes(favoriteCodes)
        let preferred = resolvedTarget(target, favoriteCodes: favoriteCodes)
        guard let detectedLanguage,
              sameLanguage(detectedLanguage, preferred)
        else { return preferred }

        return available.first { !sameLanguage($0, detectedLanguage) } ?? preferred
    }

    private static func sameLanguage(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.hasPrefix("zh"), rhs.hasPrefix("zh") { return true }
        return lhs == rhs
    }
}
