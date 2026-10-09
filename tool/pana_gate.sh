#!/usr/bin/env bash
#
# Pub-points gate.
#
# Runs the real pana — the same scorer pub.dev uses — and fails the build unless
# the package scores 160/160. pana's own exit code is not enough: it prints
# "Points: N/160." without failing the process, so a regression would otherwise
# pass silently. This parses the number and compares it to a floor.
#
# Why a floor and not a hard 160: pub.dev's criteria drift with the SDK, so a
# hard-coded ceiling would break on a toolchain upgrade rather than on a real
# regression. MIN_POINTS makes the intent explicit and is bumped deliberately.
#
# Local prerequisites (pana 0.23.19 does not run out of the box on Dart 3.13):
#   B="$(dirname "$(dirname "$(readlink -f "$(which pana)")")")"
#   mkdir -p "$B/lib/_internal"
#   echo '{}' > "$B/lib/_internal/allowed_experiments.json"
#   dart --version 2>&1 | sed 's/.*: //' | awk '{print $1}' > "$B/version"
#   pana --license-data="$HOME/.pub-cache/hosted/pub.dev/pana-0.23.19/lib/src/third_party/spdx/licenses"
#
# pana resolves the Flutter SDK only from FLUTTER_ROOT — it does not scan PATH.
# For a pure-Dart package this is not needed, but the variable is set when
# present so the same command works unchanged in a Flutter monorepo.
#
# NOTE: run one package at a time. pana copies the package into a temp directory
# and this has run out of space on a 512 MB /tmp when run in parallel.

set -euo pipefail

readonly MIN_POINTS="${MIN_POINTS:-160}"
readonly REPORT="${REPORT:-$(mktemp -t pana-report.XXXXXX.txt)}"

echo "==> pana (floor: ${MIN_POINTS}/160), report -> ${REPORT}"

# The license corpus ships with the pana package; its path is otherwise
# discovered, which needs network access.
LICENSE_ARGS=()
for candidate in \
  "$HOME"/.pub-cache/hosted/pub.dev/pana-*/lib/src/third_party/spdx/licenses \
  "$HOME"/.pub-cache/git/pana-*/lib/src/third_party/spdx/licenses; do
  if [[ -d "$candidate" ]]; then
    LICENSE_ARGS=(--license-data="$candidate")
    break
  fi
done
if [[ ${#LICENSE_ARGS[@]} -eq 0 ]]; then
  echo "!! SPDX license corpus not found; pana may report spurious license findings." >&2
fi

set +e
pana "${LICENSE_ARGS[@]}" > "$REPORT" 2>&1
set -e

SCORED="$(grep -oE 'Points: [0-9]+/160' "$REPORT" | tail -1 | sed -E 's|Points: ([0-9]+)/160|\1|' || true)"

if [[ -z "$SCORED" ]]; then
  echo "!! pana produced no score. Report follows:" >&2
  tail -40 "$REPORT" >&2
  exit 1
fi

echo "==> scored ${SCORED}/160 (floor ${MIN_POINTS})"

if (( SCORED < MIN_POINTS )); then
  echo "!! FAIL: ${SCORED}/160 is below the ${MIN_POINTS}/160 floor." >&2
  echo "" >&2
  echo "Sections not at full marks:" >&2
  grep -E '^### ' "$REPORT" | grep -vE '\[\*\]' >&2 || true
  echo "" >&2
  echo "Full report: ${REPORT}" >&2
  exit 1
fi

echo "==> PASS"