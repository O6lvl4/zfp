# Option — Educational Guide

> Also available in: [日本語](./option.ja.md)

---

## What is an Option?

An **Option** (also called **Maybe** in Haskell, **Optional** in Java/Swift) represents a value that may or may not exist.

Instead of using `null` as a magic value that silently propagates through your code, Option makes the possibility of absence **explicit in the type system**.

```
Some(42)   — a value exists
None       — no value
```

In Zig, this is already a first-class language feature: `?T`.

```zig
const x: ?i32 = 42;    // Some(42)
const y: ?i32 = null;  // None
```

Zig's `?T` *is* the Option type. `zfp/option` adds functional combinators on top of it — with zero runtime cost.

---

## The Problem: Nested Null Checks

When multiple operations can fail, the naive approach creates deeply nested code:

```zig
fn process(raw: ?[]const u8) ?i32 {
    if (raw) |s| {
        const parsed = std.fmt.parseInt(i32, s, 10) catch return null;
        if (parsed > 0) {
            const result = lookup(parsed);
            if (result) |r| {
                return r * 2;
            }
        }
    }
    return null;
}
```

Each step adds a level of indentation. The actual logic gets buried. This is sometimes called the **"pyramid of doom"**.

The same logic expressed as a pipeline:

```zig
const option = @import("zfp").option;

fn process(raw: ?[]const u8) ?i32 {
    return option.map(
        option.andThen(
            option.andThen(raw, parsePositiveInt),
            lookup,
        ),
        double,
    );
}
```

Flat, readable, and generates **identical machine code** to the nested version.

---

## Functional Programming Concepts

### Functor — `map`

A **functor** is a container you can apply a function to without unwrapping it.

```
map : F(A) → (A → B) → F(B)
```

For Option:

```
map(Some(a), f)  = Some(f(a))
map(None,    f)  = None
```

`map` lifts a function `A → B` into the world of optional values. The "null propagation" is handled by the container — you never write `if` yourself.

```zig
const option = @import("zfp").option;

fn double(x: i32) i32 { return x * 2; }

// double every non-null integer, propagate null unchanged
const result = option.map(@as(?i32, 21), double); // ?i32(42)
const empty  = option.map(@as(?i32, null), double); // null
```

**Key idea**: `map` never changes whether a value is present. It only transforms the value inside.

---

### Monad — `andThen`

A **monad** extends the functor idea to functions that themselves produce optional values.

```
andThen : F(A) → (A → F(B)) → F(B)
```

Also known as `flatMap`, `bind`, or `>>=` in Haskell.

The difference from `map`:

| operation | `f` returns | result |
|-----------|-------------|--------|
| `map`     | `B`         | `?B`   |
| `andThen` | `?B`        | `?B`   |

Without `andThen`, applying a fallible function via `map` would give `??B` — a doubly-wrapped optional. `andThen` flattens it automatically.

```zig
const std = @import("std");
const option = @import("zfp").option;

const safeSqrt = struct {
    fn call(x: f64) ?f64 {
        if (x < 0) return null;
        return std.math.sqrt(x);
    }
}.call;

// chain two fallible operations
const r = option.andThen(option.andThen(@as(?f64, 16.0), safeSqrt), safeSqrt);
// 16.0 → sqrt → 4.0 → sqrt → 2.0
```

**Key idea**: `andThen` is how you sequence fallible operations without nesting. Each step can independently "fail" (return null), and the chain short-circuits at the first failure.

---

### Default Value — `unwrapOr`

Sometimes you want to escape the optional world and get a concrete value:

```
unwrapOr : F(A) → A → A
```

```zig
const option = @import("zfp").option;

const port = option.unwrapOr(config.port, 8080);
```

In Zig this is literally `config.port orelse 8080`. `unwrapOr` is provided for API consistency in pipelines.

---

### Filtering — `filter`

Keep a value only when it satisfies a predicate:

```
filter : F(A) → (A → Bool) → F(A)
```

```zig
const option = @import("zfp").option;

fn isPositive(x: i32) bool { return x > 0; }

const positive = option.filter(@as(?i32, -5), isPositive); // null
const kept     = option.filter(@as(?i32,  3), isPositive); // ?i32(3)
```

`filter` is useful when a value is present but does not meet a condition — it converts presence to absence without changing the value itself.

---

## Why Zig's `?T` is Already Correct

Many languages implement Option as a generic enum or struct (e.g., `enum Option<T> { Some(T), None }`). This typically involves:

- A tag byte (or more) for the discriminant
- Possible heap allocation for boxing
- Virtual dispatch or branch prediction costs

**Zig's `?T` has none of these costs.** The compiler represents `?T` as:

- For pointer types: `null` is a distinguished bit pattern (zero). No overhead.
- For value types: a small discriminant packed alongside the value, with the compiler free to optimize it away entirely when the value is provably non-null.

The result: `?T` in Zig is as efficient as a hand-written struct with a boolean flag — or better, because the compiler understands its semantics.

---

## Why `zfp/option` is Zero-Cost

Every function in `zfp/option` is marked `inline` and takes `anytype` parameters.

This means:

1. **No function call overhead.** The compiler inlines the body at every call site.
2. **No type erasure.** `anytype` is resolved at compile time. The generated code is specialized for the exact types you use.
3. **No indirection.** No function pointers, no vtables, no closures on the heap.

The compiler sees:

```zig
const option = @import("zfp").option;

option.map(@as(?i32, x), double)
```

and generates exactly the same code as:

```zig
if (x) |v| v * 2 else null
```

You can verify this with `zig build -Doptimize=ReleaseFast` and inspect the output — the calls disappear entirely.

---

## Composition

The real power comes from combining these operations:

```zig
const option = @import("zfp").option;

// Parse a raw string into a validated, transformed value
// Each step can independently return null on failure
fn processInput(raw: ?[]const u8) ?f64 {
    return option.map(
        option.andThen(
            option.andThen(
                option.filter(raw, isNonEmpty),
                parseFloat,
            ),
            validateRange,
        ),
        normalize,
    );
}
```

Reading from the inside out:
1. `filter` — skip empty strings
2. `andThen(parseFloat)` — parse to f64, fail on bad input
3. `andThen(validateRange)` — reject out-of-range values
4. `map(normalize)` — transform the valid value

Each step is independently testable and named. The pipeline makes the data flow explicit.

---

## Relationship to Other Concepts

| Concept | Zig equivalent | zfp function |
|---------|---------------|-------------|
| Functor | `if (x) \|v\| f(v) else null` | `map` |
| Monad / flatMap | `if (x) \|v\| f(v) else null` where `f` returns `?U` | `andThen` |
| Default / getOrElse | `x orelse default` | `unwrapOr` |
| Guard / filter | `if (x) \|v\| if (p(v)) v else null` | `filter` |
| isPresent | `x != null` | `isSome` |
| isEmpty | `x == null` | `isNone` |

All of these operations exist in Zig already as syntax. `zfp/option` names them, making intent explicit and enabling composition without noise.

---

## Further Reading

- [Zig language reference: Optionals](https://ziglang.org/documentation/master/#Optionals)
- [Haskell `Maybe` monad](https://wiki.haskell.org/Maybe_monad) — the original
- [Rust `Option<T>`](https://doc.rust-lang.org/std/option/) — a well-documented modern take
