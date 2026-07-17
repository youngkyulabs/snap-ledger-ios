# SnapLedger (찰칵가계부)

카드 결제 알림 스크린샷이나 영수증을 공유받아 자동으로 가계부에 정리하는 iOS 앱.

- **App Store**: [다운로드](https://apps.apple.com/app/id6772852897)
- [개인정보처리방침](https://youngkyulabs.github.io/snap-ledger-ios/privacy-policy.html)
- [지원 페이지](https://youngkyulabs.github.io/snap-ledger-ios/support.html)

> 이 저장소는 투명성을 위해 소스 코드를 공개합니다. 외부 Pull Request·기여는 받지 않으며, 코드의 재사용·재배포를 허용하지 않습니다 (자세한 내용은 [LICENSE](LICENSE) 참고). 버그 제보·기능 제안은 [Issues](../../issues)로 환영합니다.

## 동작 흐름

1. iOS 공유 시트에서 찰칵가계부 선택 (또는 Shortcuts/Siri로 "이미지에서 지출 추가")
2. 이미지가 App Group inbox에 큐잉되고 찰칵가계부 앱이 백그라운드에서 처리
3. **VisionKit OCR**로 한·영 텍스트 추출
4. **Apple Foundation Models**로 결제일·금액·가맹점·카테고리를 정형 추출
5. 검토 탭에서 사용자가 확인·수정 후 저장
6. 데이터는 iCloud(CloudKit)에 저장돼 기기 간 자동 동기화. 저장 폴더를 지정하면 월별 CSV(`expenses-YYYY-MM.csv`)로도 자동 내보내기(백업)

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
- **기록 탭** — 저장한 지출을 일별로 보기 + 가맹점·카테고리·메모·금액 검색 + 내보낸 월별 CSV 뷰어와 다중 선택 복사 (HTML+TSV 멀티 페이로드로 Numbers에 표 그대로 paste)
- **검토 날짜 경고** — 캡처 시점 기준으로 결제일이 너무 오래됐거나 미래면 검토 팝업에서 경고 아이콘으로 표시 (저장 전 오탐 확인)
- **iCloud 동기화 + CSV 백업** — 모든 데이터의 진실원은 iCloud(CloudKit)라 기기 간 자동 동기화. 저장 폴더를 지정하면 월별 CSV로 한 방향 자동 내보내기(백업·AI 분석용). 폴더를 안 골라도 데이터는 안전 (설정 → 저장 폴더에서 전체 내보내기·폴더 변경)
- **통계 대시보드** — 카테고리 도넛 + 전월 대비 추세 (도넛 조각을 탭하면 그 카테고리 항목 목록)
- **카테고리 예산** — 카테고리별 월 한도 설정, 사용률 진행률로 표시. 한도는 변경 전까지 매월 자동 이월. 그 달 유효 한도는 `budgets-YYYY-MM.csv`로도 내보내져 지출 CSV와 join해 AI 분석 가능 (지출·정산과 동일한 한 방향 export)
- **월 정산** — 수입·카드 사용액·저축·계좌별 잔액·자금 변동을 입력해 '실제 쓴 돈'과 '기록한 돈'을 대조. 결과는 저장 폴더에 `reconciliations-YYYY-MM.csv`로 내보내져 AI에게 그대로 분석을 맡길 수 있음 (지출 CSV와 동일한 한 방향 export)
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

- Swift 6, SwiftUI, SwiftData + CloudKit (가계부·예산·정산 데이터는 CloudKit private DB가 진실원, 기기 간 자동 동기화. 인텐트 공유용 로컬 모델은 App Group 컨테이너)
- VisionKit (OCR)
- Foundation Models (`@Generable` 정형 추출)
- AppIntents (Shortcuts/Siri 노출)
- UserNotifications (야간 알림)
- BackgroundTasks (BGAppRefreshTask)
- Swift Testing (`@Test` / `#expect`)

## CI / CD

- **CI**: GitHub Actions — 모든 push·PR마다 lint + build + test
- **CD**: Xcode Cloud — `main` push에 빌드에 영향이 있는 코드가 변경되면 자동으로 TestFlight 업로드 (문서만 바뀌면 스킵, 수동 실행도 가능)
