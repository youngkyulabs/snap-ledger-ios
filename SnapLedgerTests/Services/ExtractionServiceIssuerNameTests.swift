import Foundation
import Testing
@testable import SnapLedger

/// Verifies which merchant answers count as card issuer or pay-app titles rather than merchants.
@MainActor
struct ExtractionServiceIssuerNameTests {
    @Test func shortIssuerNamesAreIssuers() {
        for name in ["삼성", "LOTTE", "lotte", "신한 SOL페이", "KB Pay", "현대"] {
            #expect(FoundationModelsExtractionService.isCardIssuerName(name), "\(name)")
        }
    }

    @Test func merchantsStartingWithIssuerWordsAreNotIssuers() {
        for name in ["롯데마트", "삼성서울병원", "현대백화점 판교점", "신한은행 ATM 앞 편의점"] {
            #expect(!FoundationModelsExtractionService.isCardIssuerName(name), "\(name)")
        }
    }

    @Test func existingPrefixesStillMatch() {
        #expect(FoundationModelsExtractionService.isCardIssuerName("현대카드M"))
        #expect(FoundationModelsExtractionService.isCardIssuerName("KB국민카드"))
    }

    @Test func normalizeClearsShortIssuerMerchant() {
        let out = FoundationModelsExtractionService.normalize(
            PaymentExtraction(transactions: [
                PaymentTransaction(date: "2026-10-08", amount: 57800, merchant: "LOTTE", category: "", items: []),
            ]),
            ocrText: "롯데카드 승인 57,800원 일시불 10/08"
        )
        #expect(out.transactions.first?.merchant.isEmpty == true)
    }
}
