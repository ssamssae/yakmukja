# 약먹자 AdMob 정책 결정

**Task**: `T-260515-16`

**Date**: 2026-06-06 KST

**Status**: decided · implementation guard applied

**Inputs**:

- `daejong-page/specs/audit-2026-05-15/yakmukja.md` (PR #77)
- `daejong-page/specs/competitor-2026-05-15/yakmukja.md` (PR #81 산출물)
- 현 repo README 의 iOS-only 출시 정책

## 1. 결정

**Option B 채택: iOS-only + Android 광고 비활성 + 솔직한 광고 문구.**

약먹자는 iOS 출시본에 한해 비개인화 AdMob 배너를 유지한다. Android 는 기존 정책대로 Play 출시를 보류하고, Android AdMob App ID / 광고 단위 ID 를 발급하지 않는다. Android 런타임에서는 광고 SDK 초기화와 배너 로드를 건너뛴다.

## 2. 왜 B인가

### A. Android 출시 + 실 AdMob ID 발급

지금 선택하지 않는다.

- Android 출시는 2026-05-02 정책상 보류 상태다.
- 출시 재개에는 Play 등록/심사, 광고 ID/Data Safety, INTERNET 권한, 실기기 광고 검증이 같이 필요하다.
- 단순히 테스트 ID를 실 ID로 바꾸면 출시 정책과 심사 준비가 함께 따라오지 않아 위험하다.

### B. iOS-only + Android 광고 비활성

이번 결정.

- 현재 운영 현실과 가장 가깝다. iOS App Store는 이미 출시됐고 iOS AdMob 운영 ID도 발급돼 있다.
- Android 미출시 정책을 유지하면서 audit S3의 "Android test AdMob ID 잔류" 위험을 제거한다.
- "광고 없음"이라는 과한 주장을 버리고, "계정 없음 / 개발자 서버 전송 없음 / iOS 하단 배너"로 정직하게 정리할 수 있다.

### C. 광고 완전 제거 + 유료화/Pro 재설계

지금 선택하지 않는다.

- 경쟁사 분석상 "광고 없음 + 로컬 전용" 포지션은 강하지만, 완전 무광고는 수익 모델 재설계가 먼저다.
- 유료화/IAP/Pro tier는 App Store/Play 설정, 가격 정책, 결제 QA, 환불 CS까지 동반한다.
- Medisafe 유료 전환으로 생긴 무료 시장 빈자리는 우선 무료+iOS 배너 모델로 관찰한다.

## 3. 이번 PR의 guard

- Android Manifest 에서 Google test AdMob App ID 제거.
- `AdsService` 는 iOS에서만 초기화하고, Android에서는 no-op.
- `AdaptiveBanner` 는 Android에서 `SizedBox.shrink()`만 렌더.
- README와 store metadata에서 "광고 없음" 표현 제거.

## 4. 후속 작업

1. `T-260515-08` ASO 재작성은 이 문구를 기준으로 한다.
   - 금지: "광고 없음"
   - 허용: "계정 가입 없음", "개발자 서버 전송 없음", "iOS 하단 배너"
2. Android 출시 재개 시 새 task로 Option A를 다시 연다.
   - Android AdMob App ID / Unit ID 발급
   - Android `INTERNET` 권한과 광고 ID/Data Safety 선언
   - Galaxy 실기기 광고 로드 검증
3. 광고 완전 제거/유료화는 별도 제품 결정이다. 이 문서는 C를 폐기하지 않고 현재 릴리스 범위에서 제외한다.
