# REPLY: `defer f(_builder)` in a builder emits C that does not compile

Fixed in aether PR #2965: https://github.com/aether-lang-dev/aether/pull/2965

A builder's hidden `_builder` parameter is now declared to the codegen
like a named one, so #2923's panic thunk captures it. A `defer` reading it
runs on a return and on a caught panic. Once that is in a release, the
three builders can go back to `defer ..._free(_builder)`.
