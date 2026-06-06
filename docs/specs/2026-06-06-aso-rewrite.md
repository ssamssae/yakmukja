# 약먹자 ASO 재작성

**Task**: `T-260515-08`

**Date**: 2026-06-06 KST

**Status**: store metadata package ready, external store update not applied

## Inputs

- `docs/specs/2026-06-06-admob-policy-decision.md`
- `daejong-page/specs/competitor-2026-05-15/yakmukja.md`
- Current app UI after light design refresh (`docs/specs/2026-05-20-design-refresh.md`)
- Current `store_metadata.md`

## Decision

Use the Option B product truth:

- iOS-only release stays.
- iOS keeps one non-personalized AdMob bottom banner.
- Android release is still on hold and Android ad IDs are not issued.
- Do not market the app as ad-free.
- Do market: account-free, developer-server-free, lightweight medication reminder.

## Final Fields

### ASC Subtitle

`복용 시간 알림 · 복약 기록 · 카운트다운`

Reason: keeps the strongest search terms (`복용`, `알림`, `복약`, `기록`) and adds the current product differentiator (`카운트다운`) within the 30-character ASC limit.

### ASC Keywords

`복용,알림,복약,처방,영양제,비타민,약알림,복약알림,약관리,복용기록,약달력,혈압약,당뇨약,부모님약,오메가3,홍삼,pill,reminder`

Reason: combines broad category terms with high-intent medication reminder phrases and the parent-care segment from the competitor analysis.

### Play Short Description

`약·영양제·비타민 복용 시간 알림. 5초 등록, 카운트다운, 완료 체크, 가입 없음.`

Reason: stays within the 80-character Play limit while surfacing supplement use, reminder intent, countdown, completion tracking, and the no-account promise.

### Positioning

Primary line: a lightweight medication and supplement reminder for people who want fast setup without accounts or server sync.

Do not position against full medical-management apps. 약먹자 does not provide prescription OCR, pharmacist consultation, interaction checking, caregiver dashboards, or medical advice.

### Platform Copy Rule

- App Store copy may mention the iOS bottom banner explicitly.
- Play Store draft copy should not claim "광고 없음"; Android release remains on hold.
- Privacy/App Privacy copy must be checked before any real ASC/Play metadata update because the public privacy page may lag behind the iOS AdMob reality.

## Verification

- `store_metadata.md` no longer contains `광고 없음`.
- `store_metadata.md` no longer describes the app as dark-theme-first.
- Subtitle and Play short description are within their documented local limits.
- ASC keywords use more of the 100-character budget than the old 54-character draft.
- No ASC/Play Console PATCH or submission was performed in this task.
