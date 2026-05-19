import Foundation
import FoundationModels

protocol ExtractionService: Sendable {
    var isAvailable: Bool { get }
    func extract(from text: String) async throws -> PaymentExtraction
}

struct FoundationModelsExtractionService: ExtractionService {
    let customGuide: String
    let categories: [String]

    init(customGuide: String = "", categories: [String] = AppSettings.defaultPresets) {
        self.customGuide = customGuide
        self.categories = categories
    }

    static var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: return true
        case .unavailable: return false
        }
    }

    var isAvailable: Bool { Self.isAvailable }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Category prompt parts

    private struct CategoryPromptParts {
        let line: String
        let example1: String
        let example2: String
    }

    private static func bestCategoryMatch(in categories: [String], keywords: [String]) -> String {
        for keyword in keywords {
            if let match = categories.first(where: { $0.contains(keyword) }) {
                return match
            }
        }
        return categories.first ?? ""
    }

    private static func categoryPromptParts(for categories: [String]) -> CategoryPromptParts {
        guard !categories.isEmpty else {
            return CategoryPromptParts(
                line: "- category: 사용 가능한 카테고리 목록이 비어 있어요. 항상 빈 문자열로 두세요.",
                example1: "", example2: ""
            )
        }
        let list = categories.map { "\"\($0)\"" }.joined(separator: ", ")
        let line = "- category: 다음 라벨 중 가장 잘 맞는 것 하나를 그대로 복사 (양옆 따옴표 제외): \(list). 라벨의 '0.', '1.' 접두 번호나 '・' 구분 기호도 라벨의 일부 — 잘라내지 말고 함께 복사. 맞는 라벨이 없거나 헷갈리면 빈 문자열. 첫 번째 라벨을 기본값으로 쓰지 마세요. 목록 밖 단어 금지."
        return CategoryPromptParts(
            line: line,
            example1: bestCategoryMatch(in: categories, keywords: ["쇼핑", "생활"]),
            example2: bestCategoryMatch(in: categories, keywords: ["카페", "식비"])
        )
    }

    // MARK: - Prompt text

    private static func coreRules(today: Date, categoryLine: String) -> String {
        """
        한국어 카드 결제 알림 또는 영수증의 OCR 텍스트에서 거래 목록(transactions)을 추출하세요.

        **중요**: 응답은 입력 OCR 텍스트에서만 추출. 아래 예시는 형식 설명용 가짜 데이터이므로 예시의 이름·금액·품목을 응답에 절대 복사하지 마세요.

        타입 판단:
        A) 영수증: 합계/총금액/결제금액 같은 최종 합산 라인 + 품목 단가가 보임.
           → transaction 정확히 1개, 품목은 items 배열로만. 합산 라인이 여러 라벨로 반복돼도 한 번만 — 절대 더하지 마세요.
        B) 결제 알림: "<금액>원 일시불/할부/승인/일반승인" 라인이 1개 이상.
           → 알림 행 하나당 transaction 1개, items는 항상 []. 카드사명 헤더(현대카드·신한카드 등)는 별도 transaction 아님.

        공통: '누적·한도·잔액·월 사용액·부가세·과세물품가액·포인트·적립·캐시백·마일리지·사용가능' 라인의 숫자는 amount로 절대 사용 금지. 광고 배너 무시. 거래 못 찾으면 transactions=[].

        각 transaction 필드:
        - date: YYYY-MM-DD. 입력이 'YYYY-MM-DD', 'YYYY/MM/DD', 'YYYY.MM.DD', 'M/D HH:mm' 등 어떤 형식이든 정규화. 연도 누락이면 오늘(\(dateFormatter.string(from: today)))의 연도.
        - amount: KRW 정수, 결제 한 건. 영수증은 합계/총금액/결제금액 라인 숫자, 알림은 "<금액>원" 패턴. 입력에 결제 금액이 보이면 amount는 0 금지.
        - merchant: 가맹점 상호만. 카드사명·결제처리사명·캐셔/서명 이름·대괄호 결제수단 표기는 merchant 아님. 매장 상호가 전혀 없으면 빈 문자열.
        \(categoryLine)
        - items: 영수증의 품목별 분해만. 알림은 빈 배열.
        """
    }

    private static func examplesBlock(
        example1Category: String,
        example2Category: String
    ) -> String {
        """
        === 아래 예시는 형식 설명용 가짜 데이터. 응답에 예시 데이터를 복사하지 말고 반드시 입력에서만 추출하세요. ===

        예시 1 (알림 리스트, 여러 행 → N개):
        입력: "현대카드  3,300원 일시불, 5/17  Apple  누적523,748원  /  25,020원 일시불, 5/17  쿠팡"
        출력: transactions=[
          {date="2026-05-17", amount=3300, merchant="Apple", category="\(example1Category)", items=[]},
          {date="2026-05-17", amount=25020, merchant="쿠팡", category="\(example1Category)", items=[]}
        ]

        예시 2 (영수증 한 장 → transaction 1개, 품목은 items로):
        입력: "스타벅스  2026-05-17  아메리카노 4,500  카페라떼 5,500  합계 10,000  부가세 909"
        출력: transactions=[
          {date="2026-05-17", amount=10000, merchant="스타벅스", category="\(example2Category)",
            items=[{name="아메리카노", amount=4500}, {name="카페라떼", amount=5500}]}
        ]

        불확실하면 빈 문자열 또는 0.
        """
    }

    static func instructions(today: Date, customGuide: String, categories: [String]) -> String {
        let parts = categoryPromptParts(for: categories)
        let core = coreRules(today: today, categoryLine: parts.line)
        let examples = examplesBlock(
            example1Category: parts.example1,
            example2Category: parts.example2
        )
        let base = core + "\n\n" + examples
        let trimmedGuide = customGuide.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGuide.isEmpty else { return base }
        return base + """


        사용자 가이드 (위 규칙보다 우선 적용):
        \(trimmedGuide)
        """
    }

    // MARK: - Post-processing

    /// Prefix-matched so brand variants (현대카드Z, 현대카드M, 신한카드 The Mileage 등)도 잡힙니다.
    static let cardIssuerPrefixes: [String] = [
        "현대카드", "신한카드", "삼성카드", "BC카드", "비씨카드",
        "롯데카드", "국민카드", "KB카드", "KB국민카드",
        "하나카드", "농협카드", "NH농협카드", "우리카드",
        "씨티카드", "광주카드", "전북카드", "수협카드",
    ]

    static func isCardIssuerName(_ name: String) -> Bool {
        cardIssuerPrefixes.contains { name.hasPrefix($0) }
    }

    /// Lookup keys are upper-cased; Korean keys are unaffected by `uppercased()`.
    static let paymentProviderNormalization: [String: String] = [
        "NAVER FINANCIAL": "네이버페이",
        "NAVER PAY": "네이버페이",
        "NAVERPAY": "네이버페이",
        "네이버파이낸셜": "네이버페이",
        "KAKAOPAY": "카카오페이",
        "KAKAO PAY": "카카오페이",
        "카카오페이먼츠": "카카오페이",
        "토스페이먼츠": "토스페이",
        "TOSSPAYMENTS": "토스페이",
        "TOSS PAYMENTS": "토스페이",
    ]

    static func normalize(_ extraction: PaymentExtraction) -> PaymentExtraction {
        let cleaned = extraction.transactions.map { trans -> PaymentTransaction in
            var t = trans
            let raw = t.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            if isCardIssuerName(raw) {
                t.merchant = ""
            } else if let mapped = paymentProviderNormalization[raw.uppercased()] {
                t.merchant = mapped
            }
            return t
        }
        return PaymentExtraction(transactions: cleaned)
    }

    func extract(from text: String) async throws -> PaymentExtraction {
        let session = LanguageModelSession(
            instructions: Self.instructions(
                today: .now, customGuide: customGuide, categories: categories
            )
        )
        let response = try await session.respond(to: text, generating: PaymentExtraction.self)
        return Self.normalize(response.content)
    }
}

struct StubExtractionService: ExtractionService {
    let result: PaymentExtraction
    let isAvailable: Bool

    init(result: PaymentExtraction, isAvailable: Bool = true) {
        self.result = result
        self.isAvailable = isAvailable
    }

    func extract(from text: String) async throws -> PaymentExtraction {
        result
    }
}
