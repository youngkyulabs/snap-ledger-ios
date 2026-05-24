import FoundationModels

/// Apple Intelligence(SystemLanguageModel) 가용성을 사용자 친화 문구로 매핑한다.
/// 설정/온보딩/검토 탭이 모두 같은 메시지·아이콘·심각도를 쓰도록 단일 진입점.
enum AppleIntelligenceStatus: Equatable, CaseIterable {
    case available
    case appleIntelligenceOff
    case deviceNotEligible
    case modelNotReady

    enum Severity {
        case success
        case warning
        case info
    }

    static var current: AppleIntelligenceStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled: return .appleIntelligenceOff
            case .deviceNotEligible: return .deviceNotEligible
            case .modelNotReady: return .modelNotReady
            @unknown default: return .deviceNotEligible
            }
        }
    }

    var isAvailable: Bool { self == .available }

    /// 상태 행에 표시되는 한 줄 라벨.
    var shortLabel: String {
        switch self {
        case .available:
            return "Apple Intelligence가 켜져 있어요"
        case .appleIntelligenceOff:
            return "Apple Intelligence가 꺼져 있어요"
        case .deviceNotEligible:
            return "이 기기에서는 지원되지 않아요"
        case .modelNotReady:
            return "Apple Intelligence가 준비 중이에요"
        }
    }

    /// 섹션 푸터/도움말에 표시되는 설명. 동작 방식, 호환 기기, 켜는 법 포함.
    var detailMessage: String {
        switch self {
        case .available:
            return "결제 알림 스크린샷이나 영수증 사진을 공유하면 Apple Intelligence가 금액·가맹점·날짜를 자동 추출해서 검토 목록에 채워 넣어요. 사진은 기기 안에서만 처리되고 외부로 전송되지 않아요."
        case .appleIntelligenceOff:
            return "설정 앱 → Apple Intelligence 및 Siri에서 켜주세요. iPhone 15 Pro·Pro Max, iPhone 16 시리즈 이상에서 쓸 수 있어요."
        case .deviceNotEligible:
            return "자동 추출은 iPhone 15 Pro·Pro Max, iPhone 16 시리즈 이상에서 동작해요. 그 외 기기에서는 검토 탭의 + 버튼으로 직접 입력해서 추가하세요."
        case .modelNotReady:
            return "Apple Intelligence가 백그라운드에서 준비 중이에요. 충전 중이거나 Wi-Fi에 연결된 상태로 잠시 기다리면 자동으로 켜져요."
        }
    }

    /// 짧은 안내 배지(온보딩)에서 쓰는 라벨. 꺼져 있을 때 켜는 경로를 함께 보여준다.
    var badgeLabel: String {
        switch self {
        case .available:
            return "Apple Intelligence가 켜져 있어요"
        case .appleIntelligenceOff:
            return "설정 → Apple Intelligence 및 Siri에서 켜주세요"
        case .deviceNotEligible:
            return "이 기기에서는 지원되지 않아요"
        case .modelNotReady:
            return "Apple Intelligence가 준비 중이에요"
        }
    }

    /// 검토 탭의 빈 상태/배너에 표시되는 본문.
    var reviewTabMessage: String {
        switch self {
        case .available:
            return ""
        case .appleIntelligenceOff:
            return "설정 → Apple Intelligence 및 Siri에서 켜면 공유받은 사진을 자동 추출해요. 그 전까지는 + 버튼의 ‘수동 입력’으로 직접 추가하세요."
        case .deviceNotEligible:
            return "이 기기에서는 자동 추출이 지원되지 않아요. 공유받은 사진은 + 버튼의 ‘수동 입력’으로 직접 추가하세요."
        case .modelNotReady:
            return "Apple Intelligence가 준비 중이에요. 잠시 후 사진이 자동 추출돼요. 그 전까지는 + 버튼의 ‘수동 입력’으로 직접 추가할 수 있어요."
        }
    }

    var iconSystemName: String {
        switch self {
        case .available: return "checkmark.seal.fill"
        case .modelNotReady: return "arrow.down.circle.fill"
        case .appleIntelligenceOff, .deviceNotEligible: return "exclamationmark.triangle.fill"
        }
    }

    var severity: Severity {
        switch self {
        case .available: return .success
        case .modelNotReady: return .info
        case .appleIntelligenceOff, .deviceNotEligible: return .warning
        }
    }

    /// "설정 앱 열기" 행을 보여줄지 — 사용자가 시스템 설정에서 직접 켤 수 있는 경우에만.
    var offersSystemSettingsLink: Bool {
        self == .appleIntelligenceOff
    }
}
