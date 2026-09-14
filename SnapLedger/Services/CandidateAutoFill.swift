import Foundation

/// Auto-fills empty fields using OCR candidate values.
enum CandidateAutoFill {
    /// Fills empty merchant with the first candidate if available.
    static func merchant(current: String, candidates: [String]) -> String {
        current.isEmpty ? (candidates.first ?? current) : current
    }

    /// Fills empty amount only when exactly one candidate exists.
    static func amount(current: Int, candidates: [Int]) -> Int {
        current == 0 && candidates.count == 1 ? candidates[0] : current
    }

    /// Resolves category preferring learned over extracted, restricted to presets.
    static func category(learned: String?, extracted: String?, presets: [String]) -> String? {
        // Validate whether trimmed label exists in preset list.
        if let learned {
            let trimmed = learned.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !CategoryValidation.isOffPreset(trimmed, presets: presets) {
                return trimmed
            }
        }
        return extracted
    }
}
