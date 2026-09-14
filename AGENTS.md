# AGENTS.md

This file guides future AI assistant sessions through the SnapLedger codebase. It compresses key conventions, architecture, and build workflows so a new session can become productive quickly.

## One-Line Project Summary

A Korean personal finance app built on iOS 26 and Apple Intelligence. Receives card payment notification screenshots or receipt photos via the share sheet → VisionKit OCR → structured extraction via Foundation Models → user review → saved to CloudKit-backed SwiftData (single source of truth). If the user designates a storage folder, exports one-way monthly CSVs (optional, for backup & AI analysis).

## Build / Test

```bash
# Lint (strict, fast pre-validation independent of build)
swiftlint --strict --config .swiftlint.yml

# Build (generic simulator, standard daily build — runs SwiftLint build phase in strict mode)
xcodebuild -project SnapLedger.xcodeproj -scheme SnapLedger \
  -destination 'generic/platform=iOS Simulator' build

# Unit tests (Swift Testing — @Test / #expect)
xcodebuild test -project SnapLedger.xcodeproj -scheme SnapLedger \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:SnapLedgerTests
```

SwiftLint should be pre-installed via `brew install swiftlint`. If not installed, the build phase prints a warning and gracefully passes (lint violations fail the build, but tool absence passes).

Simulator device names can be confirmed with `xcrun simctl list devices available | grep iPhone`. Defaults to `iPhone 17 Pro`. (Note: if multiple iOS runtimes are installed, you can specify `OS=26.5` or use the device ID from `xcrun simctl list devices`).

## CI / CD

Separation of concerns:

- **CI is GitHub Actions** (`.github/workflows/ci.yml`): Full suite of `swiftlint --strict` + `xcodebuild build` + `xcodebuild test` on every push and PR. All lint, build, and test gates are enforced here.
- **CD is Xcode Cloud**: Archive → TestFlight upload only. Automatically triggered on pushes to `main` when build-affecting code changes (path filtering in the Xcode Cloud workflow's start condition skips doc-only changes). Can also be triggered manually via App Store Connect web or Xcode's Cloud tab (**Start Build**). Build numbers are auto-incremented by Xcode Cloud (`CURRENT_PROJECT_VERSION` in pbxproj remains static).

**SwiftLint build phase is skipped on Xcode Cloud**: The first line of the build phase detects `CI_XCODE_CLOUD=TRUE` and early-exits. This is because (1) the lint gate is already enforced by GitHub Actions, and (2) it avoids the overhead and warnings of running `brew install swiftlint` on every Xcode Cloud worker. It continues to run strictly in local builds and GitHub Actions.

## Module Layout

Folder names dictate roles. Refer to this table when deciding where code belongs:

| Directory | What belongs here | What does NOT belong here |
|---|---|---|
| `App/` | App entry point, shell, App Group constants | Business logic, domain models |
| `Models/` | SwiftData `@Model` (5 expense models + 7 budget/reconciliation models) | Non-SwiftData DTOs (those belong in `Services/`) |
| `Services/` | Business logic (OCR, extraction, save orchestration, domain helpers) | UI, file/system IO |
| `Storage/` | File, clipboard, and bookmark IO | Business decisions (what data to save belongs in `Services/`) |
| `Features/` | UI tab views + onboarding (SwiftUI) | System integrations (BGTask/Intent/Notification) → `System/` |
| `System/` | System integration points (BGTask, AppIntent, UNUserNotification) | SwiftUI views |

```
SnapLedger/                          # Main app target (synchronized root group)
  App/                               # App entry point
    SnapLedgerApp.swift              # @main, ModelContainer (groupContainer), BGTask register
    ContentView.swift                # TabView shell (Review/History/Statistics/Budget/Settings) + scenePhase observer + onboarding gate
                                     #            + Return to current month on Statistics/Budget tab reselection (resetNonce)
    AppGroup.swift                   # group.com.youngkyu.snapledger container / inbox URL
  Info.plist                         # Partial plist: BGTaskSchedulerPermittedIdentifiers + UIBackgroundModes
                                     #            + ITSAppUsesNonExemptEncryption
  SnapLedger.entitlements            # App Group
  AppIcon.icon / Assets.xcassets

  Models/                            # SwiftData @Model
    AppSettings.swift, ParsedEntry.swift, SavedEntry.swift, PendingImage.swift, MerchantCategory.swift
    AppSchema.swift                  # ModelContainer schema definition — separates cloudModels (CloudKit private DB source of truth) / localModels (App Group, intent sharing). Register new @Model here only
    # --- Budget & Reconciliation (Budget tab) ---
    CategoryBudget.swift             # Per-category monthly limit (auto-carries forward from effectiveFrom, monthlyLimit=0 is cancellation tombstone)
    MonthlyReconciliation.swift      # Monthly reconciliation header (monthKey + note). Amount items are split into separate models below
    IncomeItem.swift                 # Monthly income item (name + amount, sortOrder)
    CardUsageItem.swift              # Monthly card usage item (name + amount)
    SavingsItem.swift                # Monthly savings item (name + amount)
    AccountMonthlyBalance.swift      # Per-account starting/ending balance + interest
    CashAdjustment.swift             # Cash flow adjustments (inflow/outflow, name + amount + note) — co-located with CashAdjustmentDirection enum

  Services/                          # Business logic (fully unit-testable)
    OCRService.swift                 # protocol + VisionKitOCRService (Korean/English accurate)
    CandidateHeuristics.swift        # Payment signal scoring on OCR text (blocks hallucinations on scenery photos)
    ExtractionService.swift          # protocol + FoundationModelsExtractionService (dynamic prompt, multi-transaction)
    PaymentExtraction.swift          # @Generable PaymentExtraction(transactions:[Transaction])
    AppleIntelligenceStatus.swift    # FM availability → user-friendly copy (shared entry point for Settings/Onboarding/Review)
    PendingProcessor.swift           # @MainActor pipeline: reconcile inbox → OCR → heuristic → extract → ParsedEntry
    SaveCoordinator.swift            # Confirm review → CSV append + SavedEntry creation + category learning
    CategoryLearner.swift            # Merchant → category learning & lookup
    CategoryValidation.swift         # Determines if a category is off-list (warning only, pure)
    ImageImporter.swift              # Normalize imports from + menu (photos, clipboard, files, drop) → inbox
    CandidateAutoFill.swift          # Auto-fill category/amount by merchant on new review entry (pure)
    EntryReorder.swift               # Drag-and-drop item reordering → sortOrder recalculation (pure, shared with reconciliation items)
    EntrySaveValidation.swift        # Required field validation before saving review entry (pure)
    ReviewDateStatus.swift           # Flags dates outside normal range (today/yesterday) → tooOld/future warnings (pure, relative to entry.createdAt)
    SyncCoordinator.swift            # CSV one-way export orchestration (expenses + reconciliation + budget) + folder reachability check (isFolderReachable)
    SyncCoordinator+Files.swift      # Filename ↔ monthKey boundary helpers
    SyncCoordinator+Reconciliation.swift # Reconciliation CSV export & monthKeys (domain → ReconciliationCSV)
    SyncCoordinator+Budget.swift     # Budget CSV export & month range calculation (flattens carryover via resolveAll → BudgetCSV)
    SyncFileKind.swift               # Target export file type (.expenses / .reconciliation) distinction
    CSVFolderAccess.swift            # Storage folder bookmark resolution + reachability check wrapper
    CSVRowParser.swift               # Expense CSV row ↔ domain field parsing (shared between save & sync)
    CategoryBudgetStore.swift        # Category limit CRUD + effectiveLimit carryover calculation (monthKey helpers)
    ReconciliationStore.swift        # Monthly reconciliation draft load/save/delete, carry-forward, CSV row generation
    ReconciliationSummary.swift      # Reconciliation summary calculation (actual spending / recorded spending / discrepancy, isReconciled status) — pure

  Storage/                           # File, clipboard, and bookmark IO
    CSVWriter.swift                  # Monthly CSV based on NSFileCoordinator (BOM + header + escape)
    CSVParser.swift                  # Parser for History tab monthly CSV viewer
    BookmarkStore.swift              # Security-scoped bookmark creation & resolution
    FolderBookmarkHelper.swift       # BookmarkStore wrapper — applies URL → AppSettings.csvFolderBookmark
    ClipboardExporter.swift          # Exports review/history entries to TSV (+HTML) payload (for pasting into Numbers)
    ReconciliationCSV.swift          # Monthly reconciliation CSV (reconciliations-YYYY-MM.csv) writer/parser — AI-friendly export
    BudgetCSV.swift                  # Monthly budget CSV (budgets-YYYY-MM.csv) writer (category, limit) — AI-friendly export

  Features/                          # UI views
    MonthNavigationRow.swift         # ◀ Current Month (menu) ▶ month selection row (shared across Budget & Statistics tabs)
    Review/                          # ReviewListView (+ menu, drop zone, badge, processing indicator), EntryEditorView (chip row + ReviewDateStatus date warning icon),
                                     #            BudgetToastView (bottom floating toast on budget threshold during review save), FailedImagesSection, InboxImage
    History/                         # HistoryView (@Query SavedEntry, daily sections + .searchable), SavedEntryEditorView,
                                     # CSVFileView (monthly table viewer + multi-select copy/share), HistoryGrouping, EntrySearch (pure — partial match for merchant/category/note + exact match for amount)
    Statistics/                      # StatisticsView (category donut chart + month-over-month trend), StatisticsAggregation (pure),
                                     # CategoryColor (pure), CategoryEntriesSheet (donut slice tap → category entries list)
    Budget/                          # BudgetView (month selector → reconciliation entry + category limit progress), BudgetProgress (pure: usage vs. limit),
                                     # MonthlyReconciliationView (inputs for income/cards/savings/balances/cash flow + salary masking),
                                     # ReconciliationEditors (account/item editor rows), ReconciliationVerdict+Color (status/discrepancy colors)
    Settings/                        # SettingsView (storage folder row = folder name → storage folder view / reminder / FM status),
                                     # AdvancedSettingsView (categories / extraction guide), CategoryEditorView (preset add/delete/reorder),
                                     # AboutView, FolderPicker, FeedbackMail (pure), MailComposeSheet
    Sync/                            # FileSyncView (storage folder view = Export All + Change Folder)
    Onboarding/                      # OnboardingView + ValuePage/SetupPage + AppearStep/PermissionAction (pure)

  System/                            # System integrations (not views)
    Background/BackgroundRefresh.swift          # BGAppRefreshTask
    Intents/AddExpenseFromImageIntent.swift     # AppIntent (Spotlight/Siri)
    Intents/SnapLedgerShortcuts.swift           # AppShortcutsProvider
    Notifications/NotificationScheduler.swift   # UNUserNotification wrapper
    Notifications/ReminderContent.swift         # pure: time/count → body & single-fire trigger
    Notifications/ReminderRefresher.swift       # Reschedules/clears notifications from settings & pending count (shared by ContentView & BGTask)

SnapLedgerShareExtension/            # Share Extension target (synchronized root group, separate)
  ShareViewController.swift          # Silent UIVC, copies NSItemProvider images to App Group inbox
  Info.plist                         # Explicit plist: NSExtensionPrincipalClass, image-only activation
  SnapLedgerShareExtension.entitlements   # App Group

SnapLedgerTests/                     # Swift Testing — mirrors source structure
  Models/    Services/    Storage/    Features/    System/
```

## Key Architectural Decisions

1. **Share Sheet → Inbox File → Main App Reconcile**
   The Share Extension does not create `PendingImage` rows directly. It only writes files to `App Group container/inbox/` and dismisses. The main app reconciles the inbox on launch, foreground transition, or BGTask execution via `PendingProcessor.reconcileInbox`, creating `PendingImage` rows for any unmapped files. This design avoids sharing `.swift` files across target memberships under Xcode 16 `PBXFileSystemSynchronizedRootGroup` — the extension only needs an inline App Group identifier constant without depending on SwiftData.

2. **Guard Foundation Models**
   Always check `FoundationModelsExtractionService.isAvailable`. If unavailable, processing drains are skipped entirely (`ContentView.drainPending`, `BackgroundRefresh.handle`), and `AddExpenseFromImageIntent` gracefully degrades with an "Added to queue" message. Note that Apple Intelligence may be unavailable in simulators, requiring on-device testing.

3. **All SwiftData Containers Use Group Container**
   `ModelConfiguration(schema: schema, groupContainer: .identifier(AppGroup.identifier))`. Both the main app and AppIntents share and inspect the exact same store.

4. **Extraction Accuracy via Prompt + User Guide**
   `FoundationModelsExtractionService.instructions(today:customGuide:categories:)` is the single source of truth. Explicitly defines payment notification patterns (`<amount>원 일시불`) and forbidden secondary amounts (`누적`, `잔액`, `한도`, `포인트`, etc.). `@Guide` delegates to instructions (no hardcoding). When users specify custom guides in Settings, they are appended to the end of the prompt under "User Guide (takes precedence over rules above)".

5. **Dynamic Category List**
   `AppSettings.categoryPresets` (user-editable) is injected directly into the prompt. The model is soft-constrained to pick from this list.

6. **CSV Writes Protected by NSFileCoordinator**
   `CSVWriter.append` uses `.forMerging` for cross-process safety. BOM and header are written only on the first call when creating the file. Monthly files follow `expenses-YYYY-MM.csv`.

7. **CSV is a One-Way Export Backup (`SyncCoordinator`) — CloudKit as Source of Truth (Phases 1–4)**
   CloudKit-backed SwiftData is the sole source of truth for all persistent data. CSVs are **export-only backups across 3 kinds (expenses, reconciliation, budget)**, not a source of truth. Consequently, file-to-app import, external modification detection, conflict resolution UI, `CSVFileState` fingerprints, and `FileFingerprint` have all been removed.
   - **Export (App → File)**: Save, edit, delete, and reorder operations trigger a **best-effort** rewrite of the affected month's CSV. If no folder is configured or writing fails, the commit remains successful — `SaveCoordinator.exportEntryBestEffort` (expenses + that month's budget) / `ReconciliationStore.exportBestEffort` (reconciliation + that month's budget) / `CategoryBudgetStore.exportBestEffort` (budget edits). CSV export is completely optional, so data remains secure in CloudKit even without a configured folder.
   - **Entry Point**: **Settings → Storage Folder row** → `FileSyncView` ("Storage Folder"). Offers **Export All** (`SyncCoordinator.exportAll`, backfilling all app months for expenses, reconciliations, and budgets into the folder) and **Change Folder**. Selecting a new folder automatically runs a full backfill export.
   - **Deleted / Moved Folder Handling**: Even if a security-scoped bookmark resolves, the physical directory may no longer exist → verified via `SyncCoordinator.isFolderReachable` (`BookmarkStore.isReachableDirectory`). `FileSyncView` presents a "Folder not found + Change Folder" banner. Export routines quietly skip missing/unreachable folders (best-effort).

8. **Category Budgets Auto-Carry Forward via `effectiveFrom` (`CategoryBudget` / `CategoryBudgetStore`)**
   Budgets do not create rows for every month. `CategoryBudget(category, monthlyLimit, effectiveFrom)` automatically repeats each month from `effectiveFrom` until the next change. The effective limit for a month is the latest row where `effectiveFrom <= month` (`CategoryBudgetStore.resolveLimit`). Clearing a limit is represented by a `monthlyLimit = 0` tombstone starting in that month (preserving historical limits). The Budget tab restricts navigation to months up to the current month because future months are not locked.
   - **Budget CSV is a Monthly Effective Limit Snapshot (`budgets-YYYY-MM.csv`)**: Header `카테고리,한도`, UTF-8 with BOM. `CategoryBudgetStore.resolveAll` flattens carryover at export time and writes only categories with an effective limit > 0 in preset order (off-list items alphabetical at the end). One-way best-effort export (piggybacking on expense/reconciliation saves and budget edits; `SyncCoordinator.exportAll` backfills `[earliest effectiveFrom ... current month]`). Does not store actual spending or usage percentages — AI calculates those by joining with `expenses-*.csv`. If a month has no active limits, no file is written and any existing file is deleted.

9. **Monthly Reconciliation Splits Header + Item Models, Round-Trips to CSV (`MonthlyReconciliation` + 5 item models / `ReconciliationStore` / `ReconciliationCSV`)**
   A monthly reconciliation uses `MonthlyReconciliation` (monthKey + monthly note) as the header, with amounts split into `IncomeItem`, `CardUsageItem`, `SavingsItem`, `AccountMonthlyBalance`, and `CashAdjustment`. On entering the view, `ReconciliationStore.carryForwardDraft` prefills stable values from the prior month (account names & baseline balance, income/savings names + amounts; cards and adjustments prefill names with 0 amounts).
   - **Summary and Verdict Centralized in `ReconciliationSummary` (pure)**: Calculates `actualSpending`, `recordedSpending`, difference, and `isReconciled(status:)` in one place so the Budget tab and reconciliation view reach identical conclusions. An in-progress month is considered "in progress" only after the user enters actual numbers (closing balance != opening balance, or card usage); prior to that, `actualSpending` is gated to 0 to prevent prefill noise. Closed past months are finalized if saved data exists.
   - **Reconciliation CSV is AI-Friendly + Lossless Round-Trip (`reconciliations-YYYY-MM.csv`)**: 6 columns `종류,항목,계좌,방향,금액,메모`, UTF-8 with BOM, RFC 4180 escaping. Designed to be self-describing in Korean since the primary consumer is AI — no date column (all reconciliation models are month-scoped), account balances unfold into opening/closing/interest rows, and monthly note is preserved with type `월메모`. One-way export-only (`SyncCoordinator+Reconciliation.exportReconciliationMonths`, best-effort), identical to expense CSV.

## Conventions

- **No File Headers**: New `.swift` files must start directly with `import` without header comments (`// FileName.swift\n// Target\n// Created by...`). Remove any template header blocks immediately.
- **Code Comments in English & Concise**: Write comments in English only where truly necessary. Describe only what the code directly does, avoiding verbose cross-references to other types, files, or historical designs. Prefer a single line by default; multiple lines are acceptable if strictly needed, but if an explanation becomes lengthy, document it in `AGENTS.md` instead of code comments.
- **Use Swift Testing**: New unit tests must use `import Testing`, `@Test`, and `#expect`. XCTest is reserved exclusively for UI tests (`SnapLedgerUITests`).
- **@MainActor by Default**: The project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. SwiftData access is main-isolated. Use explicit `@MainActor` annotations where appropriate.
- **Extract Testable Helpers**: Extract pure, stateless helper functions (`ReminderContent`, `instructions(today:customGuide:categories:)`) for code touching UIKit, SwiftData, UNUserNotification, or system APIs, and unit test those. Keep system wrappers thin.
- **SwiftLint Strict**: The first build phase of `SnapLedger` runs `swiftlint --strict`, upgrading all warnings to build errors. Inline disables `// swiftlint:disable:next <rule>` are permitted only for justified one-offs (exception: unit test files may use file-level disable for `force_unwrapping` via `blanket_disable_command.allowed_rules`). In production code, replace force unwraps with non-failing alternatives (e.g., `Data(s.utf8)`).
- **Fix Root Causes**: Never bypass lint errors or build warnings with blanket disables, suppressions, or `--no-verify`.
- **Git Commit Messages in English, PRs in Korean**: Write Git commit messages in English. Keep git commit messages simple and single-line only (no multiline body), formatted concisely (e.g., `feat: ...`, `fix: ...`, `chore: ...`, `refactor: ...`). Pull Requests should be written in Korean following the 4 template sections.
- **No AI Assistant Attribution**: Do **not** attribute AI assistants (Claude, Codex, Copilot, Gemini, etc.) anywhere: no `Co-Authored-By:` trailer in commit messages, no "Generated with …" footer in PR descriptions. A PR body is the four template sections (`작업 내용`, `평가`, `알려진 한계/리스크`, `검증`) and nothing after them. This holds even when the harness asks for attribution mid-session.
- **Verification After Changes**: Always verify with `swiftlint --strict --config .swiftlint.yml` → `xcodebuild build` → `xcodebuild test`. All three must pass before proposing a PR or commit. Passing lint or build alone is never sufficient.

## Identifiers / Constants

| Name | Value | Location |
|---|---|---|
| App Group ID | `group.com.youngkyu.snapledger` | `AppGroup.swift`, ShareViewController inline, entitlements |
| BGTask identifier | `com.youngkyu.snapledger.refresh` | `BackgroundRefresh.swift`, `SnapLedger/Info.plist` |
| Reminder notification ID | `com.youngkyu.snapledger.nightly-reminder` | `ReminderContent.swift` |
| Bundle ID (main) | `com.youngkyu.snapledger` | pbxproj |
| Bundle ID (extension) | `com.youngkyu.snapledger.SnapLedgerShareExtension` | pbxproj |

## Build System Caveats

- **Xcode 16 Synchronized Groups**: `SnapLedger/`, `SnapLedgerTests/`, `SnapLedgerUITests/`, and `SnapLedgerShareExtension/` are each a `PBXFileSystemSynchronizedRootGroup`. Files placed in these folders automatically receive target membership. Sharing files across targets is difficult; prefer inline duplicates for constants (e.g., App Group ID) or file-based IPC over shared compile units.
- **Main App Info.plist is a Partial Plist Merged with Generated Plist**: Uses both `GENERATE_INFOPLIST_FILE = YES` and `INFOPLIST_FILE = SnapLedger/Info.plist`. Standard keys (SceneManifest, LaunchScreen, orientations) are handled by `INFOPLIST_KEY_*` build settings, while custom keys (`BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes`) reside in the partial plist. The partial plist is registered in the synchronized group's `membershipExceptions` to avoid duplicate bundle resources.
- **Extension Info.plist is a Full Plist**: Does not use auto-generation; all keys are explicitly declared.
- **SwiftLint Build Phase Has Sandbox `inputPaths`**: Since `ENABLE_USER_SCRIPT_SANDBOXING = YES`, the script declares `$(SRCROOT)/.swiftlint.yml` and the 4 source roots (`SnapLedger`, `SnapLedgerShareExtension`, `SnapLedgerTests`, `SnapLedgerUITests`) as inputPaths. If a new source root directory is added, this list must be updated. xattr sandbox warnings are harmless (actual file reads succeed).

## Frequently Used Verification Commands

```bash
# Verify Info.plist keys immediately after build
plutil -p /Users/youngkyu/Library/Developer/Xcode/DerivedData/SnapLedger-*/Build/Products/Debug-iphonesimulator/SnapLedger.app/Info.plist

# Check simulator App Group inbox (verify files dropped by Share Extension)
xcrun simctl get_app_container booted com.youngkyu.snapledger groups
ls "$(xcrun simctl get_app_container booted com.youngkyu.snapledger groups | awk '{print $2}')/inbox/"

# Force trigger BGTask (LLDB on booted app)
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.youngkyu.snapledger.refresh"]
```

## Known Limitations (Intentional, Verify Before Modifying)

- If Foundation Models is unavailable on the simulator, inbox processing drain is skipped entirely and the Review tab appears empty. Inbox files remain queued and are processed on real devices.
- Reminder notification copy is baked-in with the pending count at the time of scheduling (iOS local notifications cannot recompute copy at trigger time). Mitigation: schedules only the **next single occurrence** (`ReminderContent.trigger`) rather than a recurring trigger, and reloads on all app activity opportunities (scenePhase `.active`/`.background`, BGTask) via `ReminderRefresher.refresh`. Force-quitting the app suspends BGTask, allowing at most one stale notification — acceptable under iOS constraints.
- Share Extension UI may have its detent hint (`preferredContentSize`) ignored by some host apps. Works properly in standard system hosts (Photos, Safari, Messages).
