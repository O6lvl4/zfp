# tap — Side-effect Injection

```zig
const tap = @import("zfp").tap;
```

## What is it?

`tap` lets you inject a side-effecting function (logging, tracing, assertions) into a
pipeline without breaking the flow of the value.

The value goes in, the side effect happens, and the same value comes out unchanged.

```
tap.run(x, f)  ≡  f(x); x
```

---

## The Problem

Debugging a pipeline currently forces you to break it apart:

```zig
// Before — pipeline broken for logging
const parsed = parse(raw);
std.debug.print("parsed: {}\n", .{parsed});
const validated = validate(parsed);
std.debug.print("validated: {}\n", .{validated});
const result = transform(validated);
```

With `tap`, the pipeline stays intact:

```zig
const tap  = @import("zfp").tap;
const pipe = @import("zfp").pipe;

const result = pipe.run(raw, .{
    parse,
    tap.typed(ParsedData, logParsed),
    validate,
    tap.typed(ValidData, logValidated),
    transform,
});
```

---

## `tap.run` — Direct use

Apply `f` for its side effect, return `value` unchanged.

```zig
const tap = @import("zfp").tap;

const value: i32 = 42;
const same  = tap.run(value, logFn); // logFn(42) is called
// same == 42
```

`f`'s return value is discarded — only the side effect matters.
This works for any `f`, whether it returns `void` or not.

```zig
// All of these work:
tap.run(value, logFn)       // f returns void
tap.run(value, inspectFn)   // f returns something — return value discarded
```

---

## `tap.typed` — Pipeline step

Return a concrete `fn(T) T` that can be placed inside a `pipe.run` tuple.

```zig
const tap  = @import("zfp").tap;
const pipe = @import("zfp").pipe;

const logParsed = struct {
    fn call(x: ParsedData) void {
        std.debug.print("after parse: {}\n", .{x});
    }
}.call;

const result = pipe.run(raw, .{
    parse,
    tap.typed(ParsedData, logParsed),  // ← injected here
    validate,
    transform,
});
```

**Why the explicit type?**

`pipe.run` resolves all return types at comptime before calling anything.
For that to work, each pipeline step must have a concrete, knowable signature.
`tap.typed(T, f)` provides exactly that: `fn(T) T`.

---

## Why is it zero-cost?

`tap.run` is `pub inline fn` — the compiler folds it into the call site.
`tap.typed` returns a function whose body is also inlined.

The generated code is identical to writing:

```zig
logFn(value);
// continue with value
```

No wrapper structs, no indirection, no allocation.

---

## Composition example

```zig
const tap  = @import("zfp").tap;
const pipe = @import("zfp").pipe;
const std  = @import("std");

const logRaw = struct {
    fn call(s: []const u8) void {
        std.debug.print("[raw]    {s}\n", .{s});
    }
}.call;

const logParsed = struct {
    fn call(n: i32) void {
        std.debug.print("[parsed] {d}\n", .{n});
    }
}.call;

const result = pipe.run(input, .{
    tap.typed([]const u8, logRaw),
    parseInt,
    tap.typed(i32, logParsed),
    double,
});
```

Output:

```
[raw]    "21"
[parsed] 21
```

Result: `42`

---

## Relationship table

| Concept | zfp | What it does |
|---------|-----|--------------|
| Observe a value in-place | `tap.run(value, f)` | Calls `f(value)`, returns `value` |
| Observe inside `pipe.run` | `tap.typed(T, f)` | Returns `fn(T) T` step |

---

## Further reading

- [Haskell Data.Function — (&)](https://hackage.haskell.org/package/base/docs/Data-Function.html)
- [Rust tap crate](https://docs.rs/tap/latest/tap/)
- [Zig inline functions](https://ziglang.org/documentation/master/#inline-functions)
