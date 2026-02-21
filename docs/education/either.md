# either — Left/Right Sum Type

```zig
const either = @import("zfp").either;
```

## What is it?

`either` provides `Either(L, R)` — a tagged union that holds one of two alternatives:

- **`Left(L)`** — the "secondary" or "error" case
- **`Right(R)`** — the "primary" or "success" case

Inspired by Haskell's `Data.Either`, it models situations where a computation can produce one of two distinct outcomes with different types.

Unlike `result` (which works on `anyerror!T`), `Either(L, R)` lets you choose **any type** for both sides — including rich error types, alternative values, or domain-specific variants.

---

## The Problem

When a function can return two different types, Zig gives you a few options:

```zig
// Option 1 — tagged union (verbose to define every time)
const ParseResult = union(enum) {
    ok: i32,
    err: []const u8,
};

// Option 2 — anyerror!T (Left side restricted to error sets)
fn parse(s: []const u8) anyerror!i32 { ... }

// Both require manual switch every time you want to chain
const raw = parse(input) catch |e| return e;
const doubled = raw * 2;
```

With `either`, the intent is clear and composable:

```zig
const either = @import("zfp").either;
const E = either.Either([]const u8, i32);

const result = either.andThen(
    either.andThen(parse(input), validate),
    double,
);
```

---

## `Either(L, R)` — The type

Construct an `Either` type using `Either(L, R)`:

```zig
const either = @import("zfp").either;

const E = either.Either([]const u8, i32);

const ok  = E{ .right = 42 };
const err = E{ .left  = "something went wrong" };
```

---

## Functor — `map`

**Haskell**: `fmap :: (a -> b) -> Either l a -> Either l b`

Apply `f` to the `Right` value; leave `Left` unchanged.

```zig
const either = @import("zfp").either;

const E = either.Either([]const u8, i32);

either.map(E{ .right = 3 }, double)
// → Either([]const u8, i32){ .right = 6 }

either.map(E{ .left = "err" }, double)
// → Either([]const u8, i32){ .left = "err" }
```

The Right type can change:

```zig
either.map(E{ .right = 5 }, isPositive)
// → Either([]const u8, bool){ .right = true }
```

---

## Monad — `andThen`

**Haskell**: `(>>=) :: Either l a -> (a -> Either l b) -> Either l b`

Apply `f` to `Right`; short-circuit and propagate `Left` unchanged.
`f` itself must return an `Either`.

```zig
const either = @import("zfp").either;

const E = either.Either([]const u8, i32);

const validate = struct {
    fn call(x: i32) E {
        return if (x > 0) .{ .right = x } else .{ .left = "non-positive" };
    }
}.call;

either.andThen(E{ .right = 3 }, validate)   // → .{ .right = 3 }
either.andThen(E{ .right = -1 }, validate)  // → .{ .left = "non-positive" }
either.andThen(E{ .left = "failed" }, validate)  // → .{ .left = "failed" }
```

Chain multiple steps without nesting:

```zig
either.andThen(
    either.andThen(parse(input), validate),
    transform,
)
```

---

## `mapLeft` — Transform the Left value

Apply `f` to the `Left` value; leave `Right` unchanged.

```zig
const either = @import("zfp").either;

either.mapLeft(E{ .left = "hi" }, strLen)
// → Either(usize, i32){ .left = 2 }

either.mapLeft(E{ .right = 42 }, strLen)
// → Either(usize, i32){ .right = 42 }
```

---

## `bimap` — Transform both sides

Apply `lf` to `Left` or `rf` to `Right`, whichever is active.

**Haskell**: `bimap :: (a -> c) -> (b -> d) -> Either a b -> Either c d`

```zig
const either = @import("zfp").either;

either.bimap(E{ .left  = "hi" }, strLen, double)
// → Either(usize, i32){ .left = 2 }

either.bimap(E{ .right = 5 }, strLen, double)
// → Either(usize, i32){ .right = 10 }
```

`bimap` is the most general transformation: it normalises both sides in one step.

---

## `isLeft` / `isRight` — Predicates

```zig
const either = @import("zfp").either;

either.isLeft(E{ .left = "err" })   // → true
either.isRight(E{ .right = 42 })    // → true
```

---

## `unwrapOr` — Extract Right or use a default

```zig
const either = @import("zfp").either;

either.unwrapOr(E{ .right = 42 }, 0)        // → 42
either.unwrapOr(E{ .left = "err" }, 0)      // → 0
```

---

## `unwrapOrElse` — Extract Right or compute from Left

```zig
const either = @import("zfp").either;

either.unwrapOrElse(E{ .right = 42 }, strLen)        // → 42
either.unwrapOrElse(E{ .left = "hello" }, strLen)    // → 5
```

---

## `fromOption` — Convert `?T` to Either

```zig
const either = @import("zfp").either;

either.fromOption(@as(?i32, 42), "missing")    // → .{ .right = 42 }
either.fromOption(@as(?i32, null), "missing")  // → .{ .left = "missing" }
```

---

## `toOption` — Convert Either to `?R`

Discards the `Left` value.

```zig
const either = @import("zfp").either;

either.toOption(E{ .right = 42 })      // → @as(?i32, 42)
either.toOption(E{ .left = "err" })    // → null
```

---

## Why Zig's native tagged union is correct

`Either(L, R)` compiles to a tagged union — the same structure Zig uses for `?T` and `anyerror!T` internally. There is no heap allocation, no boxing, and no indirection.

```zig
// Either([]const u8, i32) compiles to exactly:
union(enum) {
    left: []const u8,
    right: i32,
}
```

The only overhead is the tag byte — the same cost you would pay writing the union by hand.

---

## Why `zfp/either` is zero-cost

All functions are `pub inline fn` with `anytype` parameters.
Return types are computed using `@TypeOf(f(@as(PayloadType, undefined)))` — a comptime expression that evaluates the type without executing.

Every call compiles to a plain `switch` statement with one branch taken:

```zig
// map(e, f) compiles to:
switch (e) {
    .left => |l| .{ .left = l },
    .right => |r| .{ .right = f(r) },
}
```

No virtual dispatch. No allocations. No intermediate structs.

---

## Composition example

Parse a string, validate the range, then format the result — or collect a descriptive error at each stage:

```zig
const either = @import("zfp").either;

const E = either.Either([]const u8, i32);

const parse = struct {
    fn call(s: []const u8) E {
        const n = std.fmt.parseInt(i32, s, 10) catch return .{ .left = "not a number" };
        return .{ .right = n };
    }
}.call;

const validate = struct {
    fn call(n: i32) E {
        return if (n >= 0 and n <= 100)
            .{ .right = n }
        else
            .{ .left = "out of range [0, 100]" };
    }
}.call;

const result = either.andThen(parse("42"), validate);
// → .{ .right = 42 }

const bad = either.andThen(parse("999"), validate);
// → .{ .left = "out of range [0, 100]" }
```

Combined with `pipe`:

```zig
const pipe  = @import("zfp").pipe;
const arrow = @import("zfp").arrow;

// Compute both the raw and validated form of an input
const stats = arrow.fanout(
    parse,
    struct {
        fn call(s: []const u8) E { return either.andThen(parse(s), validate); }
    }.call,
    "42",
);
// stats[0] = parse("42")              → .{ .right = 42 }
// stats[1] = validate(parse("42"))    → .{ .right = 42 }
```

---

## Relationship table

| Haskell | zfp | What it does |
|---------|-----|--------------|
| `Left l` | `E{ .left = l }` | Wrap a value as Left |
| `Right r` | `E{ .right = r }` | Wrap a value as Right |
| `fmap f (Right r)` | `either.map(e, f)` | `.{ .right = f(r) }` |
| `fmap f (Left l)` | `either.map(e, f)` | `.{ .left = l }` |
| `first f` | `either.mapLeft(e, f)` | Apply f to Left |
| `bimap lf rf` | `either.bimap(e, lf, rf)` | Apply to whichever side is active |
| `e >>= f` | `either.andThen(e, f)` | flatMap on Right |
| `fromMaybe` | `either.fromOption(opt, l)` | `?T → Either(L, R)` |
| `toMaybe` | `either.toOption(e)` | `Either(L, R) → ?R` |
| `either l r` | `switch` expression | Pattern match on Left/Right |

---

## Further reading

- [Haskell Data.Either](https://hackage.haskell.org/package/base/docs/Data-Either.html)
- [Rust Result](https://doc.rust-lang.org/std/result/enum.Result.html) — same concept, restricted error side
- [Zig tagged unions](https://ziglang.org/documentation/master/#Tagged-union)
