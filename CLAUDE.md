# 약먹자 (yakmukja)

## 프로젝트 개요
약 복용 알림 Flutter 앱 (iOS/Android)
- 패키지: com.ssamssae.yakmukja
- 앱 이름: 약먹자

## 개발 환경
- FVM 사용: 모든 Flutter 명령어는 `fvm flutter` 사용
- FVM 경로: ~/fvm/versions/stable/bin/flutter
- M1 Mac (darwin-arm64)

## 자주 쓰는 명령어
```bash
# 클린 빌드 후 실행 (iOS 실기기)
fvm flutter clean && fvm flutter run --release

# APK 빌드 (Android)
fvm flutter build apk --release --split-per-abi

# iOS 빌드
fvm flutter build ipa --release

# 정적 분석
fvm dart analyze lib/
```

## 주의사항
- iOS는 전통 AppDelegate 방식 사용 (FlutterImplicitEngineDelegate 금지)
- 런처 아이콘 투명 배경 금지 (App Store 거절 사유)
- 한국어 대화, 간결한 설명, 단계별 진행
