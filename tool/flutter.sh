#!/usr/bin/env bash
# 약먹자 Flutter 진입점 — 툴체인이 살아있는지 먼저 확인하고 넘긴다.
#
# 왜 있나 (T-260728-089): fvm 에 버전이 하나도 지정돼 있지 않으면 `fvm flutter ...` 가
# 출력 0줄 + rc=0 으로 조용히 아무것도 하지 않는다. CLAUDE.md 규약대로
# `fvm flutter analyze` 를 돌린 워커는 이걸 통과로 읽는다 — 검증이 통째로 위장된다.
# 실제로 한 번 오판했다. 규율(문서에 "확인해라")로는 못 막으므로 게이트로 만든다.
#
# 계약 (픽스처: tool/tests/test_flutter_preflight.sh)
#   - 툴체인이 버전 배너를 못 내면 실패한다 (조용한 초록 차단)
#   - pubspec.yaml 이 요구하는 최소 Flutter 버전에 못 미치면 실패한다
#   - 정상이면 인자를 그대로 넘긴다 (과차단 금지)
#
# 사용: tool/flutter.sh analyze lib/   ·   tool/flutter.sh test
# 툴체인 교체(테스트용): YAKMUKJA_FLUTTER_CMD="/path/to/flutter" tool/flutter.sh ...
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
read -ra FLUTTER_CMD <<< "${YAKMUKJA_FLUTTER_CMD:-fvm flutter}"

die() {
  echo "🛑 [preflight] $1" >&2
  echo "   진단: ${FLUTTER_CMD[*]} --version 을 직접 돌려보세요." >&2
  echo "   흔한 원인: fvm 에 버전 미지정(fvm list 의 Global/Local 이 비어 있음)." >&2
  echo "   복구: 리포 루트에서 fvm use 3.44.6 (.fvmrc 생성)." >&2
  exit 90
}

banner="$("${FLUTTER_CMD[@]}" --version 2>&1)"
probe_rc=$?

if [ "$probe_rc" -ne 0 ]; then
  die "Flutter 툴체인이 오류로 끝났습니다 (rc=$probe_rc). 출력: ${banner:-<없음>}"
fi

version="$(printf '%s\n' "$banner" \
  | sed -n 's/^Flutter \([0-9][0-9.]*\).*/\1/p' | head -1)"

if [ -z "$version" ]; then
  die "Flutter 툴체인이 버전을 대답하지 않습니다 — 아무것도 실행되지 않았을 가능성이 높습니다."
fi

# 최소 버전은 pubspec.yaml 을 정본으로 읽는다 (여기에 숫자를 또 적어두면 갈린다).
min="$(sed -n 's/^[[:space:]]*flutter:[[:space:]]*">=\([0-9][0-9.]*\)".*/\1/p' \
  "$REPO_ROOT/pubspec.yaml" 2>/dev/null | head -1)"

if [ -n "$min" ]; then
  lowest="$(printf '%s\n%s\n' "$version" "$min" | sort -V | head -1)"
  if [ "$version" != "$min" ] && [ "$lowest" = "$version" ]; then
    die "Flutter $version 은 pubspec.yaml 이 요구하는 >=$min 에 못 미칩니다."
  fi
fi

exec "${FLUTTER_CMD[@]}" "$@"
