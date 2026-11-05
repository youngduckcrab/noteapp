#!/usr/bin/env bash
# npm run test:emulator (cwd functions/). Contract 7.4.6: the container-wide heavy-test lock is
# taken by INFRA's `ws with-heavy-lock` (fixed path /tmp/noteapp-heavy-tests.lock, override
# NOTEAPP_HEAVY_LOCK); it sets NOTEAPP_HEAVY_LOCK_HELD=1 for every child, so an inner
# `ws test -t emulator` does not take it again (no nested deadlock). No bash lock of our own.
# CI (CI=true): one job per runner and no Dart yet at this step of functions.yml → no lock.
set -euo pipefail
fn_dir="$(cd "$(dirname "$0")/.." && pwd)"          # functions/
root="$(cd "$fn_dir/.." && pwd)"
if [[ -z "${NOTEAPP_HEAVY_LOCK_HELD:-}" && "${CI:-}" != "true" ]]; then
  cd "$root"
  exec dart run tool/ws.dart with-heavy-lock -- bash functions/scripts/emulator_suite.sh "$@"
fi
for port in 5001 9099; do                              # risk R9: another agent's emulator
  if command -v ss >/dev/null && ss -ltn "sport = :$port" | grep -q LISTEN; then
    echo "port $port is busy (another emulator?)" >&2; exit 3
  fi
done
cd "$fn_dir"
inner="node --test 'lib/test-emulator/**/*.emulator.test.js'"
if [[ "${1:-}" == "--with-dart" ]]; then             # SYNC + LIBRARY in one emulator run (I-3)
  inner="$inner && (cd .. && dart run tool/ws.dart test --package ink_recognition --run-skipped -t emulator)"
fi
npx firebase emulators:exec --config ../app/firebase.json --only functions,auth \
  --project demo-noteapp "$inner"
