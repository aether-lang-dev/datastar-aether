# Component testing

Following [UI Component Testing][post] (Paul Hammant, 2017): test the
smallest rectangle you reasonably can, in a harness that never ships,
with the slow parts of the stack replaced by something instant. Aim for
multiple *tests* a second — not multiple clicks a second.

[post]: https://paulhammant.com/2017/02/01/ui-component-testing

## Why Datastar suits this unusually well

Two properties of Datastar make the harness cheap, where Angular in 2017
needed [ngWebDriver][ngwd] and a framework-specific bridge:

1. **There is no client-side component framework to boot.** A component
   is an HTML fragment plus the endpoints that patch it. Mounting one in
   isolation is just serving that fragment — no bundler, no build step,
   no app startup.

2. **The model is reachable without a framework bridge.** The post
   reaches for `ngWebDriver.mutate(el, "card", "{'num': 5105105105105100,
   ...}")` to push state into the model in one Selenium operation instead
   of typing into four fields.

   Datastar v1.0.3 exposes no global object to poke, and its
   `datastar-patch-signals` CustomEvent turns out to be one the client
   *emits*, not one it listens for (both checked in a real browser). So
   `wd_extra.set_signals` goes in through the door the client genuinely
   watches: `data-bind` subscribes to the `input` event, so setting each
   input's value and firing `input` puts the values into the signal store
   exactly as typing would — in one Selenium call instead of four rounds
   of `send_keys`.

   That is arguably a better test than poking a store directly, because
   it exercises the binding rather than bypassing it.

[ngwd]: https://github.com/paul-hammant/ngWebDriver

## The pieces

| Path | What it is |
|---|---|
| `harness/components/` | The registry: a catalogue plus `mount_all`. |
| `harness/components/card/` | Credit-card entry — validation, a slow processor, decline paths. |
| `harness/components/inbox/` | Filtered message list — server-rendered, patches elements. |
| `harness/page/` | The page shell every component is served in. |
| `harness/stub/cards/` | A *response* stub: one call in, one programmable verdict out. |
| `harness/stub/messages/` | A *data* stub: seed a corpus, query it. |
| `cmd/harness/` | The server, plus the `/_harness/*` control surface. |
| `tests/component/` | One suite per component. |
| `tests/component/harness_fixture/` | Session setup, harness control, and the fast/slow interaction verbs. |
| `tests/component/wd_extra/` | `send_keys` / `clear` (the Aether binding does not wrap them) and `set_signals`. |

**Adding a component** is a directory under `harness/components/`
exporting `mount`, `fragment` and `PATH`; two lines in the registry (an
import and a `mount` call); one catalogue row; and a `test_<name>.ae`.
The index page and the startup banner both read the catalogue, so it is
announced in both from that one row. If a rectangle needs a backend,
that is a module under `harness/stub/` and a verb on the control
surface.

**Two stub shapes, on purpose.** Rectangles sit on two kinds of slow
thing. `stub/cards` answers a call with a verdict a test configured
(*"the processor declines this one"*). `stub/messages` holds a corpus a
test seeded and answers queries against it. Bending either into the
other's shape makes the tests read worse.

## Running it

```sh
task test-component     # starts the harness, runs every suite, stops it
task test-component-ci  # same, but a missing browser/harness FAILS
task harness            # just the harness, for poking by hand at :4321
```

**Use `test-component-ci` on a build box.** Without
`COMPONENT_TESTS_REQUIRED=1`, a missing browser or harness prints
`SKIPPED` and exits 0 — right on a laptop that has no chromedriver, and
exactly how a suite quietly stops testing anything in CI. A skip that
reports as a pass is the same class of lie as a stale cache.

The browser is **headed**, deliberately — the Aether binding's
`remote()` sends no chromeOptions, so Chrome opens a real window and a
run is watchable (and recordable). The tests are not screenshot tests;
the window is for humans.

## The harness control surface

The part that makes a full-stack-awkward case into a one-liner:

```sh
# make the next authorization decline
curl -X POST localhost:4321/_harness/backend \
     -d '{"outcome":"decline","message":"Insufficient funds"}'

# make the processor slow, so the pending state is observable
curl -X POST localhost:4321/_harness/backend \
     -d '{"outcome":"approve","delayMs":600}'

# what did the component actually ask the backend for?
curl localhost:4321/_harness/calls
# {"calls":[{"pan":"************4242","expiry":"11/2031","amount":1000}],"count":1}

# clear between tests
curl -X POST localhost:4321/_harness/reset
```

`/_harness/calls` is the gray-box half the post says is worth the setup
cost. "The card failed the Luhn check, so the processor was never
called" is invisible from the DOM; here it is one assertion.

PANs are masked to the last four on the way into the recorder — a
harness that logged full card numbers would be a bad habit to teach even
with test data.

## What the tests cover

**19 tests over two rectangles.**

`test_card.ae` (9) — a form:

- *Validation, backend never called* — empty number, failed Luhn,
  out-of-range month, short security code. Each also asserts the
  processor was called **zero** times, proving the short-circuit.
- *Backend outcomes* — approval with the auth code surfaced, decline
  with the processor's reason, processor error, and the pending state
  made observable by telling the stub to be slow.
- *Real typing* — one test that types character by character, because
  the binding is what it is testing.

`test_inbox.ae` (10) — a list:

- *Listing and filtering* — all messages, filter across sender and
  subject, case-insensitivity, unread-only, and the unread class on
  markup the SDK put in the DOM.
- *Empty and error states* — nothing matches; a store failure that
  reports itself **without clearing the list** (a transient fault should
  not look like data loss); and recovery on the next search.
- *What it asked the store* — one query per search, and the unread flag
  reaching the backend. The DOM shows two items either way; only the
  query log proves the filtering happened server-side rather than by
  luck of the corpus.

That last group is the gray-box half the post argues is worth the setup
cost. It is also why the inbox exists: the card only ever provoked
`datastar-patch-signals`, so `patch_elements` — half the SDK — had never
been exercised through a browser.

## Speed — measured, not claimed

The post's target is multiple *tests* a second. Where this lands today,
headed, browser warm, on this machine:

```
 9 card  tests in ~4.2s   (~471ms each)
10 inbox tests in ~4.7s   (~473ms each)
```

Down from ~1.1s per test. Two changes got it there, and the profiling
that found them is worth repeating rather than guessing:

| phase | before | after |
|---|---|---|
| stub reset | 41ms | 41ms |
| page navigation | 67–163ms | 61–141ms |
| filling 4 fields | ~900ms (4× `send_keys`) | one round trip |
| clicking a button | 300–700ms | ~50ms |
| waiting for the patch | 23–47ms | 23–47ms |

**Filling.** `send_keys` types character by character over a WebDriver
round trip per field. `harness_fixture.fill_fast` sets the values and
fires `input` — the event `data-bind` subscribes to — in one call.

**Clicking.** A real WebDriver click does scroll-into-view, hit-testing
and a native input event. `click_fast` dispatches `el.click()` in-page:
one round trip, and the component's own `data-on:click` handler still
runs. It skips the browser's input plumbing, not the component's
behaviour.

Both have a deliberate exception. `test_card.ae` keeps one test that
types for real, because the *binding* is what it is testing — if
`data-bind` broke, only that test would notice. Use the slow verbs where
the interaction itself is under test; use the fast ones everywhere else.

Still ~470ms rather than the ~200ms the post's "multiple tests a second"
implies. The remainder is page navigation plus the one test that asks
the stub to be slow on purpose. Reusing the page between tests — reset
signals rather than re-navigate — is the next lever, and is left undone
because navigation is also what guarantees test isolation.

## The workbench

`task harness`, then open <http://127.0.0.1:4321/w>.

A component served alone shows one state: whatever it looks like on load.
The states worth reviewing are the others — the decline, the empty result,
the slow backend, the store that failed. Reaching those by hand means typing
into the component and configuring its stub every time, which is why they
usually go unreviewed.

A **story** names one of those states and makes it a URL:

    /w/card/declined      the card component, processor set to decline
    /w/inbox/empty        the inbox with an empty corpus
    /w/card/declined/raw  the same, with no workbench chrome

Opening it resets the harness, applies the story's setup, and serves the
component. So a state is a link: shareable in a review, bookmarkable while
working, and drivable by a test that wants to start somewhere other than the
beginning.

**Adding a story is one line** in `harness/stories/module.ae`:

    id | component | title | setup-json | note

The setup JSON is posted to the same `/_harness/*` endpoint a test uses.
That is deliberate — if stories had a private path into the stubs they would
stop being evidence about the real thing.

Two views on purpose. The framed one (`/w/<id>`) is for a person: notes,
metadata, one-click navigation between sibling states. The raw one
(`/w/<id>/raw`) is for a test and for a screen recording, where workbench
chrome would be a distraction. Same story, same setup, same component — so
what you review, what you record and what a test drives cannot diverge.

`tests/component/test_workbench.ae` checks that every story still does what
it claims. Not that the page loads — a story whose setup silently failed
still serves a 200 and a component — but that driving the component produces
the promised outcome. Mutation-tested: stop applying story setup and three
of its tests go red.

## Notes for whoever runs this next

- **Datastar attribute syntax is colon-separated**: `data-on:click`,
  `data-bind:card.num`. The hyphen form (`data-on-click`) silently does
  nothing — no console error, the handler just never binds. Verified in
  a real browser against both RC.7 and v1.0.3.
- **The bundle is pinned to `datastar@v1.0.3`**, the current release. The
  Go SDK's examples still point at `1.0.0-RC.7`.
- **Needs Aether 0.629.0 or later.** Earlier compilers hit an E0200
  false positive on `d = webdriver.remote(...)` — a typed pointer was not
  assignable to a bare `ptr`, which took out the whole native WebDriver
  binding. Fixed upstream in
  [#1881](https://github.com/aether-lang-dev/aether/pull/1881); the
  "never bind the session in the function that creates it" workaround
  this file used to document has been removed.
- **No cache workaround needed as of Aether 0.630.0.** Earlier versions
  did not invalidate `ae run`'s cache when the entry file was in a
  subdirectory and the edited module resolved from the project root —
  exactly this layout — so a suite could report green against code it
  never compiled. Fixed in
  [aether#1886](https://github.com/aether-lang-dev/aether/pull/1886);
  the `rm -rf ~/.aether/cache` that every task used to do first is gone.
- **Quitting the session does not stop the driver.** `webdriver.quit(d)`
  ends the browser; the `chromedriver` process that `driver.ensure`
  spawned keeps running, and nothing else holds a handle to it. Left
  alone that leaks one driver per suite run — 31 had piled up on this
  box, none with a browser attached, before the symptom (a run that
  hung instead of starting Chrome) made it obvious. `harness_fixture`
  now keeps the handle in a module `var` and calls `driver.stop` after
  `webdriver.quit`, so a run leaves nothing behind. Worth checking with
  a process count either side of a run if you fork this fixture.
