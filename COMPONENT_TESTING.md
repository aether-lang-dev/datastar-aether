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

## Where the Selenium binding comes from

The component tests need the Aether Selenium port — three directories
from it: `aether/` (the binding), `selenium_core/` (the engine) and
`selenium_core/drivermgr/` (driver resolution).

It is **not** hardcoded to a sibling checkout.
[`scripts/find-selenium.sh`](scripts/find-selenium.sh) resolves it at run
time, in this order:

1. **`$SELENIUM`** — an explicit answer. A wrong one fails loudly rather
   than silently falling through to something else.
2. **`../selaenium`, but only with `SELAENIUM_LOCAL=1`** — a sibling
   checkout, for the case where you are editing the binding alongside
   this repo. Never auto-detected; see below.
3. **`~/.aether/packages/<host>/<user>/selaenium`** — where `ae add`
   installs packages. This is the default. Note the depth: `ae add`
   stores by full source path, so the binding sits three levels below
   `packages/`, not two.

When none of them match, the script prints all three options and notes
that the offline suites need none of this — rather than failing as a
compile error about an unknown module, which is what a hardcoded path
gives you when it is wrong.

### The two ways to get it (A: published, B: local)

**A — buy it in, pinned (the reproducible default).** The port publishes
GitHub releases, so pin one by tag:

```sh
ae add github.com/aether-lang-dev/selaenium@v0.2.0
```

`ae add` is `git clone` + `git checkout <tag>`, so this lands the tree
**at that exact tag** under `~/.aether/packages/github.com/aether-lang-dev/selaenium`,
which is what the resolver's step 3 finds. A given tag is the same bytes
for everyone — CI and a teammate compile identical engine source. (The
release also carries prebuilt `libselenium_core.*` binaries; those are
for FFI consumers that `dlopen` the engine and are irrelevant here — the
component tests compile the `.ae` source in-graph.)

**B — develop it alongside, on the same box (opt-in).** If you are
editing the binding and want your edits under test without publishing,
point at your working tree:

```sh
task test-component SELENIUM=/home/you/scm/selaenium   # by path
SELAENIUM_LOCAL=1 task test-component                  # or take ../selaenium
```

**A sibling checkout is never picked up automatically**, and that is a
deliberate change from how this started.

It used to be auto-detected and to win over the package. The reasoning
was sound — someone editing the binding wants their edits under test —
but the mechanism was not: a working copy silently overriding a pinned
dependency is how a run goes green against engine changes committed on
one box and never pushed, and then fails in CI, which only has the
package.

It is also the same shape as the bug that left this script's package
branch dead for its first week: a fallback quietly doing something other
than what the caller assumed. Two mistakes (globbing two directory
levels instead of three, and spelling the repo `selenium` rather than
`selaenium`) meant the package was never found — and nobody noticed,
because the sibling fallback kept every run green on the one machine
that had both.

So B is now opt-in, and every run echoes `selenium binding: <path>` so
you can see which engine produced a result.

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
- **A chrome process right after a run is teardown, not a leak.** Chrome
  exits asynchronously, so a process count taken the instant a suite
  returns can show 1 where a count a second later shows 0. This was
  investigated at length on the strength of a `sleep 2` sample that
  caught it mid-shutdown; four hypotheses (SSE keeping it alive, the
  Datastar bundle, an interaction that opens a stream, multiple sessions
  per process) were each tested and each disproved before the timing
  itself turned out to be the artefact. If you measure this, sample
  repeatedly and let it settle.
- **Quitting the session does not stop the driver.** `webdriver.quit(d)`
  ends the browser; the `chromedriver` process that `driver.ensure`
  spawned keeps running, and nothing else holds a handle to it. Left
  alone that leaks one driver per suite run — 31 had piled up on this
  box, none with a browser attached, before the symptom (a run that
  hung instead of starting Chrome) made it obvious. `harness_fixture`
  now keeps the handle in a module `var` and calls `driver.stop` after
  `webdriver.quit`, so a run leaves nothing behind. Worth checking with
  a process count either side of a run if you fork this fixture.
