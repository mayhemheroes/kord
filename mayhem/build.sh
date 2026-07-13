#!/usr/bin/env bash
#
# kord/mayhem/build.sh — build twitchax/kord's cargo-fuzz target as a sanitized libFuzzer
# binary (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS), then pre-build the
# project's own test suite (normal flags) so mayhem/test.sh only RUNS it.
#
# The fuzz crate is ADDITIVE at mayhem/fuzz/ (upstream removed its old root fuzz/ dir);
# it ports the historical kord-fuzz harness (Chord::parse -> chord/scale/relative_chord)
# unchanged, pointing at ../../kord (lib name `klib`, features = ["audio"]).
#
# AIR-GAPPED CONTRACT (SPEC §6.5): this first (online) build populates the cargo registry
# under $CARGO_HOME=/opt/toolchains/rust/cargo; the PATCH tier re-runs this script OFFLINE
# with CARGO_NET_OFFLINE=true exported by the runtime — do NOT hard-code --offline here.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# RUST_DEBUG_FLAGS threads DWARF < 4 symbols (§6.2 item 10): debuginfo for triage,
# -Zdwarf-version=3 for the Rust user CUs, and the cc-wrapper linker that prepends a
# DWARF3 anchor object as the FIRST object in every link so the -m1 readelf check sees
# DWARF v3 even though the precompiled ASan runtime CUs remain DWARF v5 deeper in.
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -Z dwarf-version=3 -Clinker=/opt/mayhem-dwarf3-anchor/cc-wrapper.sh}"
export RUST_DEBUG_FLAGS

: "${MAYHEM_JOBS:=$(nproc)}"
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# OSS-Fuzz Rust libFuzzer+ASan flags. cargo-fuzz sets the ASan flag itself, but we pin it
# explicitly. --cfg fuzzing matches libfuzzer-sys; force-frame-pointers aids ASan backtraces.
# NOTE: $SANITIZER_FLAGS (clang flags) doesn't apply to rustc — ASan comes via RUSTFLAGS.
FUZZ_RUSTFLAGS="--cfg fuzzing $RUST_DEBUG_FLAGS -Zsanitizer=address -Cforce-frame-pointers"

FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

# Discover every target from the crate's fuzz_targets/ dir (one binary per target).
FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$FUZZ_RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

# Use the image's DEFAULT toolchain (the Dockerfile pinned nightly-2025-12-22, matching
# upstream's rust-toolchain.toml, so rustup resolves it without a download).
for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  RUSTFLAGS="$FUZZ_RUSTFLAGS" cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Pre-build the project's OWN test suites with NORMAL flags (no sanitizers) so
# mayhem/test.sh only runs them. Mirrors upstream CI (Makefile.toml):
#   [tasks.test]            cargo nextest run --features "ml_train ml_infer ml_sample_process"
#   [tasks.test-web-server] cargo nextest run --lib   (in kord-web)
# (wasm-pack browser test tasks are not runnable in the image — recorded as skipped.)
echo "=== pre-building upstream test suites (normal flags) ==="
RUSTFLAGS="" cargo test --no-run -p kord --features "ml_train ml_infer ml_sample_process" --jobs "$MAYHEM_JOBS"
RUSTFLAGS="" cargo test --no-run -p kord-web --lib --jobs "$MAYHEM_JOBS"

echo "build.sh complete:"
ls -la /mayhem/kord-fuzz
