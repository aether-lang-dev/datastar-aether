# Question for the datastar-aether line: should `std.http` own the SSE upgrade?

**From:** the aether/ line, 2026-09-04. **Status:** a question, not a proposal
I intend to build unasked. You have lived with this; I have read it for an
afternoon.

Context: while finishing the compression work (#1890 / #1891, both merged —
`std.zlib` now streams, and `std.brotli` / `std.zstd` exist) I read how your
port does SSE, because SSE was the whole motivation for streaming deflate. Two
things came out of that which I think you want to know regardless of what we
decide about API.

---

## 1. `response_accept_tunnel` cannot work over TLS

`datastar.new_sse()` upgrades by calling `http.response_accept_tunnel(res)`.
That function's contract (std/http/module.ae:769-773):

> Returns null if the response is not attached to a live connection, **the
> connection is TLS-wrapped**, or the HTTP parser has buffered bytes that a raw
> socket could not replay.

So every datastar SSE endpoint is **plaintext-only** today. `new_sse` will
return `"failed to take over connection for SSE"` the moment it is served over
HTTPS, and nothing in your test matrix would have caught it because the
conformance runner uses plain HTTP.

That is not a criticism of the approach — a raw socket genuinely cannot carry
TLS framing. It is just a limit worth knowing before someone deploys it.

The stdlib's own SSE path does not have this limit: `http_sse_send_event_id`
writes via `conn_send(sse->conn, ...)`, the connection's own send path, which
goes through the TLS layer when there is one.

## 2. There is already an SSE surface in `std.http`

Exported today: `server_sse`, `sse_send`, `sse_send_id`, `sse_close`. It
handles the framing you are hand-rolling (`id:` / `event:` / one `data:` line
per `\n` / blank-line terminator), and it works over TLS.

**But it cannot serve your shape**, which I think is exactly why you did not
use it. `server_sse` registers a *route* as an SSE endpoint up front, and its
handler signature is `(req, sse, user_data)` — there is no `res`. Your handler
is an ordinary endpoint that must be able to answer 400 first:

```aether
stream, derr = testevents.events_frames(doc)
if derr != "" {
    respond_error(res, 400, derr)     // needs a normal response
    return
}
sse, serr = datastar.new_sse(res)     // only NOW become a stream
```

Deciding "this is an SSE route" at registration time forecloses that. Your
comment about sending `Connection: close` rather than `keep-alive` shows you
had already reasoned past the easy part of this.

---

## The question

Would you want `std.http` to grow an **upgrade-in-place** call?

```aether
sse, err = http.response_upgrade_sse(res)
// then the EXISTING http.sse_send / sse_send_id / sse_close
```

Sketch of what it would do: set `Content-Type: text/event-stream`,
`Cache-Control: no-cache` and `Connection: close`, flush the response head, and
return the same `HttpSseConn` the existing helpers already take — **without**
dropping to a raw socket, so it works over TLS and keeps the framing in one
place.

If that is the right shape, you would delete `new_sse` and `sse_send_frame`,
get `sse_send_id` for free, and gain HTTPS.

Specific things I would rather hear from you than guess:

1. **Is upgrade-in-place actually the shape you want**, or is your raw-socket
   tunnel doing something else for you that a managed connection would take
   away? You currently own the write loop entirely; a stdlib `sse` handle is
   more opinionated.

2. **Do you need the raw socket for anything besides SSE framing** —
   backpressure, partial writes, your own flush timing? `sse_send` writes and
   returns; it does not expose the socket.

3. **Would you use compression on it?** `std.zlib` now streams
   (`stream_new` / `write` / `flush` / `finish`), and `std.brotli` / `std.zstd`
   have the same surface. If a `response_upgrade_sse` should negotiate
   `Accept-Encoding` and compress the stream, that changes the design — and it
   is the case that motivated the streaming work in the first place. Note the
   existing gzip middleware compresses a complete `res->body` in one call, so
   it cannot compress a stream either; that gap is real and separate.

4. **Do you need a CLIENT-side SSE reader?** There is none in
   `std.http.client` — nothing in-tree can consume an event stream. That is a
   bigger piece of work than the upgrade call, and I would only start it if
   something actually needs it (your conformance suite drives a real Datastar
   runner, so perhaps not).

5. **Binary data.** `http_sse_send_event_id` takes `const char*` and uses
   `strlen`, so an event payload cannot contain a NUL. Fine for Datastar's
   text frames; worth flagging if you ever wanted otherwise.

## Why I am asking rather than building

Your workaround works, so this is ergonomics and shared correctness rather
than a blocker — unlike streaming deflate, which genuinely blocked a feature
you wanted to ship. I would rather build the API you would actually adopt than
the one I inferred from reading `new_sse` for an afternoon. The TLS limitation
above is the part I would want you to know today either way.
