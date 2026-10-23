#!/usr/bin/env bash
# One-command bootstrap for datastar-aether.
#
# Ensures the Aether toolchain (`ae`) and the build runner (`aeb`, used here only
# for release/.version.ae) are present at the pinned versions, then runs the
# offline suites — the same four `task test` runs — so a fresh clone proves
# itself in one command.
#
# The toolchains install via aeb's canonical remote installer, get.sh, which
# ensures BOTH `ae` and `aeb` binary-first (no compiler, no make). Installing
# needs only `curl`. BUILDING additionally needs a C compiler (Aether compiles to
# C) — checked below.
#
# Idempotent: a no-op for the toolchain when `ae`/`aeb` are already good.
#
# The known-good pins live in ci/versions.env (AETHER_REF, AETHER_MIN, AEB_REF);
# this reads them so there is one place to bump. Override at the shell to test a
# bump.
#
# Env overrides:
#   PREFIX        install prefix                 (default: $HOME/.local; no sudo)
#   AETHER_REF    ae tag/branch/SHA to install   (default: ci/versions.env) — pin in CI
#   AEB_REF       aeb tag/branch/SHA to install  (default: ci/versions.env) — pin in CI
#   MIN_AE        minimum acceptable ae version  (default: ci/versions.env floor)
#   NO_TEST=1     install the toolchain only
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"; export PREFIX
AEB_GET_URL="https://raw.githubusercontent.com/aether-lang-dev/aeb/main/get.sh"

# Pins from ci/versions.env (shell-overridable). AETHER_REF vX.Y.Z -> AE_PIN X.Y.Z.
# shellcheck disable=SC1091
[ -f "$HERE/ci/versions.env" ] && . "$HERE/ci/versions.env"
MIN_AE="${MIN_AE:-${AETHER_MIN:-${AETHER_REF#v}}}"; MIN_AE="${MIN_AE:-0.841.0}"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }
ae_version() { ae --version 2>/dev/null | head -n1 | sed -E 's/^ae ([0-9]+\.[0-9]+\.[0-9]+).*/\1/'; }

export PATH="$PREFIX/bin:$HOME/.aether/bin:$PATH"   # so freshly-installed ae/aeb are found below

# ---- 1. Toolchain (ae + aeb), via aeb's get.sh (binary-first, make-free) ----
if command -v ae >/dev/null 2>&1 && command -v aeb >/dev/null 2>&1 \
   && have="$(ae_version || true)" && [ -n "$have" ] && version_ge "$have" "$MIN_AE"; then
    say "ae $have + aeb already on PATH (ae >= $MIN_AE) — skipping toolchain install"
else
    command -v curl >/dev/null 2>&1 || die "curl is required to install the Aether toolchain (or install ae/aeb yourself and re-run)."
    say "installing ae + aeb via get.sh (AE_PIN=${MIN_AE}, AEB_REF=${AEB_REF:-latest}, PREFIX=$PREFIX)"
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    curl -fsSL "$AEB_GET_URL" -o "$tmp" || die "could not download get.sh"
    AE_PIN="${MIN_AE}" AEB_REF="${AEB_REF:-}" PREFIX="$PREFIX" bash "$tmp" || die "toolchain install failed (get.sh)."
    command -v ae  >/dev/null 2>&1 || die "ae installed but not on PATH — ensure $PREFIX/bin is on PATH."
    command -v aeb >/dev/null 2>&1 || die "aeb installed but not on PATH — ensure $PREFIX/bin is on PATH."
    say "ae $(ae_version) + aeb ready"
fi

# ---- 2. Preflight for BUILDING: a C compiler ----
command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || command -v clang >/dev/null 2>&1 \
    || die "a C compiler (cc/gcc/clang) is required — Aether compiles to C. Install e.g. build-essential (Debian/Ubuntu) or the Xcode Command Line Tools (macOS)."

[ "${NO_TEST:-0}" = "1" ] && { say "toolchain ready (NO_TEST=1, skipping the suites)"; exit 0; }

# ---- 3. The offline suites, exactly as `task test` runs them ----
cd "$HERE"
mkdir -p target target/tls
say "building the fixtures the suites spawn"
ae build tests/fixtures/tick_server.ae
ae build -o target/once_server tests/fixtures/once_server.ae
ae build -o target/tls_server tests/fixtures/tls_server.ae
say "conformance goldens";  ae run tests/test_conformance.ae
say "SDK units";            ae run tests/test_sdk.ae
say "streaming";            ae run tests/test_streaming.ae
if [ ! -f target/tls/cert.pem ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -keyout target/tls/key.pem -out target/tls/cert.pem \
    -subj "/CN=127.0.0.1" -addext "subjectAltName=IP:127.0.0.1" 2>/dev/null
fi
say "TLS"; TLS_CERT=target/tls/cert.pem TLS_KEY=target/tls/key.pem ae run tests/test_tls.ae
say "version pins";         aeb release/.version.ae
say "done. Component suites (need a browser): task test-component"
