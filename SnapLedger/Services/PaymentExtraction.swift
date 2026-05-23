import Foundation
import FoundationModels

@Generable
struct PaymentExtraction: Equatable, Sendable {
    @Guide(description: "이미지에서 추출된 거래 목록. 카드 알림 N행이면 N개, 영수증 한 장이면 1개.")
    var transactions: [PaymentTransaction]
}

@Generable
struct PaymentTransaction: Equatable, Sendable {
    @Guide(description: "결제 일자, YYYY-MM-DD 형식. 알림에 연도가 없으면 instructions에 제공된 오늘 날짜의 연도를 사용. 모르면 빈 문자열.")
    var date: String

    @Guide(description: "결제 금액(원), 정수. '일시불', '할부', '승인' 직전에 등장하는 금액 한 건만 선택. '누적', '잔액', '한도', '포인트', '적립', '월 사용액' 등의 보조 금액은 절대 선택하지 않음. 모르면 0.")
    var amount: Int

    @Guide(description: "가맹점 이름만. '현대카드', '신한카드' 같은 카드사명이나 '승인', '일시불' 등 결제 종류 단어는 포함하지 않음.")
    var merchant: String

    @Guide(description: "추정 카테고리. instructions에 주어진 카테고리 목록 안에서만 정확히 한 단어로 선택. 어느 것도 맞지 않거나 모르면 빈 문자열.")
    var category: String

    @Guide(description: "이 거래가 영수증이면 품목별 분해. 카드 알림이면 빈 배열.")
    var items: [PaymentLineItem]
}

@Generable
struct PaymentLineItem: Equatable, Sendable {
    @Guide(description: "품목 이름")
    var name: String

    @Guide(description: "품목 금액(원)")
    var amount: Int
}
