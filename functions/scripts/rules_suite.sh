#!/usr/bin/env bash
# npm run test:rules (cwd functions/) — 07-sync 6.10 L4 (Q6): SYNC's 1st-round security rules
# (packages/sync_engine/firebase/*.rules) in the Auth + Firestore + Storage emulators, checked
# with real emulator ID tokens over REST (lib/test-emulator/rules.emulator.test.js). Needs Java
# and the emulator jars (firebase-tools downloads them on first use), so it is run by hand and
# never in CI. Contract 7.4.6: under INFRA's container-wide heavy-test lock, like
# emulator_suite.sh (`ws with-heavy-lock` sets NOTEAPP_HEAVY_LOCK_HELD=1 for its children).
set -euo pipefail
fn_dir="$(cd "$(dirname "$0")/.." && pwd)"          # functions/
root="$(cd "$fn_dir/.." && pwd)"
if [[ -z "${NOTEAPP_HEAVY_LOCK_HELD:-}" ]]; then
  cd "$root"
  exec dart run tool/ws.dart with-heavy-lock -- bash functions/scripts/rules_suite.sh "$@"
fi
for port in 9099 8180 9199; do                         # risk R9: another agent's emulator
  if command -v ss >/dev/null && ss -ltn "sport = :$port" | grep -q LISTEN; then
    echo "port $port is busy (another emulator?)" >&2; exit 3
  fi
done
# firebase-tools refuses rules files outside the config's directory ("is outside of project
# directory" — 07-sync 6.10 L4 fallback): the config and SYNC's rules go into a temporary
# directory together, and the emulators run there (their firestore-debug.log goes with it).
work="$(mktemp -d "${TMPDIR:-/tmp}/noteapp-rules-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cp "$fn_dir/test-emulator/firebase.rules-test.json" "$work/firebase.json"
cp "$root/packages/sync_engine/firebase/firestore.rules" \
  "$root/packages/sync_engine/firebase/firestore.indexes.json" \
  "$root/packages/sync_engine/firebase/storage.rules" "$work/"
cd "$work"
"$fn_dir/node_modules/.bin/firebase" emulators:exec --config "$work/firebase.json" \
  --only auth,firestore,storage --project demo-noteapp \
  "node --test '$fn_dir/lib/test-emulator/rules.emulator.test.js'"
