# release — cross-built binaries + GitHub Releases

This repo ships two things from one tag:

- **The SDK, as source.** `ae add github.com/aether-lang-dev/datastar-aether@<tag>`
  clones the repo at the tag; `aether.toml`'s `[package]` is what a consumer
  gets. No binary is involved — the tag *is* the release.
- **The `cmd/` binaries, cross-built.** Every `[[bin]]` in `aether.toml` (the
  conformance test server and the two examples), one executable per platform,
  each with a `.sha256`, attached to the GitHub Release for that tag.

Everything here is pure Aether, so the binaries **cross-compile for the whole
platform matrix from one Linux host** (`ae build --target`, zig cc backend) — no
per-OS runner. This is the same build-here / verify-by-hash model as
[selenium](https://github.com/aether-lang-dev/selaenium),
[servirtium-vcr](https://github.com/aether-lang-dev/servirtium-vcr) and
[libphonenumber-ae](https://github.com/aether-lang-dev/libphonenumber-ae), and
the scripts are ported from theirs.

## Build

```sh
release/build.sh                          # core matrix: linux glibc/musl + macos, x86_64 + arm64
RELEASE_TAG=v1.2.3 release/build.sh       # stamp a tag into the artifact names
RELEASE_EXTRA_TARGETS=1 release/build.sh  # + windows (slow) + freebsd (needs AETHER_SYSROOT)
TARGETS="aarch64-macos" release/build.sh  # just one target
BINS="datastar-testserver" release/build.sh   # just one binary
```

Needs `ae` + `zig` on PATH (`./bootstrap.sh` installs the pinned `ae`; zig is
the version in `ci/versions.env`'s siblings) and `sha256sum`. Outputs into
`release/dist/` (gitignored):

- `<bin>-<tag>-<os>-<arch>[-musl][.exe]` — the artifact
- `<artifact>.sha256` — its checksum (sidecar)
- `SHA256SUMS.txt` — all artifacts in one manifest

Each is built `--size` (-Oz, stripped). The tag defaults to the repo-root
`DATASTAR_AETHER_VERSION` file.

## Version pins: `release/.version.ae`

The release version is spelled in four places — `DATASTAR_AETHER_VERSION`,
`aether.toml`'s `version`, `Taskfile.yml`'s `VERSION` and the README's release
link — and they must agree. `release/.version.ae` is an
[aeb](https://github.com/aether-lang-dev/aeb) node that checks or sets them
together; it is the only thing in this repo that needs `aeb`.

```sh
aeb release/.version.ae                         # check every pin against DATASTAR_AETHER_VERSION
DS_RELEASE_TAG=v0.2.0 aeb release/.version.ae   # check every pin against v0.2.0
DS_RELEASE_SET=v0.2.0 aeb release/.version.ae   # prepare a release: rewrite every pin
```

Each pin is anchored to its surrounding text (one row in the node's `PINS[]`
table), so a stale doc fails the check and historical mentions are never
rewritten. Setting is all-or-nothing: every pin is found and counted before any
file is written. **Never add this node to a target set in set mode** — it
rewrites tracked source files. The node's output is in
`target/.aeb/logs/version_release.log`; a failure's reason is also in aeb's
console summary.

## Cut a GitHub release

Prepare the version, commit, then publish from that commit:

```sh
DS_RELEASE_SET=v0.2.0 aeb release/.version.ae
DS_RELEASE_TAG=v0.2.0 aeb release/.version.ae      # should now pass
task test                                          # the offline suites, on the tagged code
git commit -am '[release] prepare v0.2.0'
git push origin main
release/publish.sh v0.2.0                          # build the matrix + create the release
release/publish.sh v0.2.0 --draft                  # or: create as a draft to review first
release/publish.sh v0.2.0 --no-build               # or: attach whatever is already in release/dist
```

`publish.sh` re-checks the pins against the tag, refuses a dirty tracked tree,
builds (unless `--no-build`), then `gh release create <tag>` **at the exact
commit built** with every artifact, its `.sha256`, and `SHA256SUMS.txt`. It
uses your existing `gh` auth — nothing in GitHub Settings, no Actions, no
secrets. Choose a new unused version each time; an existing release is not
replaced.

After publication, download one artifact and check it against its `.sha256`: a
tag or release page alone does not prove the binaries are available.

## Why build-here / test-elsewhere

The build is deterministic and platform-agnostic (zig cross-compiles the exact
bytes every time), so building on Linux and running on the target are testing
*identical bytes* — there is no "works on my machine" gap. What a Linux host
cannot do is *run* an arm64-macOS binary. On-target verification is therefore
out of band: fetch a specific artifact by hash, run it on its platform, and
record that **that hash** worked. Because SHA256 identifies the exact bytes,
such a record is a durable claim about what users download.

## Not here

- **A tag-triggered GitHub Actions workflow.** selenium and servirtium-vcr have
  one; this repo publishes manually with `publish.sh`. Add a workflow when the
  release cadence justifies it, and disable manual publishing when you do, so
  the two publishers do not race on a tag.
- **A FreeBSD sysroot.** `x86_64-freebsd` is in the opt-in extras and skips
  loudly without `AETHER_SYSROOT`.
