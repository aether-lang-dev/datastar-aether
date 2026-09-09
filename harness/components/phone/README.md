# phone — a libphonenumber port, in progress

A pure-Aether phone-number library plus a Datastar component that uses
it. The library is derived from Google's **libphonenumber** (Apache-2.0)
by **code generation**: `gen/generate.ae` compiles the vendored metadata
XML into a pure-Aether table at build time — no XML, no `std.xml`, at
runtime, which is how every serious libphonenumber port works.

## Layout

```
phone/
  gen/
    PhoneNumberMetadata.xml            vendored verbatim from libphonenumber
    PhoneNumberMetadata.xml.PROVENANCE where it came from + attribution
    generate.ae                        XML -> metadata.ae (run offline)
  metadata.ae                          GENERATED — the compiled table
  validate/module.ae                   validation over the table (pure)
  reference/libphonenumber-LICENSE     Apache-2.0
  module.ae                            the Datastar component (uses validate/)
```

## Roadmap

This is deliberately an early cut, kept honest about scope:

1. **Now** — `isPossibleNumber`-for-fixedLine: length by country, for a
   curated ~10 countries. Enough for a real "is this a plausible number"
   check and a formatting hint.
2. **Next** — widen the curated set; add the display formatter (group
   digits per the country's format template); the Datastar component.
3. **Later** — `isValidNumber`: consume the per-type national-number
   patterns the XML already carries (we vendor the WHOLE file precisely
   so the generator can grow into it without re-fetching). This is the
   large part of the port.
4. **Eventually** — tease the *library* (`gen/`, `metadata.ae`,
   `validate/`, `reference/`) out into its own repo, e.g.
   `github.com/aether-lang-dev/aephonenumber`, consumed here via
   `ae add` exactly like selaenium. The Datastar **component**
   (`module.ae`) stays in datastar-aether as a consumer.

Because the whole metadata XML is vendored, steps 3 and 4 need no new
fetch and the extraction is a clean split of this directory.

## Scope, stated plainly

`validate` answers `isPossibleNumber` (right length for the country), not
`isValidNumber` (which also matches the per-type national regex). The
distinction is real and documented in the module and the generator
header. The curated countries are in `gen/generate.ae`'s `wanted()`.
