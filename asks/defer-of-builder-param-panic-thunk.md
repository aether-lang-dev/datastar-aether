# `defer f(_builder)` in a builder emits C that does not compile (Aether 0.818.0 to 0.823.0)

Found bringing datastar-aether to 0.823.0. `patch_elements_with`,
`patch_signals_with` and `execute_script_with` each free their options bag
with `defer element_options_free(_builder)`, and none of them compiles any
more:

```
datastar/module.ae:960:31: error: use of undeclared identifier '_builder'
```

## Minimal repro

```aether
struct Opts {
    n: int
}
opts_new() -> ptr { return heap.new(Opts) as ptr }
opts_free(p: ptr) { println("freed"); heap.free(p as *Opts) }
with_n(_ctx: ptr, v: int) { o = _ctx as *Opts; o.n = v }
use(o: ptr) -> string { x = o as *Opts; return "n=${x.n}" }

builder send_with(label: string): string with opts_new {
    defer opts_free(_builder)
    return use(_builder)
}

main() {
    r = send_with("x") { with_n(7) }
    println(r)
}
```

0.817.0 prints `freed` and then `n=7`. 0.823.0 fails at the C compile, on
`m.ae:26:11: error: use of undeclared identifier '_builder'`.

## Why

#2923 ("a panic releases what each place holds") gives each `defer` a panic
thunk, `static void _ae_defer_N(const void* _p)`, that copies the deferred
call's locals and parameters out of a cell. A named parameter is captured:

```c
void* p; memcpy(&p, _c[0], sizeof(p));
done_with(p);
```

A builder's implicit `_builder` parameter is not, so the thunk names a
variable it does not have:

```c
static void _ae_defer_0(const void* _p) {
    void* const* _c = (void* const*)_p; (void)_c;
opts_free(_builder);
}
```

The cell is `void* _ae_dfc0[1] = { 0 }`, with nothing stored in it.

## What datastar-aether does meanwhile

Each of the three builders binds the bag to a local first
(`bag = _builder`, then `defer ..._free(bag)`), and the local is captured
correctly. There is a comment at each one pointing here. Once this is fixed,
they can go back to `defer ..._free(_builder)`.
