# datastar-aether — TODO

Ideas and deferred work with a hint of design but no committed scope.
Short-lived tasks live in PRs and commit messages; this is for the
longer-lived "do it when…" items.

## Move StoraeBook to `aether/contrib/` and snip the Datastar dependency

Datastar StoraeBook (`harness/storaebook/`) is a small Storybook-alike: a
tinyweb app that browses UI components as named stories — a story tree, a
live canvas, a Canvas/Docs tab pair, a background/fullscreen toolbar, and
live Controls. It is genuinely useful and mostly generic tinyweb + HTML,
so it is worth lifting out of this app repo into `aether/contrib/` (e.g.
`contrib/storaebook/`) as an ecosystem tool any tinyweb app could use —
but that means snipping its Datastar coupling first.

**What's already generic (the bulk):** routing (one exact route per
story, generated from the story list), the story-tree sidebar, the framed
vs raw views, the docs panel, the shell CSS. All plain tinyweb + string
HTML.

**What's Datastar-tied (the part to snip):**

- The StoraeBook's *own chrome* interactivity — the Canvas/Docs tabs, the
  bg toggle, fullscreen — is written as Datastar `data-*` attributes
  (`data-signals`, `data-on:click`, `data-show`). Note it imports
  `contrib.tinyweb`, NOT the datastar SDK, so this is only a lean on the
  Datastar *client runtime*, not a code dependency. Swap for native
  `<details>`/CSS or a few lines of vanilla JS.
- The story-application seam: "applying a story POSTs its setup to the
  same `/_harness/*` stub endpoint a test uses, then serves the component
  fragment" (`apply_setup` + `component_fragment` in the module). That
  assumes the Datastar component-testing model — a stateless fragment plus
  an injectable signal store plus patch-to-re-render. A non-Datastar
  tinyweb app has a different isolation seam.

**The shape that generalizes** (mirrors real Storybook's manager +
per-framework renderers): a generic StoraeBook *core* (tree, canvas, docs,
routing, shell) plus a small *renderer* interface — "given a story id +
setup, apply the setup and return the component's HTML." datastar-aether
would supply a Datastar renderer (stub POST + fragment); a plain
server-rendered tinyweb app supplies its own (render the page in its
state). The story catalogue (`harness/stories/`) becomes the public
input format.

**Why parked:** it works where it is, and the extraction is a real
factoring job — pull the renderer interface out of `apply_setup` /
`component_fragment`, replace the chrome's `data-*` with framework-free
toggles, and settle the story-catalogue format as a public API. Do it
when a second, non-Datastar tinyweb app wants component stories: that's
the pull that proves the renderer boundary sits in the right place.

Source to lift from: `harness/storaebook/` and `harness/stories/`.
