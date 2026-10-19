import Foundation

extension FoundationModelsExtractionService {
    /// Known card issuer prefixes for filtering merchant field.
    static let cardIssuerPrefixes: [String] = [
        "현대카드", "신한카드", "삼성카드", "BC카드", "비씨카드",
        "롯데카드", "국민카드", "KB카드", "KB국민카드",
        "하나카드", "농협카드", "NH농협카드", "우리카드",
        "씨티카드", "광주카드", "전북카드", "수협카드",
    ]

    /// Short issuer and card-app titles a notification shows above the payment. Matched exactly, since a prefix
    /// match would also catch merchants such as "삼성서울병원".
    static let cardIssuerShortNames: Set<String> = [
        "신한", "삼성", "현대", "롯데", "LOTTE", "KB", "국민", "KB국민", "하나", "우리", "농협", "NH", "BC", "씨티",
        "신한 SOL페이", "신한SOL페이", "SOL페이", "KB PAY", "KB페이",
    ]

    static func isCardIssuerName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return cardIssuerPrefixes.contains { trimmed.hasPrefix($0) }
            || cardIssuerShortNames.contains(trimmed.uppercased())
    }
}
