# 약먹자 (yakmukja)

## 프로젝트 개요
약 복용 알림 Flutter 앱 (iOS/Android)
- 패키지: com.ssamssae.yakmukja
- 앱 이름: 약먹자

## 개발 환경
- **Flutter 명령은 `tool/flutter.sh` 경유** — `fvm flutter` 직접 호출 금지.
  래퍼가 툴체인 생존을 먼저 확인하고, 죽어 있으면 크게 실패한다.
- SDK 고정: `.fvmrc` = 3.44.6 (pubspec 이 `flutter: ">=3.44.0"` 요구).
  시스템 flutter 는 이 조건에 못 미칠 수 있으니 섞어 쓰지 말 것.
- M1 Mac (darwin-arm64)

> ⚠️ 제거 금지 (DO NOT REMOVE) — `fvm flutter` 직접 호출 금지 규약 (T-260728-089).
> fvm 에 버전이 지정돼 있지 않으면 `fvm flutter ...` 가 **출력 0줄 + rc=0** 으로
> 조용히 아무것도 하지 않는다. 호출자는 이를 통과로 읽어 검증이 통째로 위장된다
> (실측 사고 1건). 래퍼를 우회하면 그 함정이 그대로 되살아난다.
> 계약 픽스처: `tool/tests/test_flutter_preflight.sh`

## 자주 쓰는 명령어
```bash
# 툴체인 생존 확인 (다른 명령 전에 한 번)
tool/flutter.sh --version

# 클린 빌드 후 실행 (iOS 실기기)
tool/flutter.sh clean && tool/flutter.sh run --release

# APK 빌드 (Android)
tool/flutter.sh build apk --release --split-per-abi

# iOS 빌드
tool/flutter.sh build ipa --release

# 정적 분석
tool/flutter.sh analyze lib/

# 테스트
tool/flutter.sh test

# 래퍼 자체의 계약 검사
bash tool/tests/test_flutter_preflight.sh
```

## 주의사항
- iOS는 전통 AppDelegate 방식 사용 (FlutterImplicitEngineDelegate 금지)
- 런처 아이콘 투명 배경 금지 (App Store 거절 사유)
- 한국어 대화, 간결한 설명, 단계별 진행
