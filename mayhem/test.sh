#!/usr/bin/env bash
#
# kord/mayhem/test.sh — RUN twitchax/kord's own upstream test suite and emit a CTRF summary.
# exit 0 iff no test failed.
#
# Upstream CI (Makefile.toml [tasks.test] + [tasks.test-web-server]) runs:
#   cargo nextest run --features "ml_train ml_infer ml_sample_process"   (kord crate)
#   cargo nextest run --lib                                              (kord-web crate)
# We run the same suites via plain `cargo test` (no binstall dependency, offline-safe).
# The wasm browser suites ([tasks.test-wasm], [tasks.test-web-client]) need a headless
# browser + wasm-pack and cannot run in the commit image — they are the only omission.
#
# These tests assert VALUE-EXACT behavior (chord parsing known-answers, audio analysis of
# shipped .wav/.mp3 fixtures, ML inference on tests/vec.bin, notation round-trips), so a
# no-op / exit(0) sabotage patch cannot pass. build.sh pre-built the runners; this only RUNS.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not available — cannot run the test suite" >&2
  emit_ctrf "cargo-test" 0 1 0; exit 2
fi

echo "=== cargo test -p kord (features: ml_train ml_infer ml_sample_process) ==="
out1="$(RUSTFLAGS="" cargo test --no-fail-fast -p kord --features "ml_train ml_infer ml_sample_process" --jobs "$MAYHEM_JOBS" 2>&1)"; rc1=$?
echo "$out1"

echo "=== cargo test -p kord-web --lib ==="
out2="$(RUSTFLAGS="" cargo test --no-fail-fast -p kord-web --lib --jobs "$MAYHEM_JOBS" 2>&1)"; rc2=$?
echo "$out2"

# libtest prints one line per test binary:
#   test result: ok. 12 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; ...
PASSED=0; FAILED=0; IGNORED=0
while read -r p f i; do
  PASSED=$(( PASSED + p )); FAILED=$(( FAILED + f )); IGNORED=$(( IGNORED + i ))
done < <(printf '%s\n%s\n' "$out1" "$out2" \
  | sed -n 's/^test result:.* \([0-9][0-9]*\) passed; \([0-9][0-9]*\) failed; \([0-9][0-9]*\) ignored.*/\1 \2 \3/p')

if [ "$(( PASSED + FAILED + IGNORED ))" -eq 0 ]; then
  echo "could not parse any 'test result:' lines; using cargo exit codes ($rc1,$rc2)" >&2
  emit_ctrf "cargo-test" 0 1 0; exit 1
fi

# A nonzero cargo exit with all-passing parse lines means a compile error somewhere — fail.
if [ "$rc1" -ne 0 ] || [ "$rc2" -ne 0 ]; then
  [ "$FAILED" -gt 0 ] || FAILED=1
fi

emit_ctrf "cargo-test" "$PASSED" "$FAILED" "$IGNORED"
