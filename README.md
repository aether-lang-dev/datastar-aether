<p align="center"><img width="150" height="150" src="https://data-star.dev/static/images/rocket-512x512.png"></p>

# Datastar Aether SDK

An [Aether](https://github.com/aether-lang-dev/aether) SDK for
[Datastar](https://data-star.dev) — hypermedia-driven UIs, where the
server pushes DOM patches and signal updates to the browser over
Server-Sent Events.

Ported from the [Datastar Go SDK](https://github.com/starfederation/datastar-go),
and verified against the same cross-SDK conformance suite every other
Datastar SDK is held to: **20/20 upstream golden cases pass**, both
offline and over HTTP against the upstream runner.

## License

MIT, as the Go SDK it was ported from. Copyright is shared: the
wire-format behaviour, the option surface and the vendored conformance
goldens are derived from Star Federation's work and stay theirs; the
Aether implementation, tests and harness are mine. Both under the same
terms — see [LICENSE](LICENSE).

## Requirements

Aether **0.631.0** or later, and `contrib.tinyweb` for the examples'
routing (it ships with a standard Aether install).

Three fixes this SDK depends on, all upstream:

| version | what it fixed for us |
|---|---|
| [0.629.0](https://github.com/aether-lang-dev/aether/pull/1881) | an E0200 false positive that took out the native WebDriver binding, so the component tests could not compile |
| [0.630.0](https://github.com/aether-lang-dev/aether/pull/1886) | a stale-cache bug that let a suite report green against code it never compiled |
| [0.631.0](https://github.com/aether-lang-dev/aether/pull/1888) | a value-returning builder running its body twice — for a send verb, every event went out twice |

The SDK's core builds on older toolchains; the `*_with` verbs and the
component tests do not.

## Usage

```aether
import contrib.tinyweb
import datastar

main() {
    server = tinyweb.web_server_host("localhost", 8080) {

        tinyweb.end_point(tinyweb.GET, "/updates") |req: ptr, res: ptr, ctx: ptr| {
            // Read the client's signal store off the request.
            signals, err = datastar.read_signals(req)
            if err != "" { return }
            defer json.json_free(signals)

            // Upgrade the response to an event stream.
            sse, serr = datastar.new_sse(res)
            if serr != "" { return }
            defer datastar.sse_close(sse)

            // Patch elements into the DOM.
            _e1 = datastar.patch_elements(sse, "<div id=\"output\">Hello!</div>", null)

            // Patch signals (client-side state).
            _e2 = datastar.patch_signals(sse, "{\"count\":1}", null)

            // Run a script, or send the browser somewhere else.
            _e3 = datastar.console_log(sse, "hello from the server")
            _e4 = datastar.redirect(sse, "/next-page")
        }
    }
    tinyweb.tw_start(server)
}
```

### Options

Go's variadic functional options become an options bag. The shortest form
puts the block on the call itself:

```aether
err = datastar.patch_elements_with(sse, "<div>appended</div>") {
    datastar.with_selector("#target")
    datastar.with_mode_append()
}
```

`patch_elements_with` / `patch_signals_with` / `execute_script_with`
build the bag, let the block fill it, send, and release it. They need
Aether 0.631.0 or later — before that, a value-returning builder in
assignment position ran its body twice
([aether#1888](https://github.com/aether-lang-dev/aether/pull/1888)),
which for a send verb meant every event went out twice.

Where a bag is reused across several sends, build it once:

```aether
opts = datastar.element_options() {
    datastar.with_selector("#target")
    datastar.with_mode_append()
    datastar.with_view_transitions()
    datastar.with_retry_duration(2000)
}
defer datastar.element_options_free(opts)

err = datastar.patch_elements(sse, "<div>appended</div>", opts)
```

Pass `null` instead for all-defaults, which allocates nothing. A bag is
reusable across a stream — build it once outside the loop.

There are three bags, one per event kind:

| Constructor | Setters | Free with |
|---|---|---|
| `element_options()` | `with_selector`, `with_selector_id`, `with_mode*`, `with_namespace*`, `with_view_transitions`, `with_view_transition_selector`, `with_event_id`, `with_retry_duration` | `element_options_free` |
| `signal_options()` | `with_only_if_missing`, `with_event_id`, `with_retry_duration` | `signal_options_free` |
| `script_options()` | `with_auto_remove`, `with_script_attribute`, `with_script_attribute_kv`, `with_event_id`, `with_retry_duration` | `script_options_free` |

### The wire format, without a server

The SDK splits in two: a pure format engine and a thin transport. The
engine is string-in, string-out, so you can see and test exactly what
goes on the wire with no socket involved:

```aether
frame = datastar.patch_elements_frame("<div>hi</div>", null)
// event: datastar-patch-elements
// data: elements <div>hi</div>
//
```

`patch_elements_frame`, `patch_signals_frame` and
`execute_script_frame` are what the conformance suite asserts against.

## Examples

| Example | What it shows |
|---|---|
| [`cmd/examples/helloworld`](cmd/examples/helloworld) | Streaming a message a character at a time, at a delay the client's signal controls |
| [`cmd/examples/hotreload`](cmd/examples/hotreload) | Refreshing the browser once per server start, so a file watcher gives you live reload |
| [`cmd/testserver`](cmd/testserver) | The SDK conformance server the upstream cross-SDK runner drives |

```sh
task hello        # http://localhost:1337
task hotreload    # http://localhost:9001
```

## Testing

```sh
task test              # everything
task test-conformance  # just the 20 upstream golden cases
task test-unit         # just the SDK unit tests
task test-streaming    # just the streaming integration check
```

Three layers, each covering what the others cannot:

- **Conformance** — the 20 upstream goldens, replayed offline.
- **Units** — the API around the wire format: validators, option bags,
  convenience verbs, `url_decode`, `json_quote`.
- **Streaming** — spawns a real server that emits four patches 250ms
  apart and times their arrival. A transport that buffered every event
  and flushed once at the end would pass all 20 goldens and be useless
  for what Datastar is for; this is the only check that sees it.

`tests/golden/` is vendored from the Datastar monorepo and is the same
oracle every Datastar SDK is measured against.
`tests/test_conformance.ae` replays it offline — no server, no port, no
network — with one test case per golden.

To run the real upstream runner against this SDK over HTTP (needs a Go
toolchain):

```sh
task test-server       # terminal 1: serves :7331
task test-upstream     # terminal 2: the upstream Go runner
```

Both paths share one event decoder (`datastar/testevents`), so the
offline suite and the HTTP server cannot drift apart.

### A note on the test cache

Aether 0.630.0 and later need no special handling. Before that, `ae run`
did not invalidate its cache when the entry file sat in a subdirectory
and the edited module resolved from the project root — which is exactly
`tests/<suite>.ae` importing `datastar/` — so a suite could report green
against code it never compiled. If you are pinned to an older toolchain,
`rm -rf ~/.aether/cache` before each run. Fixed upstream in
[aether#1886](https://github.com/aether-lang-dev/aether/pull/1886).

## Parity with the Go SDK

Everything the conformance suite exercises is here, plus the whole
option surface, the convenience verbs (`console_log`, `console_error`,
`redirect`, `replace_url`, `prefetch`, `dispatch_custom_event`), and
both `read_signals` paths.

Three groups of Go API are deliberately absent:

| Go | Why it is not here |
|---|---|
| `Context()`, `WithContext` | Go's `context.Context` has no Aether analogue. `sse_is_closed` covers the "is this connection still alive" use. |
| `PatchElementTempl`, `PatchElementGostar` | Adapters for two Go template engines. An Aether template renders to a string, which `patch_elements` already takes. |
| `PatchElementf`, `RemoveElementf`, `ConsoleLogf`, `Redirectf`, `WithSelectorf` | The `-f` variants exist because Go needs `fmt.Sprintf`. Aether interpolates in the literal: `ds.remove_element(sse, "#row-${id}")`. |
| `MarshalAndPatchSignals` | Marshals a struct by reflection. Aether has none; build the JSON with `std.json` and call `patch_signals`. |

One group is a genuine gap rather than a choice:

**SSE compression is not implemented.** The Go SDK can gzip/deflate/
brotli/zstd the event stream. In the Aether releases this SDK targets,
brotli and zstd are absent, and — the real blocker — `std.zlib` is
one-shot: it opens, finishes and closes
a stream per call. Compressing SSE needs one stream held open for the
life of the connection and flushed per event; compressing each event
separately yields streams no browser will decode. Rather than ship
something that looks like compression and breaks clients, this is left
out and written up in [`aether-issues.txt`](aether-issues.txt).

Streaming deflate — plus brotli and zstd — is in flight upstream on a
feature branch with the API this port asked for. Once it reaches a
release, compression here becomes a negotiation layer over the existing
send verbs rather than a redesign.

## Design notes

**HTTPS is not supported yet.** `new_sse` takes the raw socket via
`http.response_accept_tunnel`, which refuses a TLS-wrapped connection,
so an endpoint served over HTTPS fails at runtime with "failed to take
over connection for SSE". Aether 0.634.0 added
`http.response_upgrade_sse`, which writes through the connection's own
send path and works over TLS; migrating to it is the fix and is
[written up in full](asks/sse-upgrade-in-place-REPLY.md).

**Why not `http.server_sse`?** Two reasons, one of which has since
been fixed. It registers a whole *route* as SSE, so the decision is made
before the body is parsed — but a Datastar handler must be able to
answer 400 on a malformed body and only then stream. And until 0.634.0
it could not emit a `retry:` line at all, which 5 of the 20 conformance
goldens require. So this SDK registers an ordinary route and calls
`http.response_accept_tunnel` to take the socket, which gives it every
byte after the response head.

Aether 0.634.0 closed both gaps — `http.response_upgrade_sse` is the
upgrade-in-place seam, and `http.sse_send_full` carries `retry:` — so
the raw-socket approach is no longer the only option. See the
[reply to that ask](asks/sse-upgrade-in-place-REPLY.md).

**Aether issues found while porting** are logged in
[`aether-issues.txt`](aether-issues.txt), with minimal reproducers.

## Contributing

Contributions welcome. Please keep `task test` green.
