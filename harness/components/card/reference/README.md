# Reference material (not shipped, not compiled)

The card component's *structure and intentions* are adapted from two
MIT-licensed projects. Nothing here is imported or built — these are the
sources we read to port faithfully into idiomatic Aether + Datastar.

- **vue-paycard** (MIT, © 2020 Igor Guastalla) — the animated card
  *preview*: the card face, brand logo, flip-to-back for CVV, and the
  18-brand PAN-prefix detection ruleset. `vue-paycard-style.css` is its
  stylesheet, kept verbatim as the source for our ported CSS. License in
  `vue-paycard-LICENSE`.
- **CardJs** (MIT) — the *behaviour*: per-brand number masks (Amex
  `#### ###### #####` vs the default 4×4), format-as-you-type, the
  `MM / YY` expiry mask, CVC length by brand (3 vs 4), and Luhn. We took
  the behaviour model, not the source. License in `CardJs-LICENSE`.

The card brand detection in `../brand/module.ae` is a direct port of
vue-paycard's `cardType` computed property. The masks in
`../mask/module.ae` follow CardJs's mask constants.
