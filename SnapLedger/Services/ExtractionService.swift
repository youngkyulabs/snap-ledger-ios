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

    static var isAvailable: Bool { AppleIntelligenceStatus.current.isAvailable }

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

    /// Sanitizes category labels included in the prompt.
    static func sanitizeCategoryLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func categoryPromptParts(for categories: [String]) -> CategoryPromptParts {
        let cleaned = categories.map(sanitizeCategoryLabel).filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            return CategoryPromptParts(
                line: "- category: 사용 가능한 카테고리 목록이 비어 있어요. 항상 빈 문자열로 두세요.",
                example1: "", example2: ""
            )
        }
        let list = cleaned.map { "\"\($0)\"" }.joined(separator: ", ")
        let line = "- category: 다음 라벨 중 가장 잘 맞는 것 하나를 그대로 복사 (양옆 따옴표 제외): \(list). 라벨의 '0.', '1.' 접두 번호나 '・' 구분 기호도 라벨의 일부 — 잘라내지 말고 함께 복사. 맞는 라벨이 없거나 헷갈리면 빈 문자열. 첫 번째 라벨을 기본값으로 쓰지 마세요. 목록 밖 단어 금지."
        return CategoryPromptParts(
            line: line,
            example1: bestCategoryMatch(in: cleaned, keywords: ["쇼핑", "생활"]),
            example2: bestCategoryMatch(in: cleaned, keywords: ["카페", "식비"])
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
           → 서로 다른 결제(가맹점·금액·시각이 다름)마다 transaction 1개, items는 항상 []. 카드사명 헤더(현대카드·신한카드 등)는 별도 transaction 아님.
           → 결제 1건이 여러 줄로 나뉘거나 같은 금액이 반복 표기돼도(예: 한 금액에 '일시불'과 '승인'이 함께 등장) transaction은 1개로 합치세요. '취소·부분취소' 표기가 붙은 금액은 별도 거래로 만들지 마세요.
           → 반대로 가맹점이나 결제 시각이 서로 다르면 금액이 같아도 별개 거래입니다 — 합치지 마세요.

        공통: '누적·한도·잔액·월 사용액·부가세·과세물품가액·포인트·적립·캐시백·마일리지·사용가능' 라인의 숫자는 amount로 절대 사용 금지. 광고 배너 무시. 거래 못 찾으면 transactions=[].

        각 transaction 필드:
        - date: YYYY-MM-DD. 입력이 'YYYY-MM-DD', 'YYYY/MM/DD', 'YYYY.MM.DD', 'M/D HH:mm' 등 어떤 형식이든 정규화. 연도 누락이면 오늘(\(dateFormatter.string(from: today)))의 연도. **입력 텍스트에 날짜 표기가 전혀 없으면 빈 문자열 — 오늘 날짜나 임의의 날짜를 절대 지어내지 마세요.**
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
        === 아래 예시는 형식 설명용 가짜 데이터. merchant/items.name은 placeholder('예시상호N', '예시품목N')입니다.
        응답에 예시 데이터를 복사하지 말고 입력에서만 추출하세요. 입력에 동일 placeholder가 없으면 '예시상호'·'예시품목'으로 시작하는 값은 출력 금지. ===

        예시 1 (알림 리스트, 여러 행 → N개):
        입력: "현대카드  1,111원 일시불, 5/17  예시상호1  누적999,999원  /  2,222원 일시불, 5/17  예시상호2"
        출력: transactions=[
          {date="2026-05-17", amount=1111, merchant="예시상호1", category="\(example1Category)", items=[]},
          {date="2026-05-17", amount=2222, merchant="예시상호2", category="\(example1Category)", items=[]}
        ]

        예시 2 (영수증 한 장 → transaction 1개, 품목은 items로):
        입력: "예시상호3  2026-05-17  예시품목1 3,333  예시품목2 4,444  합계 7,777  부가세 707"
        출력: transactions=[
          {date="2026-05-17", amount=7777, merchant="예시상호3", category="\(example2Category)",
            items=[{name="예시품목1", amount=3333}, {name="예시품목2", amount=4444}]}
        ]

        예시 3 (알림 1건인데 같은 금액이 반복 표기 → 나누지 말고 1개로 합침):
        입력: "현대카드 승인  9,900원 일시불  9,900원 승인완료  5/17  예시상호4  누적 12,345원"
        출력: transactions=[
          {date="2026-05-17", amount=9900, merchant="예시상호4", category="\(example1Category)", items=[]}
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

    /// Known card issuer prefixes for filtering merchant field.
    static let cardIssuerPrefixes: [String] = [
        "현대카드", "신한카드", "삼성카드", "BC카드", "비씨카드",
        "롯데카드", "국민카드", "KB카드", "KB국민카드",
        "하나카드", "농협카드", "NH농협카드", "우리카드",
        "씨티카드", "광주카드", "전북카드", "수협카드",
    ]

    static func isCardIssuerName(_ name: String) -> Bool {
        cardIssuerPrefixes.contains { name.hasPrefix($0) }
    }

    /// Placeholder prefixes used in prompt examples to detect hallucination.
    static let exampleMerchantPrefix = "예시상호"
    static let exampleItemPrefix = "예시품목"

    static func looksLikeExampleLeak(_ trans: PaymentTransaction) -> Bool {
        let merchant = trans.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        if merchant.hasPrefix(exampleMerchantPrefix) { return true }
        for item in trans.items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.hasPrefix(exampleItemPrefix) { return true }
        }
        return false
    }

    /// Payment provider aliases normalized to standard names. Keys must be upper-cased — lookup uses `uppercased()`.
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

    /// Regex for detecting presence of date tokens in OCR text.
    private static let datePresence: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\d{4}[-./]\d{1,2}[-./]\d{1,2}|\b(0?[1-9]|1[0-2])[-./](0?[1-9]|[12]\d|3[01])\b|\d{1,2}\s*월\s*\d{1,2}\s*일"#
    )

    static func hasDateToken(_ text: String) -> Bool {
        // Conservative fallback on regex compilation failure
        guard let re = datePresence else { return true }
        let range = NSRange(text.startIndex..., in: text)
        return re.firstMatch(in: text, range: range) != nil
    }

    /// Regex for a year stated by the source text. Requires a 19xx/20xx run that is not part of a
    /// longer digit group and, for the separated form, a valid month and day — otherwise account
    /// numbers such as `123456-78-901234` read as a date.
    private static let explicitYearPresence: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?<!\d)(19|20)\d{2}(?:[-./](?:0?[1-9]|1[0-2])[-./](?:0?[1-9]|[12]\d|3[01])(?!\d)|\s*년)"#
    )

    /// Whether the source text states a year. When it does not, a model-supplied year carries no
    /// information and only the month/day may be trusted.
    static func hasExplicitYear(_ text: String) -> Bool {
        // Conservative fallback on regex compilation failure
        guard let re = explicitYearPresence else { return true }
        let range = NSRange(text.startIndex..., in: text)
        return re.firstMatch(in: text, range: range) != nil
    }

    /// Year/month/day split out of a raw date string.
    private struct DateParts {
        let year: Int
        let month: Int
        let day: Int
    }

    /// Splits a date string into components, accepting `-`, `/`, and `.` separators.
    private static func dateParts(_ raw: String) -> DateParts? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day)
        else { return nil }
        return DateParts(year: year, month: month, day: day)
    }

    /// Rebuilds a date from its month/day by choosing the year that places it nearest to today.
    /// Used when the source text states no year: the model's year is discarded rather than nudged
    /// by a single step, which previously left dates two or more years off uncorrected. The same
    /// 2-day future slack as `normalizeYear` absorbs timezone skew. Input that cannot be parsed, or
    /// whose month/day does not exist in the snapped year, is returned unchanged.
    static func snapYearToNearest(
        _ raw: String,
        today: Date,
        calendar: Calendar = .current
    ) -> String {
        guard let parts = dateParts(raw) else { return raw }

        let todayYear = calendar.component(.year, from: today)
        var comps = DateComponents()
        comps.year = todayYear
        comps.month = parts.month
        comps.day = parts.day
        guard let candidate = calendar.date(from: comps),
              calendar.component(.month, from: candidate) == parts.month,
              calendar.component(.day, from: candidate) == parts.day
        else { return raw }

        let todayStart = calendar.startOfDay(for: today)
        let days = calendar.dateComponents(
            [.day], from: todayStart, to: calendar.startOfDay(for: candidate)
        ).day ?? 0

        let snappedYear = days > 2 ? todayYear - 1 : todayYear
        // A leap day cannot move to a common year; leave such input alone.
        comps.year = snappedYear
        guard let snapped = calendar.date(from: comps),
              calendar.component(.month, from: snapped) == parts.month,
              calendar.component(.day, from: snapped) == parts.day
        else { return raw }

        return String(format: "%04d-%02d-%02d", snappedYear, parts.month, parts.day)
    }

    /// Corrects a hallucinated year using the "payment time ≈ extraction time" invariant — given a
    /// partial `M/D`, models often fill in a training-distribution year instead of today's. The window is
    /// asymmetric: a future date is almost always a wrong year, so only 2 days of timezone slack are
    /// allowed before year - 1, while a past date stays plausible for months, so year + 1 applies only
    /// beyond 330 days back. Unparseable or out-of-range input is returned unchanged.
    static func normalizeYear(
        _ raw: String,
        today: Date,
        calendar: Calendar = .current
    ) -> String {
        guard let parts = dateParts(raw) else { return raw }
        let (year, month, day) = (parts.year, parts.month, parts.day)

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let candidate = calendar.date(from: comps) else { return raw }

        let todayStart = calendar.startOfDay(for: today)
        let candidateStart = calendar.startOfDay(for: candidate)
        let days = calendar.dateComponents([.day], from: todayStart, to: candidateStart).day ?? 0

        var adjustedYear = year
        if days > 2 {
            adjustedYear -= 1
        } else if days < -330 {
            adjustedYear += 1
        }

        return String(format: "%04d-%02d-%02d", adjustedYear, month, day)
    }

    static func normalize(
        _ extraction: PaymentExtraction,
        today: Date = .now,
        calendar: Calendar = .current,
        ocrText: String? = nil
    ) -> PaymentExtraction {
        // Drop hallucinated dates if OCR text has no date token
        let dropDates = ocrText.map { !hasDateToken($0) } ?? false
        // Discard the model's year outright when the text never stated one.
        let yearUnstated = ocrText.map { !hasExplicitYear($0) } ?? false
        let cleaned = extraction.transactions.compactMap { trans -> PaymentTransaction? in
            if looksLikeExampleLeak(trans) { return nil }
            var t = trans
            if dropDates {
                t.date = ""
            } else if yearUnstated {
                t.date = snapYearToNearest(t.date, today: today, calendar: calendar)
            } else {
                t.date = normalizeYear(t.date, today: today, calendar: calendar)
            }
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
        let today = Date.now
        let session = LanguageModelSession(
            instructions: Self.instructions(
                today: today, customGuide: customGuide, categories: categories
            )
        )
        let response = try await session.respond(to: text, generating: PaymentExtraction.self)
        return Self.normalize(response.content, today: today, ocrText: text)
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
