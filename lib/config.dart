/// 컴파일 타임 설정 플래그.
///
/// 스토어 스크린샷 캡처용 클린 모드. `--dart-define=SCREENSHOT_MODE=true` 로
/// 빌드하면 첫 실행 알림권한 다이얼로그와 광고 배너를 끄고 깨끗한 화면을 띄운다.
/// (기본값 false — 일반/운영 빌드 동작에는 영향 없음.)
const bool kScreenshotMode =
    bool.fromEnvironment('SCREENSHOT_MODE', defaultValue: false);

/// 스토어 스크린샷 "약 등록된" 화면용 데모 데이터 시드.
/// `--dart-define=SCREENSHOT_SEED=true` 일 때, 빈 보관함에 샘플 약을 넣는다.
const bool kScreenshotSeed =
    bool.fromEnvironment('SCREENSHOT_SEED', defaultValue: false);
