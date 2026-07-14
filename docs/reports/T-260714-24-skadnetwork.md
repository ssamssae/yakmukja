# T-260714-24 약먹자 iOS SKAdNetwork 보강 보고

- 시각: 2026-07-14 23:34 KST
- 변경: `ios/Runner/Info.plist`의 SKAdNetworkItems를 0개에서 50개로 보강
- 기준: Google Mobile Ads SDK iOS quick start의 Complete snippet
  - https://developers.google.com/admob/ios/quick-start
  - 문서 표기 최종 갱신: 2026-07-13 UTC
- 스토어 동작: 0건(빌드·업로드·제출·심사 트리거 없음)

## 검증

- RED: 변경 전 `SKAdNetworkItems | length == 50` → exit 1
- GREEN: `plutil -lint ios/Runner/Info.plist` → OK
- GREEN: 공식 순서와 전체 배열 일치, count=50, unique=50
- 배열 SHA-256: `0f1aac2d03ee2727f9034ab73e3010d549ebfed39dff67e68a4e1d2147e43eb5`
- GREEN: SKAdNetworkItems를 제외한 plist 의미값이 HEAD와 동일
- GREEN: `git diff --check` → exit 0
