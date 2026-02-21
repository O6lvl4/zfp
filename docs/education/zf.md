# zf — Function Combinators

```zig
const zf = @import("zfp").zf;
```

## What is it?

`zf` provides primitive building blocks for working with functions as values.
These are the Zig equivalents of Haskell's Prelude combinators: `id`, `flip`, `const`, and `on`.

They are the glue that makes `pipe.run` and `compose.from` chains flow naturally
without having to define a named helper function for every small transformation.

---

## `id` — Identity

**Haskell**: `id :: a -> a`

Returns its argument unchanged. Sounds useless, but is essential as a no-op slot
in pipelines or as a default transformation.

```zig
const zf = @import("zfp").zf;

zf.id(42)      // → 42
zf.id("hello") // → "hello"
zf.id(true)    // → true
```

**In a pipeline:**

```zig
const zf   = @import("zfp").zf;
const pipe = @import("zfp").pipe;

// Conditionally apply a transformation, or pass through unchanged
const transform = if (should_double) double else zf.id;
const result = pipe.run(value, .{transform});
```

---

## `flip` — Argument swap

**Haskell**: `flip :: (a -> b -> c) -> b -> a -> c`

Calls a binary function with its first two arguments swapped.

```zig
const zf = @import("zfp").zf;

const sub = struct {
    fn call(a: i32, b: i32) i32 { return a - b; }
}.call;

sub(10, 3)             // → 7   (10 - 3)
zf.flip(sub, 10, 3)    // → -7  (3 - 10)
```

**Why it matters:**

When composing functions, argument order often doesn't match what a pipeline needs.
`flip` lets you adapt any binary function without wrapping it.

```zig
const zf  = @import("zfp").zf;
const std = @import("std");

// std.mem.startsWith(haystack, prefix)
// but you have (prefix, haystack) — flip fixes the order
zf.flip(std.mem.startsWith, prefix, haystack)
```

---

## `const_` — Constant function

**Haskell**: `const :: a -> b -> a`

Returns the first argument, ignoring the second.
Named `const_` because `const` is a reserved keyword in Zig.

```zig
const zf = @import("zfp").zf;

zf.const_(42, "ignored") // → 42
zf.const_(true, 9999)    // → true
```

**In a pipeline:**

```zig
const zf   = @import("zfp").zf;
const pipe = @import("zfp").pipe;

// Replace any value with a fixed sentinel
const alwaysZero = struct {
    fn call(x: i32) i32 { return zf.const_(@as(i32, 0), x); }
}.call;

pipe.run(value, .{ parse, validate, alwaysZero }); // always ends in 0
```

---

## `on` — Apply binary function via a shared mapping

**Haskell**: `on :: (b -> b -> c) -> (a -> b) -> a -> a -> c`

Applies a unary function `g` to both arguments, then passes the results to a binary function `f`.

```
on(f, g, a, b)  ≡  f(g(a), g(b))
```

```zig
const zf  = @import("zfp").zf;
const std = @import("std");

const strLen = struct {
    fn call(s: []const u8) usize { return s.len; }
}.call;

zf.on(std.math.order, strLen, "foo", "hello") // → .lt  (3 < 5)
zf.on(std.math.order, strLen, "hi",  "ok")    // → .eq  (2 == 2)
```

**Why it matters:**

`on` lets you lift a comparison or combinator to work on a *derived property*
without writing a custom wrapper each time.

```zig
const zf  = @import("zfp").zf;
const std = @import("std");

// Sort strings by length
std.sort.block([]const u8, items, {}, struct {
    fn lessThan(_: void, a: []const u8, b: []const u8) bool {
        return zf.on(std.math.order, strLen, a, b) == .lt;
    }
}.lessThan);
```

---

## Why `zf` and not `fn`?

`fn` is a reserved keyword in Zig. Using it as a module name would force every
caller to write `@"fn"`, which is ugly:

```zig
// With fn — ugly
const zf = @import("zfp").@"fn";

// With zf — clean
const zf = @import("zfp").zf;
```

---

## Why is it zero-cost?

All four functions are `pub inline fn` with `anytype` parameters.
The compiler sees through every call at comptime:

- `id(x)` compiles to: the value `x` directly
- `flip(f, a, b)` compiles to: `f(b, a)` — a single call
- `const_(x, _)` compiles to: the value `x` directly
- `on(f, g, a, b)` compiles to: `f(g(a), g(b))` — two calls

No virtual dispatch, no boxing, no wrapper overhead.

---

## Composition example

```zig
const zf      = @import("zfp").zf;
const pipe    = @import("zfp").pipe;
const compose = @import("zfp").compose;
const std     = @import("std");

// Compare two records by their score field, descending
const byScoreDesc = struct {
    fn call(a: Record, b: Record) bool {
        return zf.on(std.math.order, getScore, a, b) == .gt;
    }
}.call;

// In a pipeline: normalise, then check if a > b by score
const checkOrder = compose.from(.{ normalise, byScoreDesc });
```

---

## Relationship table

| Haskell | zfp | What it does |
|---------|-----|--------------|
| `id x` | `zf.id(x)` | Pass through unchanged |
| `flip f a b` | `zf.flip(f, a, b)` | Call `f(b, a)` |
| `const x _` | `zf.const_(x, _)` | Always return `x` |
| `f \`on\` g` | `zf.on(f, g, a, b)` | `f(g(a), g(b))` |

---

## Further reading

- [Haskell Prelude — id, const, flip](https://hackage.haskell.org/package/base/docs/Prelude.html)
- [Data.Function — on](https://hackage.haskell.org/package/base/docs/Data-Function.html)
- [Zig comptime and anytype](https://ziglang.org/documentation/master/#comptime)
