# SnapLedger (찰칵가계부)

카드 결제 알림 스크린샷이나 영수증을 공유받아 자동으로 가계부에 정리하는 iOS 앱.

## 동작 흐름

1. iOS 공유 시트에서 찰칵가계부 선택 (또는 Shortcuts/Siri로 "이미지에서 지출 추가")
2. 이미지가 App Group inbox에 큐잉되고 찰칵가계부 앱이 백그라운드에서 처리
3. **VisionKit OCR**로 한·영 텍스트 추출
4. **Apple Foundation Models**로 결제일·금액·가맹점·카테고리를 정형 추출
5. 검토 탭에서 사용자가 확인·수정 후 저장
6. 사용자가 지정한 iCloud Drive 폴더에 월별 CSV(`expenses-YYYY-MM.csv`)로 append

## 주요 기능

- **공유 시트 통합** — Photos / 메시지 / 카드사 앱 등에서 한 번에 캡쳐
- **다양한 추가 경로** — 검토 탭 `+` 메뉴로 사진/클립보드/파일/드래그&드롭/수동 입력 지원
- **로컬 LLM 추출** — Foundation Models로 디바이스 내 처리, 외부 전송 없음
- **다중 거래 추출** — 한 이미지에 알림이 여러 건이면 N개 entry로 분리
- **결제 신호 가드** — OCR 결과를 휴리스틱으로 점수화해 풍경 등 결제와 무관한 이미지에서의 LLM 환각을 사전 차단
- **누적 금액 등 오인식 방지** — prompt에서 `누적/잔액/한도/포인트` 같은 보조 금액 명시적 배제
- **사용자 추출 가이드** — 카드사별 특이 패턴을 Settings에서 자유 텍스트로 추가
- **카테고리 편집** — 카테고리 프리셋을 추가/삭제/재정렬, 추출 prompt에 동적 주입
- **카테고리 학습** — 검토에서 사용자가 카테고리를 바꾸면 가맹점→카테고리 매핑을 학습해 다음번에 자동 적용
- **기록 탭** — 월별 CSV 뷰어 + 다중 선택 복사 (HTML+TSV 멀티 페이로드로 Numbers에 표 그대로 paste)
- **통계 대시보드** — 카테고리 도넛 + 전월 대비 추세
- **야간 알림** — 매일 설정한 시각에 검토 대기 건수 알림 (홈 화면 아이콘 뱃지도 동기화)
- **백그라운드 처리** — BGTaskScheduler로 앱 미사용 시에도 catch-up 처리
- **Shortcuts/Siri** — `AddExpenseFromImageIntent`로 음성·자동화에서 호출 가능
- **CSV / TSV 출력** — BOM + UTF-8, NSFileCoordinator로 다중 프로세스 안전

## 요구사항

- **iOS 26.0+** (Foundation Models 사용)
- **Apple Intelligence 지원 기기** (iPhone 15 Pro 이상 권장 — 시뮬레이터에서는 unavailable일 수 있음)
- Xcode 26+
- 개인 Apple ID (시뮬레이터 + 본인 디바이스 빌드용)
- **SwiftLint** — `brew install swiftlint`. 빌드 페이즈가 `--strict`로 강제. 미설치 시 페이즈는 warning 후 graceful pass (lint 위반만 fail, 도구 부재는 pass).

## 빌드

```bash
xcodebuild -project SnapLedger.xcodeproj -scheme SnapLedger \
  -destination 'generic/platform=iOS Simulator' build
```

빌드 페이즈가 SwiftLint를 자동 실행하지만, 변경 직후 빠르게 검증하려면:

```bash
swiftlint --strict --config .swiftlint.yml
```

테스트:

```bash
xcodebuild test -project SnapLedger.xcodeproj -scheme SnapLedger \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:SnapLedgerTests
```

## 초기 셋업 (한 번만)

Xcode에서 **SnapLedger**, **SnapLedgerTests**, **SnapLedgerUITests**, **SnapLedgerShareExtension** 각 타겟의 Signing & Capabilities에서:

1. Team을 본인 Apple ID로 설정
2. (메인 앱 / Share Extension만) App Groups 캐퍼빌리티 추가, `group.com.youngkyu.snapledger` 등록

자세한 컨벤션과 아키텍처는 [CLAUDE.md](CLAUDE.md) 참고.

## 기술 스택

- Swift 6, SwiftUI, SwiftData (모든 SwiftData 컨테이너는 App Group 공유)
- VisionKit (OCR)
- Foundation Models (`@Generable` 정형 추출)
- AppIntents (Shortcuts/Siri 노출)
- UserNotifications (야간 알림)
- BackgroundTasks (BGAppRefreshTask)
- Swift Testing (`@Test` / `#expect`)
