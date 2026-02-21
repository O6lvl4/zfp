# Result — Educational Guide

> Also available in: [日本語](./result.ja.md)

---

## What is a Result?

A **Result** (also called **Either** in Haskell, `Result<T, E>` in Rust) represents a computation that can either succeed with a value or fail with an error.

Instead of using exceptions (which escape the type system) or magic return codes (which are easy to ignore), Result makes failure **explicit in the type**.

```
Ok(42)        — success with a value
Err(NotFound) — failure with an error
```

In Zig, this is already a first-class language feature: `E!T` (error union).

```zig
const x: anyerror!i32 = 42;           // Ok(42)
const y: anyerror!i32 = error.NotFound; // Err(NotFound)
```

Zig's `E!T` *is* the Result type. `zfp/result` adds functional combinators on top of it — with zero runtime cost.

---

## The Problem: Scattered Error Handling

When multiple operations can fail, the naive approach scatters error handling throughout the logic:

```zig
fn process(raw: anyerror![]const u8) anyerror!i32 {
    const s = try raw;
    const n = std.fmt.parseInt(i32, s, 10) catch |err| return err;
    if (n <= 0) return error.OutOfRange;
    const looked_up = lookup(n) catch |err| return err;
    return looked_up * 2;
}
```

Every step requires explicit error handling. The happy path is buried in noise.

The same logic expressed as a pipeline:

```zig
const result = @import("zfp").result;

fn process(raw: anyerror![]const u8) anyerror!i32 {
    return result.andThen(
        result.andThen(
            result.andThen(raw, parsePositiveInt),
            lookup,
        ),
        double,
    );
}
```

Flat, readable, and generates **identical machine code** to the manual version.

---

## Functional Programming Concepts

### Functor — `map`

A **functor** is a container you can apply a function to without unwrapping it.

```
map : F(A) → (A → B) → F(B)
```

For Result:

```
map(Ok(a),  f)  = Ok(f(a))
map(Err(e), f)  = Err(e)
```

`map` lifts a pure (infallible) function into the world of fallible values. The error propagation is handled by the container — you never write `catch` yourself.

```zig
const result = @import("zfp").result;

fn double(x: i32) i32 { return x * 2; }

const ok  = result.map(@as(anyerror!i32, 21), double); // Ok(42)
const err = result.map(@as(anyerror!i32, error.Bad), double); // Err(Bad)
```

**Key idea**: `map` never changes whether a computation succeeded. It only transforms the value inside a success.

---

### Monad — `andThen`

A **monad** extends the functor idea to functions that themselves produce results.

```
andThen : F(A) → (A → F(B)) → F(B)
```

Also known as `flatMap`, `bind`, or `>>=` in Haskell.

The difference from `map`:

| operation | `f` returns | result |
|-----------|-------------|--------|
| `map`     | `B`         | `E!B`  |
| `andThen` | `E!B`       | `E!B`  |

Without `andThen`, applying a fallible function via `map` would give `E!(E!B)` — a doubly-wrapped error union. `andThen` flattens it automatically.

```zig
const result = @import("zfp").result;

const safeDiv = struct {
    fn call(x: i32) anyerror!i32 {
        if (x == 0) return error.DivisionByZero;
        return @divTrunc(100, x);
    }
}.call;

// chain two fallible operations
const r = result.andThen(result.andThen(@as(anyerror!i32, 5), safeDiv), safeDiv);
// 5 → 100/5=20 → 100/20=5
```

**Key idea**: `andThen` is how you sequence fallible operations without nesting. Each step can independently fail, and the chain short-circuits at the first error.

---

### Default Value — `unwrapOr`

Sometimes you want to escape the result world and get a concrete value, substituting a default for any error:

```
unwrapOr : F(A) → A → A
```

```zig
const result = @import("zfp").result;

const port = result.unwrapOr(config.readPort(), 8080);
```

In Zig this is literally `config.readPort() catch 8080`. `unwrapOr` is provided for API consistency in pipelines.

---

### Recovery — `unwrapOrElse`

When you need the error value itself to determine the fallback:

```
unwrapOrElse : F(A) → (E → A) → A
```

```zig
const result = @import("zfp").result;

const value = result.unwrapOrElse(readConfig(), struct {
    fn call(err: anyerror) Config {
        std.log.warn("config error: {s}, using defaults", .{@errorName(err)});
        return Config.default();
    }
}.call);
```

This is the key difference from `option`: because errors carry information, recovery often needs to inspect the error value. `unwrapOrElse` makes this explicit.

---

### Bridging to Option — `toOption`

When you need to interface result-based and option-based code:

```
toOption : F(A) → ?A
```

```zig
const result = @import("zfp").result;

// Drop the error, keep only the "did it succeed?" information
const maybe_value: ?i32 = result.toOption(riskyOperation());
```

Useful at system boundaries where callers care about presence/absence but not the specific error.

---

## Result vs Option

| Concept | `option` | `result` |
|---------|----------|---------|
| Represents | presence / absence | success / failure |
| Native Zig type | `?T` | `E!T` |
| Carries information on absence | no | yes — the error value |
| Recovery | `unwrapOr` | `unwrapOr`, `unwrapOrElse` |
| Bridge | — | `toOption(?T → E!T direction)` |

**Choose `option`** when absence has no cause worth reporting.
**Choose `result`** when failure has a reason the caller might act on.

---

## Why Zig's `E!T` is Already Correct

Many languages implement Result as a generic enum (e.g., `enum Result<T, E> { Ok(T), Err(E) }`). This typically involves:

- A tag byte for the discriminant
- Possible heap allocation for boxing large error types
- Overhead for matching on the variant

**Zig's `E!T` has none of these costs.** The compiler represents `E!T` as:

- A small integer tag for the error (error values are compile-time integers in Zig)
- The payload T stored alongside it
- The tag is optimized away when the result is provably success

The result: `E!T` in Zig is as efficient as a hand-written discriminated union — or better, because the compiler understands its semantics and can eliminate branches at compile time.

---

## Why `zfp/result` is Zero-Cost

Every function in `zfp/result` is marked `inline` and takes `anytype` parameters.

This means:

1. **No function call overhead.** The compiler inlines the body at every call site.
2. **No type erasure.** `anytype` is resolved at compile time. The generated code is specialized for the exact error set you use.
3. **No indirection.** No function pointers, no vtables, no heap closures.

The compiler sees:

```zig
const result = @import("zfp").result;

result.map(@as(anyerror!i32, x), double)
```

and generates exactly the same code as:

```zig
if (x) |v| double(v) else |err| err
```

---

## Composition

The real power comes from combining operations:

```zig
const result = @import("zfp").result;

// Parse and validate a raw configuration value
// Each step independently propagates its own error type
fn parseConfig(raw: anyerror![]const u8) anyerror!Config {
    return result.map(
        result.andThen(
            result.andThen(
                result.andThen(raw, trimWhitespace),
                parseJson,
            ),
            validateSchema,
        ),
        buildConfig,
    );
}
```

Reading from the inside out:
1. `andThen(trimWhitespace)` — clean up input, fail on empty
2. `andThen(parseJson)` — parse to a JSON value, fail on syntax error
3. `andThen(validateSchema)` — validate structure, fail on missing fields
4. `map(buildConfig)` — construct the final config (infallible once validated)

Each step is independently testable and named. Every error path is explicit in the types.

---

## Relationship to Other Concepts

| Concept | Zig equivalent | zfp function |
|---------|---------------|-------------|
| Functor | `if (x) \|v\| f(v) else \|e\| e` | `map` |
| Monad / flatMap | `f(x catch \|e\| return e)` | `andThen` |
| Default / getOrElse | `x catch default` | `unwrapOr` |
| Recovery | `x catch \|e\| f(e)` | `unwrapOrElse` |
| Bridge to optional | `x catch null` | `toOption` |
| Success check | `if (x) \|_\| true else \|_\| false` | `isOk` |
| Error check | `if (x) \|_\| false else \|_\| true` | `isErr` |

---

## Further Reading

- [Zig language reference: Error Unions](https://ziglang.org/documentation/master/#Error-Union-Type)
- [Haskell `Either` monad](https://hackage.haskell.org/package/base/docs/Data-Either.html) — the original
- [Rust `Result<T, E>`](https://doc.rust-lang.org/std/result/) — a well-documented modern take
