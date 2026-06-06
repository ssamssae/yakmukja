# 약먹자 (yakmukja)

복용 시간을 잊지 않게 도와주는 가벼운 알림 앱.
정해진 시간에 어떤 약을 먹어야 하는지 한 화면에서 보고, 체크해서 기록한다.

## 배포 정책

**iOS-only 출시.** Android Play Console 등록은 보류 (강대종 2026-05-02 결정 — 핵심 앱만 출시, ₩30K 토큰 회피).
관련 메모: `feedback_app_release_strategy.md`.

- iOS: App Store 출시 완료
- Android: 빌드는 가능하지만 Play 제출 안 함 (release signing 까지 박혀 있어 미래에 풀고 싶으면 바로 가능)

## 광고 정책

**iOS-only AdMob 배너 유지.** iOS 출시본은 홈 화면 하단에 비개인화 AdMob 배너를 표시한다.
Android 는 출시 보류 상태라 AdMob App ID / 광고 단위 ID 를 발급하지 않고, Android 런타임에서는 광고 SDK 초기화와 배너 로드를 건너뛴다.

따라서 약먹자는 "광고 없음"으로 마케팅하지 않는다. 현재 정합한 표현은 "계정 가입 없음, 개발자 서버 전송 없음, iOS 하단 배너 광고"다.

## 기능

- 약 등록 (이름 · 용량 · 복용 시간대 — 아침/오후/저녁)
- 홈 화면 — 다음 복용 카운트다운, 시간대별 약 카드, 진행률 표시, "모두 복용 완료" 배너
- 시간 도달 시 로컬 알림 발사 + 탭하면 홈으로
- 30일치 복용 기록 자동 정리 (storage bloat 방지)

## 개발 환경

- Flutter (FVM 사용, `~/fvm/versions/stable/bin/flutter`)
- Dart 3.x
- Hive (`medicine.dart` / `medicine.g.dart`), `flutter_local_notifications`, `google_mobile_ads` (iOS 배너)
- M1 Mac (darwin-arm64)

## 자주 쓰는 명령

```bash
# 클린 빌드 후 iOS 실기기 실행
fvm flutter clean && fvm flutter run --release

# Android APK 빌드 (split per ABI)
fvm flutter build apk --release --split-per-abi

# iOS IPA 빌드
fvm flutter build ipa --release

# 정적 분석
fvm dart analyze lib/
```

## 주의사항

- iOS 전통 AppDelegate 방식 사용 — FlutterImplicitEngineDelegate 금지
- 런처 아이콘 투명 배경 금지 (App Store 거절 사유)
- AdMob 배너 광고 (운영 ID iOS-only 적용) — 홈 화면 하단. Android 광고 비활성.

## 패키지 정보

- 패키지 ID: `com.ssamssae.yakmukja`
- 앱 이름: 약먹자

## 백로그

`BACKLOG.md` 참조.
