# 복용 시간 수정 확인 경로

T-260926-017 · 2026-09-26 KST · mac:codex

- 사전 조건: 테스트용 약 A(08:00, 20:00), 약 B(09:00), 알림 권한 허용. 사용자 실데이터 대신 임시 Hive 및 알림 채널 모형을 사용했다.
- 진입점: 약 A → 약 수정 → 20:00 시간 칩의 닫기 → 저장.
- 기대 결과: 저장소에는 A의 08:00만 남고 재조회에도 유지된다. A의 20:00 예약은 제거되며 B의 09:00 예약은 유지된다. 저장 성공 후 이전/새 시간 슬롯을 함께 정리한다.
- 검증: `tool/flutter.sh test test/screens/medicine_alarm_edit_test.dart test/services/notification_service_test.dart`에서 Android/iOS 채널 모형의 실제 위젯 조작·예약 집합·Hive 재조회 확인. 수정 전에는 삭제한 예약 id 10이 남는 실패를 재현했다.
- 근거: `/Users/user/reports/T-260926-017/life/yakmukja-repro.txt`, `yakmukja-alarm-final.txt`.
- 미확인: 실기기 OS 알림 수신, 이미 구버전에서 고아가 된 알림의 자동 복구, 스토어 배포. Android 출시 보류 유지. 유료 주문·외부 발신 없음.

## 시작화면 로고 — T-260928-006

- 진입점: 앱 실행 → 약먹자 / 건강한 하루의 시작 화면.
- 현재 런처 원본 design/icon_master.png를 assets/images/logo.png에 그대로 동기화해 시작화면과 앱 아이콘을 일치.
- 확인: 두 파일 SHA256 동일, SplashScreen.logoAssetPath 연결 및 기존 splash 테스트.
- 미확인: 새 설치본 사용자 iPhone 화면.
