# App Store 제출 메타데이터

찰칵가계부 1.0 (build 1) App Store Connect 제출용 메타데이터.
업데이트 시 이 문서를 single source of truth로 유지한다.

---

## 1. 기본 정보

| 항목 | 값 |
|---|---|
| App Name (한국어) | 찰칵가계부 |
| App Name (English) | SnapLedger |
| Bundle ID | `com.youngkyu.snapledger` |
| SKU | `snapledger-ios-001` |
| Primary Language | Korean |
| Version | 1.0 |
| Build | 1 |
| Copyright | `2026 박영규` (개인 계정 기준 실명, ©는 시스템이 자동 부착) |
| Primary Category | Finance |
| Secondary Category | Productivity |
| Pricing | Free, In-App Purchase 없음 |
| Availability | South Korea (1차) |
| Age Rating | 4+ |

---

## 2. App Store 표시 텍스트 (한국어)

### Subtitle (최대 30자)
```
스크린샷이 한 줄 가계부로
```

### Promotional Text (최대 170자, 심사 없이 수시 변경 가능)
```
카드 결제 알림 스크린샷이나 영수증을 공유 시트로 보내기만 하면 끝. Apple Intelligence가 금액·가맹점·카테고리를 자동으로 채워 가계부에 정리해줍니다.
```

### Keywords (최대 100자, 콤마 구분, 공백 없이)
```
가계부,영수증,스크린샷,결제알림,자동입력,지출관리,CSV,월별,카드내역,AI가계부
```

### Description (최대 4000자)
```
찰칵가계부는 결제 알림이나 영수증을 사진 한 장으로 가계부에 옮기는, 한국 사용자를 위한 iOS 26 가계부입니다.

■ 이렇게 동작해요
1. 카드사 결제 알림을 캡쳐하거나 영수증을 찍습니다.
2. 공유 시트에서 "찰칵가계부"를 선택합니다.
3. Apple Intelligence가 금액·가맹점·날짜·카테고리를 자동으로 뽑아냅니다.
4. 검토 탭에서 한 번 확인하고 저장하면 끝.

■ 주요 기능
• 한 장의 이미지에서 여러 건의 결제도 한 번에 추출
• 가맹점 → 카테고리 자동 학습 (한 번 고치면 다음부터 기억)
• 사용자 지정 iCloud Drive 폴더에 월별 CSV(expenses-YYYY-MM.csv,
  날짜·설명·카테고리·금액·메모 5열)로 저장 — Numbers, Excel, 다른 가계부로 이동 자유
• 최근 기록 탭에서 월별로 묶어 보기, 스크롤하면 과거 달이 자동으로 이어짐.
  다중 선택 후 Numbers·메일로 바로 붙여넣기
• 통계 탭의 카테고리 도넛과 전월 대비 비교
• 항목마다 자유 메모 (할인 사유, 동행자, 영수증 번호 등)
• 매일 저녁 검토 알림과 아이콘 뱃지로 빠뜨림 방지
• 사진 라이브러리, 클립보드, 파일, 드래그&드롭, 직접 입력까지 모든 입력 경로 지원
• 추출 규칙을 직접 보강할 수 있는 "추출 가이드"

■ 프라이버시
• 모든 인식과 추출은 기기 안에서 처리됩니다. 결제 정보가 서버로 전송되지 않습니다.
• 데이터는 사용자가 직접 지정한 iCloud Drive 폴더의 CSV 파일로만 저장됩니다. 언제든지 파일을 가져가거나 삭제할 수 있습니다.
• 광고·분석 SDK가 없습니다.

■ 동작 요구 사항
• iOS 26 이상
• Apple Intelligence 지원 기기 및 한국어 설정 권장 (미지원 기기에서는 추출이 비활성화됩니다)
• 일부 기능은 iCloud Drive 사용을 권장합니다.

■ 의도된 한계
• 시뮬레이터 또는 Apple Intelligence가 비활성화된 환경에서는 자동 추출이 동작하지 않습니다.
• 인식 결과는 항상 검토 화면에서 한 번 확인한 뒤 저장됩니다.

피드백은 설정 → 의견 보내기에서 직접 보내주세요. 빠르게 반영하겠습니다.
```

### What's New in This Version (1.0 출시 노트)
```
첫 출시입니다. 결제 알림 스크린샷을 공유 시트로 보내면 Apple Intelligence가 가계부에 자동으로 옮겨 적습니다.
```

---

## 3. 영어 메타데이터 (1.0에서는 비활성, 글로벌 출시 시 추가)

### Subtitle
```
Receipts to ledger, instantly
```

### Keywords
```
budget,expense,receipt,screenshot,ledger,finance,ocr,csv,apple intelligence,tracker
```

### Description
```
SnapLedger turns Korean credit-card notification screenshots and receipt photos into a clean expense ledger — on device.

How it works
1. Capture a payment notification or receipt.
2. Send it to SnapLedger from the share sheet.
3. Apple Intelligence extracts the amount, merchant, date, and category.
4. Review once, save, done.

Highlights
• Multiple transactions per image
• Merchant-to-category learning that improves with each correction
• Monthly CSV (expenses-YYYY-MM.csv, 5 columns: date, description, category, amount, note)
  saved to a folder you choose in iCloud Drive — open in Numbers, Excel, or anywhere
• Recent-history tab grouped by month with infinite scroll, multi-select copy for Numbers and email
• Category donut and month-over-month comparison
• Free-form note per entry
• Nightly review reminder and badge so nothing slips
• Photo Library, clipboard, Files, drag & drop, manual entry — every input path supported

Privacy
• All recognition and extraction run on device. Your payment data never leaves your iPhone.
• Entries live only in the CSV folder you choose; export or delete anytime.
• No ads. No analytics SDKs.

Requirements
• iOS 26
• Apple Intelligence–capable device recommended (extraction disables on unsupported devices)

Designed and optimized for Korean credit-card notification formats.
```

---

## 4. App Privacy

App Store Connect "App Privacy" 섹션:

**Does this app collect data? → No (Data Not Collected)**

근거:
- 분석/광고 SDK 없음, 네트워크 호출 없음
- OCR(VisionKit) / 추출(Foundation Models) 모두 온디바이스
- 사용자 데이터는 사용자가 직접 지정한 iCloud Drive 폴더의 CSV에만 저장
- Share Extension은 App Group inbox 파일 IO만 함

### Privacy Manifest (`PrivacyInfo.xcprivacy`)

아직 없으면 추가 권장. Required Reason API 후보:
- `NSPrivacyAccessedAPICategoryFileTimestamp` — CSV 작성/검사
- `NSPrivacyAccessedAPICategoryDiskSpace` — CSV append
- `NSPrivacyAccessedAPICategoryUserDefaults` — 사용 여부 확인 후

---

## 5. Usage Description (Info.plist)

현재 `SnapLedger/Info.plist`에 권한 설명 키 없음. 코드 경로 점검 후 필요 시 추가.

| 키 | 필요 여부 | 권장 문구 |
|---|---|---|
| `NSPhotoLibraryUsageDescription` | PHPicker만 쓰면 불필요. PHAsset 직접 접근 시 필수 | "사진 라이브러리에서 결제 알림 스크린샷이나 영수증을 불러옵니다." |
| `NSPhotoLibraryAddUsageDescription` | 현재 미사용 (앱이 사진 저장하지 않음) | — |
| `NSUserTrackingUsageDescription` | 절대 추가 금지 (ATT 다이얼로그 뜸) | — |

알림 권한은 Usage Description 키가 필요 없음 (시스템 다이얼로그 자체 처리).

---

## 6. URL 항목

| 항목 | 필수 | 상태 |
|---|---|---|
| Support URL | 필수 | **미정** — 정적 페이지 호스팅 필요 (GitHub Pages 등) |
| Marketing URL | 선택 | 미정 |
| Privacy Policy URL | 필수 | **미정** — "데이터 수집 없음" 1페이지로 충분 |
| EULA | 선택 | Apple Standard EULA 사용 권장 |

---

## 7. Review Information (심사팀 메모)

```
Sign-in required: No

Notes to reviewer:
SnapLedger requires Apple Intelligence (iOS 26 on supported devices, Korean
display language recommended) for automatic extraction. On unsupported
hardware, the Review tab will show a friendly notice and queued items will
not be processed automatically — this is intentional, documented in the
onboarding screen, and items can still be added manually.

To exercise the extraction flow:
1. Open Photos. Save the attached sample image (Korean card-payment
   notification screenshot).
2. From the Photos share sheet, choose "찰칵가계부".
3. Open SnapLedger. The Review tab will show the extracted transaction.
4. Tap "저장" to commit. A row will be appended to
   expenses-YYYY-MM.csv inside the iCloud Drive folder selected
   during onboarding. CSV columns: date, description, category, amount, note.

The app does not require network access. All processing happens on device.
There is no account, no purchase, no advertising.

Contact: <your email>
```

샘플 결제 알림 스크린샷 1~2장을 review attachments로 같이 업로드 권장.

---

## 8. 스크린샷 가이드

iOS 26 기준 필수 사이즈:
- **6.9" (iPhone 17 Pro Max / 16 Pro Max)** — 1290 × 2796 — **필수**
- **iPad 13" (M4)** — 2064 × 2752 — iPad 출시 시 필수
- 6.5" / 6.7" 등 레거시는 6.9" 제출 시 자동 스케일링

권장 5장 (한국어):
1. 온보딩 가치 페이지 — "결제 알림을 자동으로 가계부에" + 카메라 아이콘 + AI 상태 뱃지
2. 공유 시트 → 검토 탭 — 카드 알림 스크린샷이 검토 항목으로 들어온 화면 (chip row 보이게)
3. 편집 화면 — 카테고리 chip row, 금액 후보 chip row, 메모 필드
4. 통계 탭 — 카테고리 도넛 + 전월 대비
5. 최근 기록 탭의 월별 CSV 뷰 — 한 달 지출이 깔끔하게 정리된 표

캡션은 스크린샷 위에 한 줄 오버레이 추천.

---

## 9. 제출 전 체크리스트

### 빌드/설정
- [x] `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`
- [x] `ITSAppUsesNonExemptEncryption = NO` (SnapLedger/Info.plist:9)
- [x] App Group entitlement (`group.com.youngkyu.snapledger`)
- [x] BGTaskSchedulerPermittedIdentifiers
- [ ] Privacy Manifest (`PrivacyInfo.xcprivacy`) 추가
- [ ] `NSPhotoLibraryUsageDescription` 필요 여부 점검 (ImageImporter 경로 확인)

### 미정 항목
- [ ] Copyright 최종 표기 (한글 vs 영문)
- [ ] Support URL 호스팅 위치
- [ ] Privacy Policy URL 호스팅 위치
- [ ] 영문 메타데이터 활성화 여부 (1.0은 비활성 권장)
- [ ] Review 샘플 스크린샷 (한국 카드사 알림 1~2장) 준비

### App Store Connect 작업
- [ ] App Privacy 응답 (Data Not Collected)
- [ ] Age Rating 설문 완료 (4+)
- [ ] 스크린샷 5장 업로드 (6.9")
- [ ] 메타데이터 입력
- [ ] Review Information 입력 + 샘플 첨부
- [ ] Build 업로드 (Xcode Organizer)
- [ ] Export Compliance: "Uses encryption? → No" (ITSAppUsesNonExemptEncryption=NO와 일치)
- [ ] Submit for Review

---

## 변경 이력

| 버전 | 날짜 | 비고 |
|---|---|---|
| 1.0 (b1) | 2026-05-24 작성 | 첫 제출 |
