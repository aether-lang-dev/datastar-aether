#!/usr/bin/env bash
# Cut a GitHub Release for a tag and attach the cross-built binaries + their
# checksums. Manual, CLI-only — no GitHub Actions, no repo settings, no secrets:
# it uses your existing `gh` auth to create the release and upload assets.
#
# Usage:
#   release/publish.sh v1.2.3               # build (if needed) + create the release
#   release/publish.sh v1.2.3 --draft       # create as a draft to review first
#   release/publish.sh v1.2.3 --prerelease  # mark as a pre-release
#   release/publish.sh v1.2.3 --no-build    # use whatever is already in release/dist
#
# Steps: check every version pin agrees with <tag> (release/.version.ae), refuse a
# dirty tracked tree, build the matrix unless --no-build, then
# `gh release create <tag>` at the exact commit built, with every artifact, its
# .sha256, and SHA256SUMS.txt.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DIST="$ROOT/release/dist"
cd "$ROOT"

export PATH="${AETHER_HOME:+$AETHER_HOME/bin:}${PREFIX:-$HOME/.local}/bin:$HOME/.aether/bin:$PATH"

say() { printf 'publish: %s\n' "$*"; }
die() { printf 'publish: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

TAG=""; NO_BUILD=0; GH_FLAGS=()
for a in "$@"; do
  case "$a" in
    --no-build)   NO_BUILD=1 ;;
    --draft)      GH_FLAGS+=(--draft) ;;
    --prerelease) GH_FLAGS+=(--prerelease) ;;
    -*)           die "unknown flag: $a" ;;
    *)            [ -z "$TAG" ] && TAG="$a" || die "unexpected arg: $a" ;;
  esac
done
[ -n "$TAG" ] || die "usage: release/publish.sh <tag> [--draft] [--prerelease] [--no-build]"
case "$TAG" in v*) ;; *) die "tag should look like vX.Y.Z (got '$TAG')" ;; esac

have gh  || die "gh (GitHub CLI) not found — install it, or upload release/dist/* by hand"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run 'gh auth login'"
have aeb || die "aeb not on PATH — release/.version.ae is an aeb node (run ./bootstrap.sh)"

# Every version pin must already name this tag: DATASTAR_AETHER_VERSION,
# aether.toml, Taskfile.yml and the README's release link. Prepare them with
# DS_RELEASE_SET and commit BEFORE tagging, so the tagged tree says its own
# version.
DS_RELEASE_TAG="$TAG" aeb release/.version.ae \
  || die "version pins disagree with $TAG — prepare them with: DS_RELEASE_SET=$TAG aeb release/.version.ae"

# One release serves BOTH consumers of this repo:
#   - source consumers (`ae add <repo>@<tag>` = git clone + `git checkout <tag>`)
#     get the SDK tree AT THE TAGGED COMMIT;
#   - binary consumers get the cmd/ executables built HERE.
# So the tag and the binaries must be the SAME code. Pin the tag to the exact
# commit we build, and refuse to build from a dirty tracked tree (untracked
# scratch is fine).
COMMIT="$(git rev-parse HEAD)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  die "working tree has uncommitted TRACKED changes — commit or stash them so the
       tag ($TAG @ ${COMMIT:0:9}) and the built binaries are the same code
       (untracked files are fine; use 'git status' to see what's dirty)"
fi

if [ "$NO_BUILD" = "0" ]; then
  say "building artifacts for $TAG …"
  RELEASE_TAG="$TAG" "$HERE/build.sh" || die "build failed — fix it, or --no-build to publish existing dist"
fi

# Collect what to upload: every artifact, its sidecar, and the manifest.
shopt -s nullglob
bins=()
for f in "$DIST"/*; do
  case "$(basename "$f")" in
    .*|*.sha256|SHA256SUMS.txt) ;;
    *) bins+=("$f") ;;
  esac
done
sums=( "$DIST"/*.sha256 )
manifest=( "$DIST"/SHA256SUMS.txt )
shopt -u nullglob
[ "${#bins[@]}" -gt 0 ] || die "no artifacts in release/dist — run release/build.sh (or drop --no-build)"
for f in "${bins[@]}"; do
  [ -f "$f.sha256" ] || die "missing checksum sidecar $f.sha256 — re-run release/build.sh"
done
assets=( "${bins[@]}" "${sums[@]}" "${manifest[@]}" )

# The os-arch combinations shipped — derived from the artifact names, so this
# stays true as the matrix grows or shrinks.
plats="$(
  for f in "${bins[@]}"; do
    b="$(basename "$f")"; b="${b%.exe}"
    printf '%s\n' "${b#*-v[0-9]*.[0-9]*.[0-9]*-}"
  done | sort -u | awk 'NR>1{printf ", "} {printf "%s", $0} END{if (NR) print ""}'
)"
notes="Cross-built binaries of this SDK's \`cmd/\` programs — ${#bins[@]} artifact(s) over ${plats} — each with a \`.sha256\` (and a combined \`SHA256SUMS.txt\`).

- \`datastar-testserver-*\` — the server the upstream Datastar SDK conformance runner drives.
- \`datastar-helloworld-*\`, \`datastar-hotreload-*\` — the two examples.

The SDK itself is consumed as source: \`ae add github.com/aether-lang-dev/datastar-aether@$TAG\`. This tag and these binaries are the same code (built from ${COMMIT:0:9}). Built from a single Linux host via \`ae build --target\`; see \`release/README.md\`."

say "creating release $TAG (tag -> ${COMMIT:0:9}) with ${#assets[@]} asset(s)$([ "${#GH_FLAGS[@]}" -gt 0 ] && echo " (${GH_FLAGS[*]})") …"

# --target "$COMMIT": create the tag at the exact commit we built, NOT at the
# remote default-branch HEAD (gh's default).
gh release create "$TAG" "${GH_FLAGS[@]}" \
  --target "$COMMIT" \
  --title "$TAG" --notes "$notes" \
  "${assets[@]}" \
  || die "gh release create failed"

printf 'publish: done — %s\n' "$(gh release view "$TAG" --json url -q .url 2>/dev/null || echo "$TAG created")"
