#!/usr/bin/env bash
# Local check only. .github/workflows/release.yml is the authoritative builder
# for both release assets. The linux-amd64 path runs the Rust build under QEMU on
# Apple Silicon, which is slow and memory hungry, so it is opt in.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$REPO_ROOT/dist"
VENDOR="$REPO_ROOT/vendor/wb-codebuddy"
CARGO_HOME_DIR="$REPO_ROOT/.cargo-home"
RUST_IMAGE="${RUST_IMAGE:-rust:1-bookworm}"

TARGETS="${*:-darwin-arm64}"

say() { printf '%s\n' "$*"; }
die() { printf 'error  %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

sha256_file() {
  if have sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  elif have shasum; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "no sha256 tool found"
  fi
}

write_checksum() {
  local file="$1"
  local name hash
  name="$(basename "$file")"
  hash="$(sha256_file "$file")"
  printf '%s  %s\n' "$hash" "$name" > "$file.sha256"
  say "checksum  $name  $hash"
}

build_darwin() {
  say "build  darwin-arm64"
  cargo build --release --manifest-path "$VENDOR/Cargo.toml"
  cp "$VENDOR/target/release/wb-codebuddy" "$DIST/wb-codebuddy-darwin-arm64"
  write_checksum "$DIST/wb-codebuddy-darwin-arm64"
}

build_linux() {
  say "build  linux-amd64"
  have docker || die "docker is required for the linux-amd64 build"
  mkdir -p "$CARGO_HOME_DIR"
  docker run --rm --platform linux/amd64 --user "$(id -u):$(id -g)" \
    -e CARGO_HOME=/cargo \
    -v "$VENDOR:/src" \
    -v "$CARGO_HOME_DIR:/cargo" \
    -w /src "$RUST_IMAGE" cargo build --release
  cp "$VENDOR/target/release/wb-codebuddy" "$DIST/wb-codebuddy-linux-amd64"
  write_checksum "$DIST/wb-codebuddy-linux-amd64"
}

main() {
  local target
  mkdir -p "$DIST"
  for target in $TARGETS; do
    case "$target" in
      darwin-arm64) build_darwin ;;
      linux-amd64) build_linux ;;
      *) die "unknown target: $target" ;;
    esac
  done
  say ""
  say "artifacts in $DIST"
  ls -1 "$DIST"
}

main
