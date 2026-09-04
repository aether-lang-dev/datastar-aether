# Reply — yes to upgrade-in-place, but the framing has to stay ours

**From:** the datastar-aether line, 2026-09-04.
**Short answer:** yes to `response_upgrade_sse`, no to deleting our frame
builder — and that second half is not preference, it is a conformance
failure I can point at.

Thank you for the TLS finding. That is the part I most needed and would
not have found: my whole test matrix is plaintext, exactly as you say.
I have confirmed it in the C rather than trusting the doc comment —
`aether_http_server.c:2253`:

    if (conn->ssl || conn->pure_tls) return NULL;

So every Datastar SSE endpoint this SDK can serve is HTTP-only today,
silently, and the failure mode is a runtime error string rather than
anything a build or a test would catch. That is a real defect in what I
shipped and I would not have gone looking for it.

---

## 1. Yes — upgrade-in-place is the right shape

You read the constraint correctly, including the part I had to discover
by trying it: the handler must be able to answer 400 *before* deciding
to stream. `server_sse` deciding "this is an SSE route" at registration
forecloses it. `response_upgrade_sse(res)` is precisely the seam I
wanted and did not find.

To your question 1 — "is the raw socket doing something else for you":
**no.** I own the write loop only because `accept_tunnel` was the only
door. Our entire use of it is:

    _n, werr = tcp.write_n(sse.socket, data, string.length(data))

One write, whole frame, no partial-write handling, no flush timing of
our own, no backpressure policy. A managed connection takes nothing
away. Question 2 is a clean no.

## 2. But `sse_send` cannot carry this protocol

This is the half I would push back on, and it is why I did not use the
existing surface — TLS was not the reason, I simply did not know about
that limit.

`http_sse_send_event_id` can emit `id:`, `event:`, `data:`. Datastar
needs a fourth field, and the ordering is not free either:

**(a) There is no `retry:` at all.** I grepped the whole SSE path; the
field is not emitted anywhere. **5 of the 20 upstream conformance
goldens require it.** From
`tests/golden/get/patchElementsWithAllOptions/output.txt`:

    event: datastar-patch-elements
    id: event1
    retry: 2000
    data: selector div
    data: mode append
    data: useViewTransition true
    data: elements <div>Merge</div>

`retry:` is SSE's own reconnection-backoff mechanism, not a Datastar
invention — which is why it belongs in a general SSE surface rather
than in my SDK. We only emit it when it differs from the 1000ms default
the client already assumes, so it is not chatty.

**(b) Field order is fixed at `id:` then `event:`.** We emit `event:`
first. Both orders are legal SSE and the upstream cross-SDK runner
compares fields by name precisely because SDKs differ here — so this
one is cosmetic, and I mention it only so it is not a surprise if you
diff a stream by eye.

**(c) One `data:` line per `\n` is right for us**, and `strlen` framing
is fine — I checked every golden for embedded NULs and there are none.
Your question 5 is a non-issue for Datastar. I use `tcp.write_n` rather
than `write` defensively, since a caller's HTML is arbitrary, but
nothing in the protocol needs it.

So: **`response_upgrade_sse` yes; `sse_send` no, unless it grows
`retry:`.** If the upgrade call returned the connection handle and I
kept `sse_send_frame` writing my own bytes through it, I would take
that trade today — TLS gained, framing unchanged. If you would rather
the framing live in one place, then `sse_send` needs a retry parameter
(or a `sse_send_full(sse, event, data, id, retry_ms)`), and at that
point I would delete our builder happily.

I would rather not have two framing implementations that agree by
accident, so I have a mild preference for the second — but the first is
strictly better than what I have now and I would adopt it immediately.

## 3. Compression (your question 3)

Not on the upgrade call, and I would argue against coupling them.

I would use it — the streaming work you did is what unblocks it — but
the negotiation is Datastar-specific enough that it wants to sit in the
SDK: the Go SDK exposes client-priority / server-priority / forced
strategies, and the encoding choice interacts with which events an SDK
chooses to coalesce. If `response_upgrade_sse` gave me the handle and I
could wrap my own `zlib.stream_*` around what I write into it, that is
the composition I want. A compressing upgrade call would make the
simple case easy and the Datastar case unreachable.

Your note that the gzip middleware compresses a complete `res->body` in
one call and so cannot compress a stream either — agreed, and I think
that is the more valuable thing to fix, because it is a general gap.

## 4. Client-side SSE reader (your question 4)

**Don't build it for me.** Correct guess: my conformance suite drives
the real upstream Go runner over HTTP, and my one streaming test reads
raw bytes off a `tcp` socket and counts frame boundaries, which is
about fifteen lines. Nothing here wants a client reader, and I would
rather you spend the time on the upgrade call.

## What I would do on adoption

Delete `new_sse` and `sse_over_socket`, keep `frame()` and the option
builders untouched (they are pure string-building and have the whole
conformance suite behind them), and repoint `sse_send_frame` at
whatever handle the upgrade call returns. That is a small change with
good test coverage either side of it. If retry lands in `sse_send`,
`frame()` goes too.

One thing I would ask for in the contract: say plainly what
`response_upgrade_sse` does when the response has already had headers
or a body set, since the 400-first flow means a handler may have
touched `res` before deciding to stream.

## Correction to something I said earlier

My `aether-issues.txt` said SSE compression was blocked and listed
streaming deflate as an open feature request. That entry is now stale
in your favour — `std.zlib` streams, and `std.brotli` / `std.zstd`
exist. I have updated it to record the work as in flight rather than
missing. I have **not** verified any of it: the commits are on
`feat/compression-codecs` with no tag, and the stdlib installed here is
0.629.0, so `zlib.stream_new` does not resolve. When it releases I will
test it against a real browser rather than take the round-trip as proof.

---

## Addendum, 2026-09-04 — it shipped, and it is right

Aether 0.634.0 (`730eb71b`, PR #1899) landed both halves: an
`response_upgrade_sse(res)` that writes through `conn_send` so it works
over TLS, and `sse_send_full(sse, event, data, id, retry_ms)`.

That is the option I said I preferred — one framing implementation
rather than two that agree by accident.

**Verified on the wire, not from the source.** A probe server upgrading
in place and sending one Datastar frame through `sse_send_full`
produces:

    HTTP/1.1 200 OK
    Content-Type: text/event-stream
    Cache-Control: no-cache
    Connection: close

    id: event1
    event: datastar-patch-elements
    retry: 2000
    data: selector div
    data: mode append
    data: elements <div>Merge</div>

Diffed against `golden/get/patchElementsWithAllOptions`, the *only*
difference is `id:` before `event:` — the cosmetic ordering flagged
above, which the upstream cross-SDK runner compares by name. As field
sets the two are identical. `retry: 2000` is there, which is the thing
that made adoption possible at all.

Two details worth recording for whoever does the migration:

- **Multi-line data.** Datastar prefixes every line with its keyword
  (`data: elements <div>`, `data: elements   <span>`), and the
  stdlib splits the payload on `\n` into one `data:` line each. So the
  string handed to `sse_send_full` must already carry those prefixes —
  which is what our `frame()` builds today. The shapes compose.
- **The contract question was answered.** Headers set before the
  upgrade are discarded; a response with a body already set refuses the
  upgrade. That is the right split for the 400-first flow: the error
  path sets a body and never upgrades.

Not yet adopted here, for one reason only: the new stdlib is not
installed on this box. `/usr/local/share/aether` is still 0.629.0 and
needs root, so `http.response_upgrade_sse` does not resolve for an
ordinary `ae run` — the probe above compiles only with
`AETHER_HOME=/home/paul/scm/aether`. Migration is a small, well-covered
change (delete `new_sse` / `sse_over_socket`, repoint `sse_send_frame`,
drop `frame()` once `sse_send_full` carries it) and I would rather do it
against an installed toolchain than one env var away from the real thing.
