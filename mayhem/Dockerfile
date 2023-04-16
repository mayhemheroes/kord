FROM ghcr.io/evanrichter/cargo-fuzz as builder

RUN apt update && apt install libasound2-dev -y
ADD . /kord
WORKDIR /kord/fuzz
RUN cargo +nightly fuzz build 

FROM debian:bookworm
RUN apt update && apt install libasound2-dev -y
COPY --from=builder /kord/fuzz/target/x86_64-unknown-linux-gnu/release/kord-fuzz /