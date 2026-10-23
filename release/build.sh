#!/usr/bin/env bash
# Cross-build this repo's binaries for the release matrix from ONE host, and emit
# each artifact with a .sha256 — the same build-here / verify-by-hash model as
# selenium's and libphonenumber-ae's release/ directories.
#
# What ships: every `[[bin]]` declared in aether.toml (the conformance test
# server and the two examples), one executable per target. The SDK itself is a
# source dependency (`ae add github.com/aether-lang-dev/datastar-aether@<tag>`)
# and needs no binary — the tag IS its release. Output name:
#   <bin>-<tag>-<os>-<arch>[-musl][.exe]
# Alongside each: <artifact>.sha256, plus a combined release/dist/SHA256SUMS.txt.
#
# Usage:
#   release/build.sh                          # core matrix (linux+macos x86_64/arm64)
#   RELEASE_EXTRA_TARGETS=1 release/build.sh  # + windows (slow) + freebsd (needs AETHER_SYSROOT)
#   RELEASE_TAG=v1.2.3 release/build.sh       # stamp the tag into artifact names
#                                               (default: DATASTAR_AETHER_VERSION)
#   TARGETS="aarch64-macos" release/build.sh  # override the matrix entirely
#   BINS="datastar-testserver" release/build.sh   # override the binary set
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck disable=SC1091
. "$HERE/targets.env"
cd "$ROOT"

export PATH="${AETHER_HOME:+$AETHER_HOME/bin:}${PREFIX:-$HOME/.local}/bin:$HOME/.aether/bin:$PATH"

say()  { printf 'release: %s\n' "$*"; }
die()  { printf 'release: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

have ae  || die "ae not on PATH (run ./bootstrap.sh, or see ci/versions.env)"
have zig || die "zig not on PATH — required for cross-compilation (ae build --target)"
have sha256sum || die "sha256sum required to checksum artifacts"

# The release tag. Single source of truth is the repo-root DATASTAR_AETHER_VERSION
# file (release/.version.ae keeps every other pin in step with it). RELEASE_TAG
# overrides it for a one-off / test build; git-describe is the last-ditch fallback.
_version_file="$ROOT/DATASTAR_AETHER_VERSION"
TAG="${RELEASE_TAG:-$( [ -f "$_version_file" ] && tr -d '[:space:]' < "$_version_file" || git describe --tags --always 2>/dev/null || echo dev )}"

# Resolve the matrix.
if [ -n "${TARGETS:-}" ]; then
  MATRIX="$TARGETS"
else
  MATRIX="$RELEASE_TARGETS"
  [ "${RELEASE_EXTRA_TARGETS:-0}" = "1" ] && MATRIX="$MATRIX $RELEASE_EXTRA_TARGETS_LIST"
fi

# The binaries: each `[[bin]]` stanza's name and path from aether.toml, so the
# manifest stays the one place a binary is declared. BINS=... narrows the set.
bin_table() {
  awk '
    /^\[\[bin\]\]/ { inbin=1; name=""; path=""; next }
    /^\[/          { inbin=0 }
    inbin && /^name *=/ { gsub(/.*= *"|".*/, ""); name=$0 }
    inbin && /^path *=/ { gsub(/.*= *"|".*/, ""); path=$0 }
    inbin && name != "" && path != "" { print name, path; name=""; path=""; inbin=0 }
  ' "$ROOT/aether.toml"
}
if [ -n "${BINS:-}" ]; then
  TABLE="$(bin_table | awk -v want=" $BINS " 'index(want, " " $1 " ")')"
else
  TABLE="$(bin_table)"
fi
[ -n "$TABLE" ] || die "no [[bin]] stanzas found in aether.toml (or BINS matched none)"

DIST="$ROOT/release/dist"
rm -rf "$DIST"; mkdir -p "$DIST"

# triple -> {os, arch, libc-suffix, extension} for the artifact name.
os_of()  { case "$1" in *-linux|*-linux-musl) echo linux;; *-macos) echo macos;; *-windows) echo windows;; *-freebsd) echo freebsd;; *) echo unknown;; esac; }
arch_of(){ case "$1" in aarch64-*) echo arm64;; x86_64-*) echo x86_64;; *) echo "$1";; esac; }
libc_of(){ case "$1" in *-musl) echo "-musl";; *) echo "";; esac; }
ext_of() { case "$1" in *-windows) echo ".exe";; *) echo "";; esac; }

say "tag: $TAG"
say "binaries: $(printf '%s\n' "$TABLE" | awk '{printf "%s ", $1}')"
say "matrix: $MATRIX"
echo

built=0; failed=0
for t in $MATRIX; do
  os=$(os_of "$t"); arch=$(arch_of "$t"); libc=$(libc_of "$t"); ext=$(ext_of "$t")

  # Only the FreeBSD target gets its sysroot; other targets must not compile
  # against FreeBSD headers just because the host provides them. FreeBSD needs a
  # base sysroot; skip loudly rather than fail if it's absent.
  target_sysroot=""
  if [ "$os" = "freebsd" ]; then
    target_sysroot="${AETHER_SYSROOT:-}"
    if [ -z "$target_sysroot" ]; then
      say "SKIP $t — set AETHER_SYSROOT to a FreeBSD base sysroot (see aether-crossbuild)"
      continue
    fi
  fi

  while read -r bin path; do
    [ -n "$bin" ] || continue
    name="${bin}-${TAG}-${os}-${arch}${libc}${ext}"
    out="$DIST/$name"
    log="$DIST/.$t.$bin.log"
    printf 'release:   %-18s %-22s -> %s ... ' "$t" "$bin" "$name"
    # --size: -Oz, no debug info, stripped — a shipped artifact. The binaries use
    # the net/os/fs capabilities of an executable, which --target grants as for a
    # native build (--with is only for --emit=lib).
    if ( AETHER_SYSROOT="$target_sysroot" ae build --size --target="$t" -o "$out" "$path" ) >"$log" 2>&1 \
       && [ -s "$out" ]; then
      ( cd "$DIST" && sha256sum "$name" > "$name.sha256" )
      printf 'ok  (%s)\n' "$(file -b "$out" 2>/dev/null | cut -c1-42)"
      built=$((built+1))
      rm -f "$log"
    else
      printf 'FAILED\n'
      sed 's/^/release:     /' "$log" 2>/dev/null | grep -iE 'error|fatal' | head -3
      failed=$((failed+1))
    fi
  done <<< "$TABLE"
done

# A combined checksum manifest over every artifact (not the .sha256 sidecars).
# Named SHA256SUMS.txt so a browser renders it inline (no forced download).
( cd "$DIST" && find . -maxdepth 1 -type f ! -name '*.sha256' ! -name '.*' ! -name SHA256SUMS.txt -printf '%f\n' \
    | sort | xargs -r sha256sum > SHA256SUMS.txt )

echo
say "built $built artifact(s) into release/dist/ ($failed failed)"
[ "$failed" -eq 0 ] || exit 1
