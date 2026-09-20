# App Store 제출 메타데이터

찰칵가계부 App Store Connect 제출 기록 (현재 버전 1.4).

App Store에 표시되는 **텍스트의 실제 값은 `fastlane/metadata/ko/`**에 있다. 이
문서는 그 밖의 제출 정보(기본 정보 · App Privacy · 심사팀 메모)와 값 선택의 근거를
남기는 곳이다. 값을 여기에 다시 적지 않는다.

---

## 1. 기본 정보

이 표의 값은 대부분 `fastlane/metadata/`가 추적하지 않는다. deliver가 관리할 수
있는 필드(Copyright, 카테고리, Age Rating, Review Information)도 파일이 없으면
그냥 건너뛰므로, App Store Connect에서 직접 설정하고 그 기록을 여기에 남긴다.
파일로 추적되는 항목은 값 대신 파일 경로를 가리킨다.

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
| Support URL | → `fastlane/metadata/ko/support_url.txt` |
| Privacy Policy URL | → `fastlane/metadata/ko/privacy_url.txt` |
| Marketing URL | (없음) |
| EULA | Apple Standard EULA |

---

## 2. App Store 표시 텍스트 (한국어)

> **값의 단일 출처는 `fastlane/metadata/ko/`의 파일들이다.** 릴리즈 워크플로가 그
> 파일들을 그대로 App Store Connect에 올린다. 이 문서는 값을 복사해 두지 않는다 —
> 같은 문구가 두 곳에 있으면 한쪽만 고쳐져 조용히 어긋나고, 그것이 1.4에서
> Promotional Text가 빠진 경위다. 여기에는 **왜 그 문구인지, 무엇을 조심해야
> 하는지**만 남긴다. 리포와 App Store Connect의 차이는
> `python3 -m scripts.asc_release audit`으로 확인한다.

| 필드 | 파일 | 제한 | 주의 |
|---|---|---|---|
| Subtitle | `subtitle.txt` | 30자 | **앱 정보(app-level)** — 바꾸면 심사 대상 |
| Promotional Text | `promotional_text.txt` | 170자 | 심사 없이 수시 변경 가능 — 짧은 공지에 쓰기 좋다 |
| Keywords | `keywords.txt` | 100자 | 콤마 구분, **공백 없이** (공백도 글자 수에 포함) |
| Description | `description.txt` | 4000자 | `■` 섹션 구조 유지 — 동작 / 기능 / 프라이버시 / 요구 사항 / 의도된 한계 |
| What's New | `release_notes.txt` | 4000자 | 버전마다 교체하되, 내린 노트는 아래에 보존 |
| Support URL | `support_url.txt` | — | §1 표에서 이 파일을 가리킨다 |
| Privacy Policy URL | `privacy_url.txt` | — | **앱 정보(app-level)** — §1 표에서 이 파일을 가리킨다 |

글자수 초과와 파일 누락은 `preflight`가 업로드 전에 막는다
(`FIELD_LIMITS` / `missing_metadata_files` in `scripts/asc_release.py`). 파일이
없으면 deliver는 그 필드를 조용히 건너뛰기 때문에, 누락은 경고가 아니라 차단이다.

### 이전 버전 노트 (내려간 What's New)
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
