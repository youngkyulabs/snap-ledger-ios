import Foundation
import SwiftData

/// 카테고리 프리셋 1개 = 레코드 1개(CloudKit private DB로 동기화).
/// 추가/삭제/정렬이 레코드 연산으로 매핑되어 다기기 동시 편집도 안전 병합된다.
/// CloudKit 제약: 관계 없음, 유니크 없음, 모든 속성 기본값 보유.
@Model
final class CategoryPreset {
    var name: String = ""
    var sortOrder: Int = 0

    init(name: String = "", sortOrder: Int = 0) {
        self.name = name
        self.sortOrder = sortOrder
    }
}
