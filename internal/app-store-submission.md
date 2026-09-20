# App Store 제출 메타데이터

찰칵가계부 App Store Connect 제출용 메타데이터 (현재 버전 1.4).
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
| Version | 1.4 |
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
찰칵가계부는 결제 알림이나 영수증을 사진 한 장으로 가계부에 옮기는, 한국 사용자를 위한 가계부입니다.

■ 이렇게 동작해요
1. 카드사 결제 알림을 캡쳐하거나 영수증을 찍습니다. 문자·메신저로 온 알림이라면 문구를 그대로 선택해도 됩니다.
2. 공유 시트에서 "찰칵가계부"를 선택합니다.
3. Apple Intelligence가 금액·가맹점·날짜·카테고리를 자동으로 뽑아냅니다.
4. 검토 탭에서 한 번 확인하고 저장하면 끝.

■ 주요 기능
• 한 장의 이미지에서 여러 건의 결제도 한 번에 추출
• 스크린샷 없이도 OK — 문자·메신저의 결제 알림 문구를 선택해 공유하면 그대로 추출
• 가맹점 → 카테고리 자동 학습 (한 번 고치면 다음부터 기억)
• 데이터는 본인 iCloud 계정에 안전하게 저장되어 여러 기기에서 자동으로 이어 보기
• 원하면 iCloud Drive 폴더에 월별 CSV(지출·정산·예산 3종)로 자동 백업
  — expenses-YYYY-MM.csv(날짜·설명·카테고리·금액·메모 5열) 외 정산·예산도 함께,
  Numbers, Excel, 다른 가계부로 이동 자유
• 최근 기록 탭에서 월별로 묶어 보기, 스크롤하면 과거 달이 자동으로 이어짐.
  가맹점·카테고리·메모·금액으로 검색, 다중 선택 후 Numbers·메일로 바로 붙여넣기
• 월 정산 → 예산 진행률 → 카테고리 비중 도넛 → 월별 추세까지 한 화면에 이어지는 월간 요약 탭
• 카테고리별 월 예산 한도와 사용률 진행률 (한도는 매월 자동 이월)
• 수입·카드(이번 달 사용액 + 이번 달 빠져나간 전월 카드대금)·저축·계좌 잔액을 입력해 '실제 쓴 돈'과 '기록한 돈'을 맞춰보는 월 정산
• 항목마다 자유 메모 (할인 사유, 동행자, 영수증 번호 등)
• 매일 저녁 검토 알림과 아이콘 뱃지로 빠뜨림 방지
• 사진 라이브러리, 클립보드, 파일, 드래그&드롭, 직접 입력까지 모든 입력 경로 지원
• 추출 규칙을 직접 보강할 수 있는 "추출 가이드"

■ 프라이버시
• 모든 인식과 추출은 기기 안에서 처리됩니다. 결제 정보가 Apple 외부 서버로 전송되지 않습니다.
• 데이터는 본인 iCloud 계정(CloudKit)에만 저장되어 기기 간 동기화됩니다. 선택 사항인 iCloud Drive 폴더 백업(CSV)은 원할 때만 켜며, 언제든 폴더를 해제하거나 파일을 가져가고 삭제할 수 있습니다.
• 광고·분석 SDK가 없습니다.

■ 동작 요구 사항
• iOS 26 이상
• Apple Intelligence 지원 기기 및 한국어 설정 권장 (미지원 기기에서는 추출이 비활성화됩니다)
• 기기 간 동기화에는 iCloud 로그인이 필요합니다. CSV 백업은 iCloud Drive 사용을 권장합니다.

■ 의도된 한계
• 시뮬레이터 또는 Apple Intelligence가 비활성화된 환경에서는 자동 추출이 동작하지 않습니다.
• 인식 결과는 항상 검토 화면에서 한 번 확인한 뒤 저장됩니다.

피드백은 설정 → 의견 보내기에서 직접 보내주세요. 빠르게 반영하겠습니다.
```

### What's New in This Version (1.4 출시 노트)
```
• 문자로 온 결제 알림도 그대로 — 스크린샷을 찍지 않아도, 메시지·메신저에서 알림 문구를 선택해 공유 시트로 보내면 바로 기록됩니다.
• 월간 요약 탭 — 흩어져 있던 예산과 통계를 한 탭으로 합쳤어요. 월 정산부터 전체 진행률, 카테고리 비중, 월별 추세까지 한 스크롤로 이어지고, 진행률이나 도넛을 누르면 카테고리별로 더 파고들 수 있어요. 지난 달을 고르면 추세 그래프도 그 달에 맞춰 움직입니다.
• 월 정산에 전월 카드대금 칸 — 이번 달에 빠져나간 지난달 카드값을 카드별로 적을 수 있고, 지난달 사용액이 기본값으로 채워집니다.
• 정산을 마친 달에 지출을 추가하면 저장 전에 한 번 짚어줍니다.
• 검토·최근 기록 화면 정리 — 카테고리는 캡슐, 메모는 말풍선 아이콘으로 한눈에 구분돼요.
• 연도가 적혀 있지 않은 알림을 작년 날짜로 잘못 기록하던 문제를 고쳤어요.
```

#### 이전 버전 노트
```
1.3 — 최근 기록을 가맹점·카테고리·메모·금액으로 검색할 수 있게 됐고, 검토 화면이 오래됐거나 미래로 잡힌 날짜를 경고 아이콘으로 짚어줍니다. 자동 추출 정확도(날짜 환각·과분할·지운 카테고리)도 개선됐습니다.
1.2.1 — 지출을 저장하면 그 카테고리가 이번 달 예산의 80%에 닿거나 초과했을 때 검토 화면 아래에 토스트로 알려줍니다(별도 권한 없이 앱 안에서만).
1.2 — iCloud 동기화가 추가됐습니다. 가계부·예산·정산 데이터가 본인 iCloud 계정에 저장되어 새 기기에서도 이어 쓸 수 있고, 월별 CSV는 백업·내보내기 전용이 됐습니다(예산도 budgets-YYYY-MM.csv로 함께 내보내짐).
1.1 — 예산 탭(카테고리별 월 한도)과 월 정산('실제 쓴 돈' vs '기록한 돈' 대조)이 추가됐습니다.
1.0 — 첫 출시입니다. 결제 알림 스크린샷을 공유 시트로 보내면 Apple Intelligence가 가계부에 자동으로 옮겨 적습니다.
```

---

## 3. App Privacy

App Store Connect "App Privacy" 섹션:

**Does this app collect data? → No (Data Not Collected)**

근거:
- 분석/광고 SDK 없음, 자체 서버로의 네트워크 호출 없음
- OCR(VisionKit) / 추출(Foundation Models) 모두 온디바이스
- 사용자 데이터는 본인 iCloud 계정의 CloudKit private database에 저장 — 개발자가 접근할 수 없는 사용자 전용 저장소이므로 "수집(collect)"에 해당하지 않음. 선택적 CSV 백업도 사용자가 지정한 iCloud Drive 폴더에만 떨어짐
- Share Extension은 App Group inbox 파일 IO만 함

### Privacy Manifest (`PrivacyInfo.xcprivacy`)

메인 앱(`SnapLedger/PrivacyInfo.xcprivacy`)과 익스텐션(`SnapLedgerShareExtension/PrivacyInfo.xcprivacy`) 둘 다 번들에 포함됨. 주요 항목:

- `NSPrivacyTracking = false`, `NSPrivacyTrackingDomains = []`, `NSPrivacyCollectedDataTypes = []`
- Required Reason API: `NSPrivacyAccessedAPICategoryFileTimestamp` (메인 앱 reasons `C617.1`·`3B52.1`, 익스텐션 reason `C617.1` — CSV export(파일 쓰기)·inbox 파일 처리 시 파일 메타 접근용)

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
2. From the Photos share sheet, choose "찰칵가계부". (The share extension also
   accepts plain text, so a card-payment notification copied from Messages can
   be shared directly without a screenshot.)
3. Open SnapLedger. The Review tab will show the extracted transaction.
4. Tap "저장" to commit. The entry is stored in the user's private
   iCloud (CloudKit) database and syncs across the user's devices.
   If a storage folder was selected, the month's CSV
   (expenses-YYYY-MM.csv; columns: date, description, category, amount, note)
   is also exported as a one-way backup — this folder is optional.

OCR and extraction run entirely on device (no network). Data is stored only
in the user's own private CloudKit database; the app uses no developer server.
There is no account sign-up, no purchase, no advertising.
```

샘플 결제 알림 스크린샷 3장을 review attachments로 같이 업로드.

---

## 변경 이력

| 버전 | 날짜 | 비고 |
|---|---|---|
| 1.0 | 2026-05-24 작성 | 첫 제출 |
| 1.1 | 2026-06-14 갱신 | 예산 탭(카테고리 한도) + 월 정산 + 정산 CSV 추가 |
| 1.2 | 2026-06-22 갱신 | CloudKit 전환 — iCloud(CloudKit private DB)가 진실원, 기기 간 동기화. CSV는 한 방향 export 백업으로 격하(파일→앱 import·외부 변경 감지·충돌 제거) |
| 1.2 | 2026-06-25 갱신 | 예산 CSV(budgets-YYYY-MM.csv) export 추가 — 추출물 3종(지출·정산·예산) |
| 1.2.1 | 2026-06-28 갱신 | 검토 저장 시 예산 임계(80%/초과) 하단 플로팅 토스트 표시 (검토 탭, 권한 불필요) |
| 1.3 | 2026-07-18 갱신 | 최근 기록 검색(가맹점·카테고리·메모·금액) + 검토 날짜 경고 아이콘 + 자동 추출 정확도 개선(날짜 환각·과분할·off-list 카테고리 폴백) |
| 1.4 | 2026-09-20 갱신 | 공유 시트 텍스트 수신(스크린샷 없이 알림 문구 공유) + 통계·예산을 합친 월간 요약 탭(탭 5→4) + 월 정산 전월 카드대금 + 정산 완료 월 경고 + 항목 행 정리 + 연도 미표기 날짜 스냅 |
