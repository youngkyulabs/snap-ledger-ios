import Testing
@testable import SnapLedger

@Suite
struct IntentTextInputTests {
    @Test(arguments: ["", "  \n ", "오늘 저녁 7시에 만나요"])
    func textWithoutPaymentSignalIsNotQueued(text: String) {
        #expect(IntentTextInput.payload(from: text) == nil)
    }

    @Test func paymentTextIsTrimmed() {
        let approval = "[Web발신]\n현대카드 승인\n홍*동\n12,300원 일시불\n11/23 12:41 스타벅스"
        #expect(IntentTextInput.payload(from: "\n  \(approval)  \n") == approval)
    }

    @Test func longTextKeepsItsFirstTwoThousandCharacters() {
        let head = "12,300원 일시불 "
        let payload = IntentTextInput.payload(from: head + String(repeating: "가", count: 3_000))
        #expect(payload?.count == 2_000)
        #expect(payload?.hasPrefix(head) == true)
    }

    @Test func signalPastTheCapDoesNotCount() {
        // Only the clipped text reaches the inbox, so the gate judges that text.
        let text = String(repeating: "가", count: 2_000) + " 12,300원 일시불"
        #expect(IntentTextInput.payload(from: text) == nil)
    }
}
