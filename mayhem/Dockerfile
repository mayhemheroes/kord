# syntax=docker/dockerfile:1.7
#
# kord commit-image Dockerfile — RUST target (cargo-fuzz). Builds on the org base,
# adding the pinned Rust nightly + cargo-fuzz under /opt/toolchains/rust, then runs
# mayhem/build.sh (fuzz target + pre-built upstream test suites) and mayhem/test.sh.
#
# Build (from the repo root, on the `mayhem` branch):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) -t kord-commit:test .

FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (never an ENV — an empty ENV breaks clang). build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
# Undefaulted (no '=') so the base ENV default flows through unless --build-arg overrides it.
ARG SANITIZER_FLAGS

# Pin the channel to upstream's rust-toolchain.toml (nightly-2025-12-22) so rustup resolves
# the repo's toolchain file without a network download; -Zsanitizer=address needs nightly.
ARG RUST_CHANNEL=nightly-2025-12-22
ARG CARGO_FUZZ_VERSION=0.12.0

ENV RUSTUP_HOME=/opt/toolchains/rust/rustup \
    CARGO_HOME=/opt/toolchains/rust/cargo \
    PATH=/opt/toolchains/rust/cargo/bin:${PATH}

USER root
# kord's `audio` feature (rodio/cpal) needs ALSA headers at build time.
RUN apt-get update && apt-get install -y --no-install-recommends libasound2-dev pkg-config \
 && rm -rf /var/lib/apt/lists/*

RUN install -d /opt/toolchains/rust \
 && curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh \
 && sh /tmp/rustup-init.sh -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_CHANNEL}" \
 && rustup component add rust-src --toolchain "${RUST_CHANNEL}" \
 # rust-toolchain.toml lists the wasm32 target — pre-install it so rustup never needs the
 # network when resolving the toolchain file (air-gapped PATCH re-run, SPEC §6.5).
 && rustup target add wasm32-unknown-unknown --toolchain "${RUST_CHANNEL}" \
 && cargo install cargo-fuzz --version "${CARGO_FUZZ_VERSION}" --locked \
 && rm -f /tmp/rustup-init.sh \
 # The commit build AND the air-gapped PATCH re-run run as `mayhem` (2000): it must
 # read the toolchain and read/refresh the cargo registry cache.
 && chown -R 2000:2000 /opt/toolchains/rust

# DWARF3 anchor: rustc's precompiled ASan runtime CUs are DWARF v5; prepending a DWARF3
# object as the FIRST object in every link makes triage (and the -m1 readelf gate) see v3,
# while -Zdwarf-version=3 keeps the user CUs at v3 (§6.2 item 10).
RUN set -eux; \
    mkdir -p /opt/mayhem-dwarf3-anchor; \
    printf 'void __mayhem_dwarf3_anchor(void) __attribute__((visibility("hidden"),used));\nvoid __mayhem_dwarf3_anchor(void) {}\n' \
      > /opt/mayhem-dwarf3-anchor/anchor.c; \
    clang -g -gdwarf-3 -c /opt/mayhem-dwarf3-anchor/anchor.c -o /opt/mayhem-dwarf3-anchor/anchor.o; \
    printf '#!/bin/bash\nexec cc /opt/mayhem-dwarf3-anchor/anchor.o "$@"\n' \
      > /opt/mayhem-dwarf3-anchor/cc-wrapper.sh; \
    chmod +x /opt/mayhem-dwarf3-anchor/cc-wrapper.sh; \
    chmod -R a+rX /opt/mayhem-dwarf3-anchor

# Source enters from the build CONTEXT (CI checkout): the FULL repo (incl. .git) → /mayhem.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Populates $CARGO_HOME (online, this first build) and builds the sanitized fuzz target(s).
RUN bash mayhem/build.sh

# Run the project's functional suite at build time (a failing suite fails the build).
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
