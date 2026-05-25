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
| Apple ID | `6772852897` |
| SKU | `snapledger-001` |
| Primary Language | Korean |
| Version | 1.0 |
| Build | 1 |
| Copyright | `2026 YOUNGKYU SEO` (©는 시스템이 자동 부착) |
| Primary Category | Finance |
| Secondary Category | Productivity |
| Pricing | Free, In-App Purchase 없음 |
| Availability | South Korea (1차) |
| Age Rating | 4+ |
| Support URL | `https://youngkyulabs.github.io/snap-ledger-ios/support.html` |
| Privacy Policy URL | `https://youngkyulabs.github.io/snap-ledger-ios/privacy-policy.html` |
| Marketing URL | (없음) |
| EULA | Apple Standard EULA |

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

## 3. App Privacy

App Store Connect "App Privacy" 섹션:

**Does this app collect data? → No (Data Not Collected)**

근거:
- 분석/광고 SDK 없음, 네트워크 호출 없음
- OCR(VisionKit) / 추출(Foundation Models) 모두 온디바이스
- 사용자 데이터는 사용자가 직접 지정한 iCloud Drive 폴더의 CSV에만 저장
- Share Extension은 App Group inbox 파일 IO만 함

### Privacy Manifest (`PrivacyInfo.xcprivacy`)

메인 앱(`SnapLedger/PrivacyInfo.xcprivacy`)과 익스텐션(`SnapLedgerShareExtension/PrivacyInfo.xcprivacy`) 둘 다 번들에 포함됨. 공통:

- `NSPrivacyTracking = false`, `NSPrivacyTrackingDomains = []`, `NSPrivacyCollectedDataTypes = []`
- Required Reason API: `NSPrivacyAccessedAPICategoryFileTimestamp` (reasons `C617.1`, `3B52.1` — CSV append 시 mtime 비교용)

새 시스템 API를 도입할 때 (예: UserDefaults, DiskSpace) 양쪽 `.xcprivacy`에 동시 추가 필요.

---

## 4. Review Information (심사팀 메모)

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
```

샘플 결제 알림 스크린샷 3장을 review attachments로 같이 업로드.

---

## 변경 이력

| 버전 | 날짜 | 비고 |
|---|---|---|
| 1.0 (b1) | 2026-05-24 작성 | 첫 제출 |
