# Orientation for an LLM working on datastar-aether

A map of what isn't obvious from a first read: what this repo is, how the
pieces fit, the traps that have actually cost time here, and how to run
things. Prefer the code and `git log` as the source of truth whenever this
file disagrees with them.

## What this is, in one paragraph

An [Aether](https://github.com/aether-lang-dev/aether) SDK for
[Datastar](https://data-star.dev) — hypermedia UIs where the server pushes
DOM patches and signal updates to the browser over SSE. Ported from the
Datastar **Go** SDK, and held to the same cross-SDK conformance suite every
other Datastar SDK passes. No Go source remains; the port is the repo.

## Layout

```
datastar/module.ae            the SDK: wire-format engine + transport
datastar/testevents/          decoder for the conformance suite's event JSON
cmd/testserver/               the server the upstream Go runner drives
cmd/harness/                  the component-testing harness (port 4321)
cmd/examples/                 helloworld, hotreload
harness/page/                 shared page shell for mounted components
harness/components/           one directory per component rectangle
harness/stub/                 the stubbed backends those components talk to
harness/stories/              named component states (the workbench's data)
harness/workbench/            the story browser UI
tests/golden/                 vendored upstream conformance goldens
tests/*.ae                    offline suites (conformance, unit, streaming, TLS)
tests/component/              Selenium suites driving a real browser
tests/fixtures/               servers the tests spawn
asks/                         correspondence with the Aether language repo
```

## The one structural idea

The SDK is **two halves that never mix**: a pure wire-format engine whose
functions take strings and return strings, and a thin transport that pushes
bytes. Everything protocol-shaped is testable with no socket, no port and no
network — which is why the conformance suite is a plain offline test.

When you add a send verb, it goes through `*_parts` (build the datalines) and
then either `frame()` (render to a string, for tests) or `sse_send_lines`
(hand to the stdlib, for the wire). **One source of datalines.** Do not add a
second path that builds datalines independently — two implementations that
agree by accident is the failure mode this structure exists to prevent.

## Traps that have actually cost time here

Each of these cost an hour or more. They are all still live.

- **Datastar attributes are colon-separated.** `data-on:click`,
  `data-bind:card.num`. The hyphen form silently binds nothing — no console
  error, the handler just never fires.
- **Signal names must be all-lowercase.** The DOM lowercases attribute names,
  so `data-bind:card.expMM` binds `card.expmm`. The field stays empty and the
  component reports a validation error for input you can see on screen.
- **A stale server on a port makes a green run meaningless.** The upstream Go
  runner has a dead `-server` flag (it reads `TEST_SERVER_URL` into a
  package-level var, which initialises before `main()`'s `Setenv`), so it
  always hits `localhost:7331`. A leftover process there will be tested
  instead of your build, and it will pass. Check the server bound before
  trusting a result.
- **`webdriver.find` returns `""` for not-found**, and the natural helper
  early-returns on it. A typo'd element id then makes a test pass through
  doing nothing. `tests/component/test_workbench.ae` fails loudly instead —
  copy that shape.
- **`#card-status` is not `#card-message`.** The status element holds
  `ok`/`empty`/`declined`; the message element holds the human text. Asserting
  on the wrong one is a confusing failure that looks like a component bug.
- **A click returns before a server-push app has re-rendered.** `wait_text`
  does the real waiting, but the first poll can read a pre-patch DOM. The
  suites `sleep(60)` after a click for this reason.

## Aether idioms this repo leans on

Read `../aether/LLM.md` first if you have not. Specific to here:

- **Options bags are heap-boxed structs**, not maps. `std.map` stores `ptr`,
  so putting an int in one segfaults. Every options struct starts with the
  same two fields (`event_id`, `retry_ms`) — that prefix is load-bearing.
- **Zero-arg option builders need an explicit null check.** A builder called
  with no trailing block gets a null `_builder`, so `element_options()` alone
  would return null and every setter on it would silently no-op.
- **`const` initialisers must be compile-time constant.** A const built by
  interpolating another module's value fails with a type error pointing at an
  inlined line number. Use a function.
- **A name declared inside a closure collides with an outer one declared
  *after* the closure.** Renaming either fixes it. Logged as issue #2 in
  `aether-issues.txt`; it bit the TLS fixture and a component test.

## Running things

```
task test              # everything offline: conformance, units, streaming, TLS
task test-component    # Selenium suites against a freshly started harness
task harness           # just the harness, for poking by hand at :4321
task test-upstream     # the real Go runner (needs Go, and task test-server)
```

The component suites need a browser and skip without one. Set
`COMPONENT_TESTS_REQUIRED=1` in CI so a missing browser is a failure — a skip
that reports as a pass is how a suite quietly stops testing anything.

Requires Aether **0.635.0** or later. Several fixes in 0.629–0.635 were made
at this port's request; `README.md` has the table and `aether-issues.txt` the
detail.

## The component harness and workbench

`cmd/harness` mounts each component **alone**, with its slow backends replaced
by stubs a test configures over `/_harness/*`. This is
[UI component testing](https://paulhammant.com/2017/02/01/ui-component-testing/):
the smallest rectangle, a harness that never ships, gray-box assertions on
what the component *asked its backend*, not just what it rendered.

The workbench (`/w`) adds named states. A story is one row in
`harness/stories/module.ae` — id, component, title, setup JSON, note — and
opening its URL resets the harness, applies the setup through the same
control surface a test uses, and serves the component. Adding a story is one
line. The story list is meant to read as the component's specification.

Stories configure the world through the real control surface on purpose. If
they used a private path they would stop being evidence about the real thing.

## Testing philosophy, since it explains otherwise-odd choices

**Mutation-test anything that matters.** Several suites here were written,
passed, and were then proven vacuous by deliberately breaking the code they
covered. That is how the stale-cache bug was found, and how a retry-suppression
gap was found after the SSE migration. If you add a test, break the thing it
covers and watch it fail before you trust it.

**Count what reaches the wire, not what a function returned.** A duplicate-send
bug produced a correct-looking return value because the second write won. Only
frame counting caught it.

**Verify claims against the code, including your own.** This repo's history
contains several corrections where a confident earlier statement turned out to
be wrong — a workaround kept after upstream fixed it, a "regression" that was
actually a different bug. Check before asserting, and correct the record when
you were wrong.
