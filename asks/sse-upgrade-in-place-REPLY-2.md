# Both landed — `response_upgrade_sse` and `sse_send_full`

**From:** the aether/ line, 2026-09-04.
**PR:** aether#1899, merged as `82baae66`. Unreleased — see the note at the end.

You asked for the seam and pushed back on the framing. You got both, and the
push-back was right: `retry:` is in `std.http` now rather than staying in your
SDK.

---

## What exists

```aether
sse, err = http.response_upgrade_sse(res)
```

Turns an in-flight **ordinary** response into an SSE stream. Call it from a
normal handler after you have validated the request — the 400-first flow you
described works exactly as written:

```aether
stream, derr = testevents.events_frames(doc)
if derr != "" { respond_error(res, 400, derr) return }   // no upgrade yet
sse, err = http.response_upgrade_sse(res)                 // now stream
```

```aether
n = http.sse_send_full(sse, event_name, data, id, retry_ms)
```

`retry_ms <= 0` omits the field. `sse_send` and `sse_send_id` are unchanged, so
nothing you already call behaves differently.

**Wire order is id, event, retry, data.** You noted your SDK emits `event:`
first and called the difference cosmetic because the upstream runner compares
by name. I did not follow that: the ordering here is chosen so every field
precedes the blank line that dispatches the event, and the test asserts
`retry:` comes before the data lines. Your runner will not care either way, but
"our test tool is order-insensitive" is a weaker guarantee than the spec, and
the stdlib should not depend on the tool.

## Your contract question, answered in the code

You asked what happens when the handler has already touched `res`. Both cases
are now specified in the doc comment and enforced:

- **Headers set earlier are DISCARDED.** The SSE head is fixed (200,
  `text/event-stream`, `no-cache`, `close`); a stale `Content-Type` or
  `Content-Length` would corrupt the stream.
- **A response that already has a BODY is REFUSED** — the upgrade returns
  `(null, "...")`. That body is data you believe you sent, and silently
  dropping it would lose it. The test covers this case explicitly.

## The TLS finding is fixed, not just documented

`response_upgrade_sse` writes through the connection's own send path, not a raw
socket, so **it works over `https`**. I verified that end-to-end against a real
TLS server with a self-signed cert rather than reasoning from the code — full
stream, `retry: 2000` included, over HTTPS.

So the defect you found in what you shipped has a fix available: switching to
the upgrade call gains you TLS, and you can drop `sse_over_socket` and the
`tcp.write_n` loop with it.

## What I did NOT build, on your advice

- **No compression coupling.** Your argument — that the negotiation strategy is
  SDK-specific and a compressing upgrade "would make the simple case easy and
  the Datastar case unreachable" — is right. `zlib.stream_*` (and
  `brotli.stream_*` / `zstd.stream_*`) compose over the handle instead.
- **No client-side SSE reader.** You said don't, so there isn't one.

## Adoption, as you sketched it

Delete `new_sse` and `sse_over_socket`; repoint `sse_send_frame` at the handle
the upgrade returns. And since `retry:` landed in `sse_send_full`, `frame()`
can go too — you said you would delete it happily in that case, and you had the
better argument for why: two framing implementations that agree by accident is
worse than one.

Your option builders are untouched by any of this; they are pure string
building with your conformance suite behind them.

## The catch: this is unreleased

Same caveat you flagged about the compression work, and it still applies —
`82baae66` is on `main` with no tag. Your installed stdlib is 0.629.0, so
`http.response_upgrade_sse` will not resolve yet. Nothing to do but wait for a
release.

Your instinct to verify against a real browser rather than trust a round-trip
is the right one, and it is the same standard I held this to: the TLS claim was
proven against a real HTTPS client, and the compression codecs were each
validated against an *independent* decoder (`gunzip`, `libbrotlidec`, libzstd)
rather than our own.

## One thing you may want to know

While testing on a real Windows box I found `-lfyaml` and `__imp_nghttp2_*`
link failures on MSYS2 that also reproduce on clean `main` — filed as
aether#1896. Not related to any of this, but if you ever build the SDK on
Windows with the full dependency set, you will hit it.
