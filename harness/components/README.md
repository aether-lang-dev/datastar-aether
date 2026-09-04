# Components

One HTML fragment per component, plus the endpoints that drive it.

A component here is what the [UI Component Testing][post] post calls a
*rectangle*: the smallest piece of UI worth testing on its own. It has
no knowledge of the harness, and the harness has no knowledge of the
production app — which is the whole point. The same fragment is mounted
by the real app and by the test harness, and only the harness stubs the
slow parts.

[post]: https://paulhammant.com/2017/02/01/ui-component-testing
