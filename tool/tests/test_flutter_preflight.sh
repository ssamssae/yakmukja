#!/usr/bin/env bash
# tool/flutter.sh 계약 픽스처 (T-260728-089).
#
# 사고: fvm 이 아무것도 안 하고 출력 0줄 + rc=0 을 내던 상태에서 CLAUDE.md 규약대로
# `fvm flutter analyze` 를 돌리면 통과로 읽혔다. 검증이 통째로 위장됐다.
# 여기서 고정하는 계약은 "툴체인이 대답하지 않으면 크게 실패한다" 하나다.
#
# 툴체인 자체를 스텁으로 갈아끼워 검사하므로 실제 fvm·Flutter 설치가 필요 없다.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$REPO_ROOT/tool/flutter.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

check() { # check <이름> <기대rc> <실제rc> [<출력>] [<출력에 있어야 할 문구>]
  local name="$1" want="$2" got="$3" out="${4:-}" needle="${5:-}"
  if [ "$want" = "nonzero" ]; then
    [ "$got" -ne 0 ] || { echo "❌ $name — rc=0 (실패해야 하는데 통과했다)"; fail=$((fail + 1)); return; }
  else
    [ "$got" = "$want" ] || { echo "❌ $name — rc=$got (기대 $want)"; fail=$((fail + 1)); return; }
  fi
  if [ -n "$needle" ] && ! printf '%s' "$out" | grep -q -- "$needle"; then
    echo "❌ $name — 출력에 '$needle' 없음"; fail=$((fail + 1)); return
  fi
  echo "✅ $name"; pass=$((pass + 1))
}

make_stub() { # make_stub <파일> <본문>
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$1"
  chmod +x "$1"
}

# ── I 정상 툴체인이면 통과시키고 인자를 그대로 넘긴다 (과차단 방지) ──────────────
make_stub "$TMP/ok" '
if [ "$1" = "--version" ]; then
  echo "Flutter 3.44.6 • channel stable • git@github.com:flutter/flutter.git"
  echo "Tools • Dart 3.12.2"
  exit 0
fi
echo "ARGS:$*"
'
out="$(YAKMUKJA_FLUTTER_CMD="$TMP/ok" "$TARGET" analyze lib/ 2>&1)"; rc=$?
check "I 정상 툴체인은 통과하고 인자를 그대로 전달한다" 0 "$rc" "$out" "ARGS:analyze lib/"

# ── J 사고 재현: 출력 0줄 + rc=0 이면 크게 실패해야 한다 ───────────────────────
make_stub "$TMP/silent" 'exit 0'
out="$(YAKMUKJA_FLUTTER_CMD="$TMP/silent" "$TARGET" analyze 2>&1)"; rc=$?
check "J 조용한 무동작(출력 0줄 rc=0)은 차단된다" nonzero "$rc" "$out" "툴체인"

# ── K 버전 미달 SDK 도 차단한다 (pubspec 은 flutter >=3.44.0 을 요구) ──────────
make_stub "$TMP/old" '
if [ "$1" = "--version" ]; then
  echo "Flutter 3.41.9 • channel stable • https://github.com/flutter/flutter.git"
  exit 0
fi
echo "ARGS:$*"
'
out="$(YAKMUKJA_FLUTTER_CMD="$TMP/old" "$TARGET" test 2>&1)"; rc=$?
check "K pubspec 최소 버전에 못 미치는 SDK 는 차단된다" nonzero "$rc" "$out" "3.44.0"

# ── L 툴체인이 실패(rc!=0)해도 통과로 읽지 않는다 ─────────────────────────────
# 배너는 멀쩡히 내면서 rc 만 비-0 인 스텁이어야 이 축이 rc 검사를 실제로 고정한다.
# (출력까지 비면 '빈 버전' 검사에 걸려 통과해버려서, rc 검사를 지워도 안 잡힌다 —
#  실제로 변이 검사에서 이 구멍이 나와 스텁을 바꿨다.)
make_stub "$TMP/broken" '
if [ "$1" = "--version" ]; then
  echo "Flutter 3.44.6 • channel stable • git@github.com:flutter/flutter.git"
  echo "boom" >&2
  exit 3
fi
echo "ARGS:$*"
'
out="$(YAKMUKJA_FLUTTER_CMD="$TMP/broken" "$TARGET" analyze 2>&1)"; rc=$?
check "L 툴체인이 오류로 끝나면 통과시키지 않는다" nonzero "$rc" "$out" "rc=3"

echo
echo "preflight 계약: ${pass} 통과 / ${fail} 실패"
[ "$fail" -eq 0 ]
