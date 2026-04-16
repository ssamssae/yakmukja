# 약먹자 (yakmukja) 개발일지

## 프로젝트 개요

| 항목 | 내용 |
|------|------|
| 앱 이름 | 약먹자 |
| 패키지 | com.ssamssae.yakmukja |
| 플랫폼 | iOS / Android |
| 프레임워크 | Flutter (FVM) |
| 로컬 DB | Hive |
| 버전 | 1.0.0+1 |
| GitHub | https://github.com/ssamssae/yakmukja |

---

## 2026-04-13 (Day 1) — 전체 개발 완료

### 1. 프로젝트 생성 및 초기 설정
- Flutter 프로젝트 생성 (com.ssamssae.yakmukja)
- FVM 환경 구성 (~/fvm/versions/stable/bin/flutter)
- Hive 로컬 DB 설정 (Medicine, DoseTime 모델)
- iOS 전통 AppDelegate 방식 적용 (FlutterImplicitEngineDelegate 금지)

### 2. 데이터 모델 설계
- **Medicine** (HiveType 0): name, dosage, times, memo, createdAt, takenRecords
- **DoseTime** (HiveType 1): hour, minute
- 복용 기록: "yyyy-MM-dd_HH:mm" 형식으로 takenRecords에 저장
- isTaken(), toggleTaken() 메서드로 복용 체크/해제

### 3. UI/UX 디자인
- **다크 테마** 적용 (Material 3, seedColor: amber #FFC107)
- **스플래시 화면**: 검정 배경, 앰버 글로우 로고, "약먹자" + "건강한 하루의 시작", 900ms 페이드인 → 2초 후 홈 전환
- **홈 화면**:
  - 오늘 날짜 + 복용 진행률 (프로그레스 바)
  - 시간대별 그룹 (새벽/아침/오후/저녁) 아이콘 구분
  - 실시간 카운트다운 배너 (다음 복용까지 남은 시간)
  - "오늘 약을 모두 복용했어요!" 완료 배너
  - 응원 버튼 (외부 링크)
  - 약이 없을 때 빈 상태 화면
- **약 등록/수정 화면**:
  - CupertinoPicker 휠 방식 복용량 선택 (0.5~10알)
  - CupertinoPicker 휠 방식 시간 선택 (오전/오후 + 시 + 분)
  - 복용 시간 칩 목록 + 삭제 가능
  - AppBar 우측 저장 버튼
  - 중복 시간 입력 방지

### 4. 시간 표시 개선
- 6단계 자연어 시간대: 밤(~5시) / 아침(5~9시) / 오전(9~12시) / 낮(12~14시) / 오후(14~18시) / 저녁(18시~)
- 12시간 포맷 (12, 1, 2, ... 11)

### 5. 푸시 알림 구현
- flutter_local_notifications v21 (named parameter API)
- flutter_timezone v5 (TimezoneInfo.identifier)
- 매일 반복 알림 (matchDateTimeComponents: DateTimeComponents.time)
- 알림 내용: "약먹자 💊" / "{약이름} {복용량} 드실 시간입니다."
- Android: POST_NOTIFICATIONS, SCHEDULE_EXACT_ALARM 등 퍼미션 추가
- iOS: UNUserNotificationCenter 권한 요청

### 6. 앱 아이콘
- 노란색 배경 + 흰색 알약 디자인 (Python PIL로 생성)
- 1024x1024 마스터 → iOS/Android 전 사이즈 생성
- 투명 배경 없음 (App Store 리젝 방지)

### 7. 빌드 이슈 해결
| 이슈 | 해결 |
|------|------|
| Android SDK 미인식 | flutter config --android-sdk 경로 설정 |
| Android 라이선스 미수락 | flutter doctor --android-licenses |
| Java 26 / Gradle 호환 | temurin@17 설치 |
| Core library desugaring | build.gradle.kts에 desugaring 설정 추가 |
| flutter_local_notifications v21 API 변경 | 전부 named parameter로 수정 |
| flutter_timezone v5 API 변경 | .identifier 프로퍼티 사용 |

### 8. APK 빌드 및 테스트
- `fvm flutter build apk --release --split-per-abi` 성공
- arm64-v8a APK 실기기 설치 확인

### 9. GitHub 푸시
- 레포: https://github.com/ssamssae/yakmukja
- Initial commit 완료 (84 files)

---

## 파일 구조

```
lib/
├── main.dart                     # 앱 진입점, Hive 초기화, 테마 설정
├── models/
│   ├── medicine.dart             # Medicine, DoseTime 모델
│   └── medicine.g.dart           # Hive TypeAdapter (자동생성 + 수동수정)
├── screens/
│   ├── splash_screen.dart        # 스플래시 화면
│   ├── home_screen.dart          # 메인 홈 (복용 목록, 카운트다운)
│   └── medicine_edit_screen.dart # 약 등록/수정 (휠 피커)
└── services/
    └── notification_service.dart  # 푸시 알림 서비스
```

---

## 사용 패키지

| 패키지 | 버전 | 용도 |
|--------|------|------|
| hive | ^2.2.3 | 로컬 DB |
| hive_flutter | ^1.1.0 | Hive Flutter 바인딩 |
| path_provider | ^2.1.4 | 앱 경로 |
| intl | ^0.19.0 | 날짜 포맷 |
| url_launcher | ^6.3.2 | 외부 링크 |
| flutter_local_notifications | ^21.0.0 | 푸시 알림 |
| flutter_timezone | ^5.0.2 | 타임존 |
| timezone | ^0.11.0 | TZDateTime |

---

## 다음 할 일 (2026-04-14)
- [ ] TestFlight 심사 제출
- [ ] Google Play 개발자 등록
- [ ] 약먹자 포함 앱 3개 스토어 런칭
