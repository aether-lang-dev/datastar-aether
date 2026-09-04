# Golden conformance fixtures

Vendored verbatim from the Datastar monorepo,
[`sdk/tests/golden`](https://github.com/starfederation/datastar/tree/repo-per-sdk/sdk/tests),
which is the cross-SDK conformance suite: every Datastar SDK, in every
language, must reproduce these streams.

Each case is a directory holding

- `input.json` — the `{ "events": [ ... ] }` document the suite sends,
- `output.txt` — the SSE stream the SDK must produce for it.

`tests/test_conformance.ae` runs all of them offline, against the
wire-format engine, with no server and no network. `cmd/testserver`
serves the same decoder over HTTP for the upstream runner, so the two
agree by construction.

To refresh from upstream:

```sh
task test-golden-update
```
