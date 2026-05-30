# CLAUDE.md

이 파일은 미래의 Claude Code 세션에게 SnapLedger 코드베이스를 안내합니다. 새 세션이 빠르게 productive해지도록 핵심 컨벤션·아키텍처·빌드 방법을 압축해서 기록합니다.

## 프로젝트 한 줄 요약

iOS 26 / Apple Intelligence 기반의 한국 가계부 앱. 카드 결제 알림 스크린샷 또는 영수증 사진을 공유받아 OCR(VisionKit) → Foundation Models로 정형 추출 → 사용자 검토 → 사용자 지정 iCloud Drive 폴더의 월별 CSV에 append.

## 빌드 / 테스트

```bash
# Lint (strict, build와 무관하게 빠른 사전 검증)
swiftlint --strict --config .swiftlint.yml

# Build (시뮬레이터 generic, 대부분의 일상 빌드 — SwiftLint 페이즈가 strict로 함께 실행됨)
xcodebuild -project SnapLedger.xcodeproj -scheme SnapLedger \
  -destination 'generic/platform=iOS Simulator' build

# Unit tests (Swift Testing — @Test / #expect)
xcodebuild test -project SnapLedger.xcodeproj -scheme SnapLedger \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:SnapLedgerTests
```

SwiftLint는 `brew install swiftlint`로 사전 설치. 미설치 시 빌드 페이즈는 warning 출력 후 통과 (lint 위반은 fail, 도구 부재는 graceful pass).

시뮬레이터 디바이스 이름은 `xcrun simctl list devices available | grep iPhone`로 확인. iPhone 17 Pro 기본.

## CI / CD

역할 분리:

- **CI는 GitHub Actions** (`.github/workflows/ci.yml`): 모든 push·PR마다 `swiftlint --strict` + `xcodebuild build` + `xcodebuild test` 풀세트. lint·빌드·테스트 게이트는 전부 여기서 담당.
- **CD는 Xcode Cloud**: Archive → TestFlight 업로드 전용. `main` push에 빌드에 영향이 있는 코드가 변경되면 자동 트리거 (문서만 바뀌는 경우 스킵하도록 Xcode Cloud 워크플로의 start condition에서 path 필터링). 필요 시 App Store Connect 웹 또는 Xcode Cloud 탭에서 **Start Build**로 수동 실행도 가능. 빌드 번호는 Xcode Cloud 워크플로의 자동 증가 설정으로 관리 (pbxproj `CURRENT_PROJECT_VERSION`은 정적 값 유지).

**SwiftLint 빌드 페이즈는 Xcode Cloud에서 스킵됨**: 빌드 페이즈 첫 줄에서 `CI_XCODE_CLOUD=TRUE`를 감지해 early-exit. 이유는 (1) lint gate는 이미 GitHub Actions가 담당하고 (2) Xcode Cloud 워커마다 매번 SwiftLint를 brew install 하는 비용·warning을 피하기 위함. 로컬과 GitHub Actions에서는 그대로 strict 실행됨.

## 모듈 레이아웃

폴더 이름이 곧 역할이다. 어디에 뭐를 둘지 헷갈리면 이 표만 보면 된다.

| 폴더 | 무엇이 들어가나 | 무엇이 들어가면 안 되나 |
|---|---|---|
| `App/` | 앱 진입점·셸·App Group 상수 | 비즈니스 로직, 도메인 모델 |
| `Models/` | SwiftData `@Model` 5종 | 비-SwiftData DTO (그건 `Services/`) |
| `Services/` | 비즈니스 로직 (OCR·추출·저장 오케스트레이션·도메인 헬퍼) | UI, 파일·시스템 IO |
| `Storage/` | 파일/클립보드/북마크 IO | 비즈니스 결정 (어떤 데이터를 저장할지는 `Services/`) |
| `Features/` | UI 탭 화면 + 온보딩 (SwiftUI) | 시스템 통합(BGTask/Intent/Notification) → `System/` |
| `System/` | 시스템 통합 지점 (BGTask·AppIntent·UNUserNotification) | SwiftUI 화면 |

```
SnapLedger/                          # 메인 앱 타겟 (synchronized root group)
  App/                               # 앱 진입점
    SnapLedgerApp.swift              # @main, ModelContainer (groupContainer), BGTask register
    ContentView.swift                # TabView 셸 (검토/기록/통계/설정) + scenePhase 옵저버 + 온보딩 게이트
    AppGroup.swift                   # group.com.youngkyu.snapledger 컨테이너 / inbox URL
  Info.plist                         # 부분 plist: BGTaskSchedulerPermittedIdentifiers + UIBackgroundModes
                                     #            + ITSAppUsesNonExemptEncryption
  SnapLedger.entitlements            # App Group
  AppIcon.icon / Assets.xcassets

  Models/                            # SwiftData @Model
    AppSettings.swift, ParsedEntry.swift, SavedEntry.swift, PendingImage.swift, MerchantCategory.swift
    CSVFileState.swift               # 월별 CSV 파일의 마지막 동기화 지문 (해시+mtime) — 외부 변경 감지 기준

  Services/                          # 비즈니스 로직 (전부 unit-testable)
    OCRService.swift                 # protocol + VisionKitOCRService (한·영 accurate)
    CandidateHeuristics.swift        # OCR 텍스트의 결제 신호 점수화 (풍경 사진 환각 차단)
    ExtractionService.swift          # protocol + FoundationModelsExtractionService (dynamic prompt, 다중 거래)
    PaymentExtraction.swift          # @Generable PaymentExtraction(transactions:[Transaction])
    AppleIntelligenceStatus.swift    # FM 가용성 → 사용자 친화 문구 (설정·온보딩·검토 탭 공통 진입점)
    PendingProcessor.swift           # @MainActor 파이프라인: reconcile inbox → OCR → heuristic → extract → ParsedEntry
    SaveCoordinator.swift            # 검토 확정 → CSV append + SavedEntry 생성 + 학습
    CategoryLearner.swift            # 가맹점 → 카테고리 학습/조회
    ImageImporter.swift              # + 메뉴에서 사진/클립보드/파일/드롭 → inbox 정규화

  Storage/                           # 파일·클립보드·북마크 IO
    CSVWriter.swift                  # NSFileCoordinator 기반 월별 CSV (BOM + 헤더 + escape)
    CSVParser.swift                  # 기록 탭 월별 CSV 뷰어용 파서
    BookmarkStore.swift              # security-scoped bookmark 생성/해소
    FolderBookmarkHelper.swift       # BookmarkStore 래퍼 — URL → AppSettings.csvFolderBookmark 적용
    ClipboardExporter.swift          # 검토/기록 항목을 TSV(+HTML) 페이로드로 (Numbers paste용)

  Features/                          # UI 화면
    Review/                          # ReviewListView (+ 메뉴/드롭존/뱃지/처리중 표시), EntryEditorView (chip row)
    History/                         # HistoryView (@Query SavedEntry, 일별 섹션), SavedEntryEditorView,
                                     # CSVFileView (월별 표 뷰어 + 다중 선택 복사/공유), HistoryGrouping (pure)
    Statistics/                      # StatisticsView (카테고리 도넛 + 전월 대비), StatisticsAggregation (pure)
    Settings/                        # SettingsView (저장폴더 행=폴더이름+동기화 상태아이콘→폴더상태 / reminder / FM 상태),
                                     # AdvancedSettingsView (카테고리 / 추출 가이드), FolderPicker, FeedbackMail (pure), MailComposeSheet
    Onboarding/                      # OnboardingView + ValuePage/SetupPage + AppearStep/PermissionAction (pure)

  System/                            # 시스템 통합 (화면 아님)
    Background/BackgroundRefresh.swift          # BGAppRefreshTask
    Intents/AddExpenseFromImageIntent.swift     # AppIntent (Spotlight/Siri)
    Intents/SnapLedgerShortcuts.swift           # AppShortcutsProvider
    Notifications/NotificationScheduler.swift   # UNUserNotification wrapper
    Notifications/ReminderContent.swift         # pure: 시간/카운트 → 본문

SnapLedgerShareExtension/            # Share Extension 타겟 (synchronized root group, 별도)
  ShareViewController.swift          # silent UIVC, NSItemProvider 이미지를 App Group inbox에 복사
  Info.plist                         # 명시적 plist: NSExtensionPrincipalClass, image-only activation
  SnapLedgerShareExtension.entitlements   # App Group

SnapLedgerTests/                     # Swift Testing — 소스 구조를 미러링
  Models/    Services/    Storage/    Features/    System/
```

## 핵심 아키텍처 결정

1. **공유 시트 → inbox 파일 → 메인 앱 reconcile**
   Share Extension은 `PendingImage` row를 직접 만들지 않습니다. 파일만 `App Group 컨테이너/inbox/`에 떨어뜨리고 dismiss. 메인 앱이 launch / foreground 진입 / BGTask 실행 시 `PendingProcessor.reconcileInbox`로 inbox를 스캔해 row 없는 파일에 대해 `PendingImage`를 생성. 이렇게 한 이유는 Xcode 16 `PBXFileSystemSynchronizedRootGroup` 사용 시 같은 .swift 파일을 두 타겟 멤버십에 깔끔히 넣기가 어렵기 때문 — Extension은 SwiftData에 의존하지 않고 App Group identifier만 inline 상수로 가지면 충분합니다.

2. **Foundation Models은 가드한다**
   `FoundationModelsExtractionService.isAvailable`로 체크. unavailable이면 drain은 통째로 스킵하고 (`ContentView.drainPending`, `BackgroundRefresh.handle`), AddExpenseFromImageIntent는 "큐에 추가됨" 메시지로 graceful degrade. 시뮬레이터에서는 Apple Intelligence가 없을 수 있으니 실기기 검증 필요.

3. **모든 SwiftData 컨테이너는 group container 사용**
   `ModelConfiguration(schema: schema, groupContainer: .identifier(AppGroup.identifier))`. 메인 앱과 AppIntent가 같은 store를 봅니다.

4. **추출 정확도는 prompt + 사용자 가이드로 잡는다**
   `FoundationModelsExtractionService.instructions(today:customGuide:categories:)`가 단일 source-of-truth. 카드사 알림 형식(`<금액>원 일시불`)과 금지 단어(`누적`, `잔액`, `한도`, `포인트` 등)를 explicit하게 명시. `@Guide`는 instructions에 위임(하드코딩 금지). 사용자가 Settings에서 추가 가이드를 적으면 prompt 끝에 "사용자 가이드 (위 규칙보다 우선 적용)"으로 append됨.

5. **카테고리 목록은 동적**
   `AppSettings.categoryPresets`(사용자 편집 가능)가 prompt에 그대로 주입됨. 모델은 그 목록 안에서만 선택하도록 soft-constrain.

6. **CSV 쓰기는 NSFileCoordinator로 보호**
   `CSVWriter.append`는 `.forMerging`으로 cross-process safe. 헤더는 첫 호출에만 BOM과 함께. 월별 파일은 `expenses-YYYY-MM.csv`.

7. **파일 동기화는 월 단위 통째 교체** (`SyncCoordinator`)
   CSV 행에 안정적 ID가 없어 fine-grained 머지는 포기 — 외부 변경된 달은 그 달 전체를 한 방향으로 교체한다.
   - **감지**: `CSVFileState`(앱이 마지막으로 쓴 지문) vs 현재 `FileFingerprint`(내용 SHA-256). 앱 진입(`scenePhase .active`) 시 비교 → 변경 있으면 인앱 알럿. 백그라운드 파일 감시는 iOS 제약상 안 함.
   - **충돌 가드**: `SaveCoordinator`가 저장/수정/삭제 직전 `checkWriteGuard`로 대상 달 지문을 확인. 외부 변경이면 `externalConflict` throw → UI에서 [가져오기/덮어쓰기] 해소 (`SyncConflictAlert`).
   - **iCloud 다운로드 게이트**: `FileFingerprint`가 미다운로드 파일을 만나면 다운로드만 트리거하고 `.notDownloaded` 반환 → 감지/충돌/import에서 그 파일은 건너뜀 (부분 데이터로 덮어쓰기 방지). 메인 스레드를 다운로드 완료까지 블로킹하지 않음.
   - **마이그레이션**: 기능 도입 전부터 있던 파일을 "외부 새 파일"로 오인하지 않도록, 폴더가 준비된 첫 진입에서 현재 지문을 baseline으로 기록 (`AppSettings.hasSyncBaseline`). 폴더 변경 시 `resetSyncState`로 지문을 비우고 baseline 리셋.
   - 모든 CSV 쓰기/import 후 지문을 갱신해 다음 감지의 기준으로 삼는다. 수동 동기화 진입점은 **설정 → 저장 폴더 행**: 폴더 이름 행 우측에 상태 아이콘(동기화됨=초록 체크 / 변경 있음=노랑 경고 / 폴더 없음=빨강 경고 / 데이터 없음=아이콘 없음, `SyncCoordinator.folderSyncSummary`)을 두고, 탭하면 `FileSyncView`("폴더 상태")로 이동. 그 화면에서 월별 상태(최신/파일 변경됨/파일에만 있음/앱에만 있음)를 보고 **달별로** 가져오기/저장(`SyncCoordinator.monthStatuses`, 월 탭 시 일반 alert), 하단에서 폴더 변경. (전체 일괄 동기화는 위험 대비 실효가 낮아 미제공 — importAll/exportAll은 테스트 전용 API로만 잔존.)
   - **폴더 삭제/이동 처리**: bookmark는 resolve돼도 실제 디렉토리가 없을 수 있음 → `BookmarkStore.isReachableDirectory`로 확인. `SyncCoordinator.withFolder`·`SaveCoordinator`(save/update/delete)는 `folderUnavailable`로 차단하고, `folderSyncSummary`는 `.folderMissing`(빨강 경고), `FileSyncView`는 "폴더를 찾을 수 없어요 + 폴더 변경" 화면을 노출.

## 컨벤션 (지켜주세요)

- **파일 헤더 금지**: 새 `.swift` 파일은 헤더 주석 없이 바로 `import`부터 시작. Xcode 템플릿이 삽입하는 `// FileName.swift\n// Target\n// Created by...` 블록은 즉시 제거.
- **Swift Testing 사용**: 새 단위 테스트는 `import Testing`, `@Test`, `#expect`. XCTest는 UI 테스트(`SnapLedgerUITests`)에서만 사용.
- **@MainActor 기본**: 프로젝트의 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. SwiftData 접근 코드는 모두 main isolated. 명시 가능한 곳은 `@MainActor` 표기.
- **테스트 가능한 헬퍼로 분리**: UIKit·SwiftData·UN(notification)·시스템 의존 코드는 stateless pure-function 헬퍼(`ReminderContent`, `instructions(today:customGuide:categories:)`)를 추출해 그쪽을 단위 테스트. 시스템 wrapper는 얇게.
- **SwiftLint strict**: 메인 `SnapLedger` 타겟의 첫 빌드 페이즈 `SwiftLint`가 `--strict`로 실행돼 모든 warning을 build error로 격상. 룰 우회는 inline `// swiftlint:disable:next <rule>`로 1회성 정당화만 허용 (예외: 테스트 파일의 `force_unwrapping`은 file-level disable 허용 — `blanket_disable_command.allowed_rules`에 화이트리스트). production 코드에서 `force_unwrapping`이 fire하면 `Data(s.utf8)` 같은 non-failing API로 대체.
- **에러는 root cause를 잡고 우회하지 않는다**: lint 위반, 빌드 워닝 등을 `--no-verify` / 무시 코드 / blanket disable로 우회하지 않습니다.
- **변경 후 검증**: `swiftlint --strict --config .swiftlint.yml` → `xcodebuild build` → `xcodebuild test` 셋 모두 통과 후 PR/커밋 제안. lint·빌드만 통과해도 안 됨.

## 식별자 / 상수

| 이름 | 값 | 위치 |
|---|---|---|
| App Group ID | `group.com.youngkyu.snapledger` | `AppGroup.swift`, ShareViewController inline, entitlements |
| BGTask identifier | `com.youngkyu.snapledger.refresh` | `BackgroundRefresh.swift`, `SnapLedger/Info.plist` |
| Reminder notification ID | `com.youngkyu.snapledger.nightly-reminder` | `ReminderContent.swift` |
| Bundle ID (main) | `com.youngkyu.snapledger` | pbxproj |
| Bundle ID (extension) | `com.youngkyu.snapledger.SnapLedgerShareExtension` | pbxproj |

## 빌드 시스템 주의사항

- **Xcode 16 synchronized groups**: `SnapLedger/`, `SnapLedgerTests/`, `SnapLedgerUITests/`, `SnapLedgerShareExtension/`은 각각 `PBXFileSystemSynchronizedRootGroup`. 폴더에 파일을 넣으면 해당 타겟에 자동 멤버십. 한 파일을 두 타겟에 넣는 건 어려움 → 코드 공유 대신 inline 중복(예: App Group ID 상수)이나 file-based IPC 사용.
- **메인 앱 Info.plist는 부분 plist + 자동 생성 병합**: `GENERATE_INFOPLIST_FILE = YES`와 `INFOPLIST_FILE = SnapLedger/Info.plist`를 같이 씀. 자동 생성되는 키(SceneManifest, LaunchScreen, orientations)는 `INFOPLIST_KEY_*` 빌드 설정으로, 임의 키(`BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes`)는 부분 plist 파일로. 부분 plist는 synchronized group의 `membershipExceptions`에 등록해 resource 중복 방지.
- **Extension Info.plist는 전체 plist**: 자동 생성 안 함 — 모든 키를 명시.
- **SwiftLint 빌드 페이즈는 sandbox용 inputPaths를 가짐**: `ENABLE_USER_SCRIPT_SANDBOXING = YES`라서 `$(SRCROOT)/.swiftlint.yml`과 4개 소스 루트(`SnapLedger`, `SnapLedgerShareExtension`, `SnapLedgerTests`, `SnapLedgerUITests`)를 inputPaths로 선언. 새 source root 디렉토리를 추가하면 이 목록도 갱신 필요. xattr 관련 sandbox warning은 무해 (실제 read는 통과).

## 자주 쓰는 검증 명령

```bash
# Build 직후 Info.plist 키 확인
plutil -p /Users/youngkyu/Library/Developer/Xcode/DerivedData/SnapLedger-*/Build/Products/Debug-iphonesimulator/SnapLedger.app/Info.plist

# 시뮬레이터의 App Group inbox 확인 (Share Extension이 떨어뜨린 파일 검증)
xcrun simctl get_app_container booted com.youngkyu.snapledger groups
ls "$(xcrun simctl get_app_container booted com.youngkyu.snapledger groups | awk '{print $2}')/inbox/"

# BGTask 강제 트리거 (LLDB on booted app)
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.youngkyu.snapledger.refresh"]
```

## 알려진 한계 (의도적, 변경 전 확인)

- Foundation Models가 simulator에서 unavailable이면 drain이 통째로 스킵되어 검토 탭이 비어 보임. inbox 파일은 그대로 큐잉 상태로 남아 있음 — 실기기에서 처리됨.
- Reminder 본문은 백그라운드 진입 시점의 pending 카운트로 baked-in. 그 후 Extension으로 더 공유해도 본문 숫자는 stale일 수 있음 (다음 백그라운드 진입 때 refresh됨). MVP에서 허용.
- Share Extension UI는 호스트 앱이 detent 힌트(`preferredContentSize`)를 무시할 수도 있음. 표준 host (Photos, Safari, Messages)에서는 동작.
