# zfp — Zero-cost Functional Programming for Zig

A minimal, zero-cost functional programming toolkit built on top of Zig's native types.

No wrappers. No allocations. No runtime overhead.
Pure comptime generics that compile away completely.

---

## Philosophy

- **Do not wrap native types.** `option` works directly on `?T`; `result` works directly on `E!T`.
- **Zero cost.** Every function is `inline`. The generated code is identical to hand-written `if`/`catch` blocks.
- **Minimal API.** One function per concept. Composable by design.
- **Idiomatic Zig.** No macros, no hidden allocations, no magic.

---

## Modules

| Module | Status | Description |
|--------|--------|-------------|
| `option` | ✅ | Utilities for Zig's native `?T` optional type — includes `ap`, `orElse` |
| `result` | ✅ | Utilities for Zig's native `anyerror!T` error union type — includes `ap`, `orElse` |
| `pipe` | ✅ | Left-to-right function pipeline with full type inference |
| `compose` | ✅ | Compose functions into a reusable callable |
| `zf` | ✅ | Function combinators: `id`, `flip`, `const_`, `on` |
| `tap` | ✅ | Side-effect injection in pipelines: `run`, `typed` |
| `arrow` | ✅ | Arrow combinators for pairs: `first`, `second`, `split`, `fanout` |
| `either` | ✅ | Left/Right sum type: `map`, `mapLeft`, `bimap`, `andThen`, and more |
| `slice` | ✅ | Foldable over slices: `fold`, `all`, `any`, `find`, `count`, and more |
| `monoid` | ✅ | Semigroup / Monoid combinators: `Sum`, `Product`, `Any`, `All`, `First`, `Last` |

---

## option

Eliminate deeply nested `if (value) |v|` chains without any runtime cost.

### API

```zig
const option = @import("zfp").option;

// Apply a function to the contained value
option.map(value: ?T, f: fn(T) U) ?U

// Flatmap — f itself returns an optional
option.andThen(value: ?T, f: fn(T) ?U) ?U

// Return the value or a default
option.unwrapOr(value: ?T, default: T) T

// Keep the value only if the predicate holds
option.filter(value: ?T, predicate: fn(T) bool) ?T

// Keep the value only if the predicate holds
option.filter(value: ?T, predicate: fn(T) bool) ?T

// Apply a wrapped function to a wrapped value (Applicative)
option.ap(f: ?fn(T)U, value: ?T) ?U

// First non-null wins (Alternative)
option.orElse(value: ?T, fallback: ?T) ?T

// Null checks
option.isSome(value: ?T) bool
option.isNone(value: ?T) bool
```

### Example: nested-if elimination

```zig
const option = @import("zfp").option;

// Before — nesting grows with every step
fn process(input: ?[]const u8) ?i32 {
    if (input) |s| {
        const n = std.fmt.parseInt(i32, s, 10) catch return null;
        if (n > 0) {
            return n * 2;
        }
    }
    return null;
}

// After — flat pipeline, same machine code
fn process(input: ?[]const u8) ?i32 {
    return option.andThen(
        option.andThen(input, parseInt),
        doubleIfPositive,
    );
}
```

---

## result

Eliminate nested `try`/`catch` chains without any runtime cost.

### API

```zig
const result = @import("zfp").result;

// Apply a function to the success value; propagate errors unchanged
result.map(value: E!T, f: fn(T) U) E!U

// Flatmap — f itself returns an error union
result.andThen(value: E!T, f: fn(T) E!U) E!U

// Return the success value or a default on error
result.unwrapOr(value: E!T, default: T) T

// Recover from an error using the error value
result.unwrapOrElse(value: E!T, f: fn(E) T) T

// Convert to optional, discarding error information
result.toOption(value: E!T) ?T

// Apply a wrapped function to a wrapped value (Applicative)
result.ap(f: E!fn(T)U, value: E!T) E!U

// First success wins (Alternative)
result.orElse(value: E!T, fallback: E!T) E!T

// Error checks
result.isOk(value: E!T) bool
result.isErr(value: E!T) bool
```

### Example: pipeline over fallible operations

```zig
const result = @import("zfp").result;

// Before
fn process(input: anyerror![]const u8) anyerror!i32 {
    const s = try input;
    const n = try std.fmt.parseInt(i32, s, 10);
    if (n <= 0) return error.OutOfRange;
    return n * 2;
}

// After — flat pipeline, same machine code
fn process(input: anyerror![]const u8) anyerror!i32 {
    return result.andThen(
        result.andThen(input, parseInt),
        doubleIfPositive,
    );
}
```

---

## pipe

Apply a sequence of functions to a value, left to right. No allocations, no closures, no runtime overhead.

### API

```zig
const pipe = @import("zfp").pipe;

// Apply functions left to right
pipe.run(value: A, .{ f: A→B, g: B→C, h: C→D }) D

// Empty list is the identity
pipe.run(value, .{}) // returns value unchanged
```

### Example: left-to-right composition

```zig
const pipe = @import("zfp").pipe;

// Before — nested calls, read right to left
const result = normalize(clamp(parse(raw)));

// After — pipeline, read left to right
const result = pipe.run(raw, .{ parse, clamp, normalize });

// Types change naturally across steps
// run(x: i32, .{ double: i32→i32, isPositive: i32→bool }) → bool
```

---

## compose

Compose a sequence of functions into a **reusable callable**. Unlike `pipe` which applies to a value immediately, `compose` returns a zero-size struct you can store and call many times.

### API

```zig
const compose = @import("zfp").compose;

// Compose functions left to right, return a reusable callable
const f = compose.from(.{ g: A→B, h: B→C });
f.run(x: A) // → C
```

### Example: reusable transformation

```zig
const compose = @import("zfp").compose;

// Before — tuple repeated at every call site
const a = normalize(clamp(parse(raw_a)));
const b = normalize(clamp(parse(raw_b)));

// After — define once, apply many times
const process = compose.from(.{ parse, clamp, normalize });
const a = process.run(raw_a);
const b = process.run(raw_b);
```

---

## zf

Primitive function combinators — the Zig equivalents of Haskell's `id`, `flip`, `const`, and `on`.

### API

```zig
const zf = @import("zfp").zf;

// Identity — returns the argument unchanged
zf.id(x: T) T

// Flip — call f with arguments swapped: flip(f, a, b) ≡ f(b, a)
zf.flip(f: fn(A,B)C, a: A, b: B) C

// Constant — return x, ignore the second argument
zf.const_(x: T, _: anytype) T

// On — apply g to both arguments, then combine with f: on(f, g, a, b) ≡ f(g(a), g(b))
zf.on(f: fn(B,B)C, g: fn(A)B, a: A, b: A) C
```

### Example: composing with combinators

```zig
const zf = @import("zfp").zf;

// Compare two strings by length
const byLength = struct {
    fn call(a: []const u8, b: []const u8) std.math.Order {
        return zf.on(std.math.order, strLen, a, b);
    }
}.call;

byLength("foo", "hello") // → .lt
byLength("hi",  "ok")    // → .eq
```

---

## tap

Inject side effects (logging, tracing, assertions) into a pipeline without interrupting the value flow.

### API

```zig
const tap = @import("zfp").tap;

// Call f(value) for its side effect, return value unchanged
tap.run(value: T, f: fn(T) void) T

// Return a concrete fn(T) T step for use inside pipe.run tuples
tap.typed(T: type, f: fn(T) void) fn(T) T
```

### Example: non-invasive logging

```zig
const tap  = @import("zfp").tap;
const pipe = @import("zfp").pipe;

// Before — split the pipeline just to log
const parsed    = parse(raw);
std.debug.print("parsed: {}\n", .{parsed});
const validated = validate(parsed);

// After — log without breaking the pipeline
const result = pipe.run(raw, .{
    parse,
    tap.typed(ParsedData, logParsed),
    validate,
    transform,
});
```

---

## arrow

Arrow combinators for working with pairs (two-element tuples). Transform each side of a pair independently, or split a single value into two paths.

### API

```zig
const arrow = @import("zfp").arrow;

// Apply f to the first element; second unchanged
arrow.first(f, .{a, b}) // → .{f(a), b}

// Apply g to the second element; first unchanged
arrow.second(g, .{a, b}) // → .{a, g(b)}

// Apply f to first, g to second  (f *** g)
arrow.split(f, g, .{a, b}) // → .{f(a), g(b)}

// Apply both f and g to the same value  (f &&& g)
arrow.fanout(f, g, a) // → .{f(a), g(a)}
```

### Example: parallel pair transformation

```zig
const arrow = @import("zfp").arrow;

// Before — unpack and repack manually
const result: struct { i32, usize } = .{
    @abs(raw_pair[0]),
    raw_pair[1].len,
};

// After — intent is clear
const result = arrow.split(absInt, strLen, .{ @as(i32, -3), "hello" });
// → .{ 3, 5 }

// Compute two values from a single input
const stats = arrow.fanout(sumSlice, countSlice, items);
// stats[0] = sum, stats[1] = count
```

---

## either

A `Left(L) | Right(R)` sum type for computations that can produce one of two distinct outcomes. Unlike `anyerror!T`, both sides can be any type.

### API

```zig
const either = @import("zfp").either;

// Type constructor
const E = either.Either(L, R);    // tagged union: { .left: L } | { .right: R }

// Functor / Monad
either.map(e, f)                  // apply f to Right; Left unchanged
either.andThen(e, f)              // flatMap on Right; short-circuit on Left

// Bifunctor
either.mapLeft(e, f)              // apply f to Left; Right unchanged
either.bimap(e, lf, rf)           // apply lf or rf to whichever side is active

// Predicates
either.isLeft(e) bool
either.isRight(e) bool

// Extract
either.unwrapOr(e, default)       // Right value or default
either.unwrapOrElse(e, f)         // Right value or f(left)

// Conversions
either.fromOption(opt, left_val)  // ?R → Either(L, R)
either.toOption(e)                // Either(L, R) → ?R
```

### Example: rich error types

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
        return if (n >= 0 and n <= 100) .{ .right = n } else .{ .left = "out of range" };
    }
}.call;

// Chain without nesting
const result = either.andThen(parse("42"), validate);
// → .{ .right = 42 }

const bad = either.andThen(parse("999"), validate);
// → .{ .left = "out of range" }
```

---

## slice

Foldable operations over Zig slices. All functions compile to the equivalent hand-written for loop — no allocations, no boxing.

### API

```zig
const slice = @import("zfp").slice;

// Fundamental fold (all others can be expressed as fold)
slice.fold(items, init, f)          // left fold: f(f(f(init, a), b), c)

// Predicates
slice.all(items, predicate)         // true if predicate holds for every item
slice.any(items, predicate)         // true if predicate holds for any item

// Search
slice.find(items, predicate)        // first match as ?T
slice.findIndex(items, predicate)   // index of first match as ?usize

// Count / iterate
slice.count(items, predicate)       // number of matching items
slice.forEach(items, f)             // call f on each item for side effects

// Numeric
slice.sum(items)                    // sum of all items (0 for empty)
slice.min(items)                    // smallest item as ?T (null for empty)
slice.max(items)                    // largest item as ?T (null for empty)
```

### Example: pipeline over a slice

```zig
const slice = @import("zfp").slice;

const scores = [_]i32{ 42, 7, 98, 13, 55, 76 };

// How many passing scores (≥ 50)?
const passing = slice.count(&scores, struct {
    fn call(x: i32) bool { return x >= 50; }
}.call);
// → 3

// Best score
const best = slice.max(&scores);
// → @as(?i32, 98)

// Total of passing scores only
const total = slice.fold(&scores, @as(i32, 0), struct {
    fn call(acc: i32, x: i32) i32 {
        return acc + if (x >= 50) x else 0;
    }
}.call);
// → 229
```

---

## monoid

Six named Semigroup / Monoid combinators. Each is a comptime namespace with `empty`, `append`, and `concat` — folds a slice to a single value with no allocation.

### API

```zig
const monoid = @import("zfp").monoid;

// Sum — numeric addition (identity = 0)
monoid.Sum.empty(T)         // → 0
monoid.Sum.append(a, b)     // → a + b
monoid.Sum.concat(items)    // → sum of all items

// Product — numeric multiplication (identity = 1)
monoid.Product.empty(T)     // → 1
monoid.Product.append(a, b) // → a * b
monoid.Product.concat(items)// → product of all items

// Any — boolean OR (identity = false, short-circuits)
monoid.Any.empty()          // → false
monoid.Any.append(a, b)     // → a or b
monoid.Any.concat(items)    // → true if any is true

// All — boolean AND (identity = true, short-circuits)
monoid.All.empty()          // → true
monoid.All.append(a, b)     // → a and b
monoid.All.concat(items)    // → true if all are true

// First — first non-null optional (identity = null)
monoid.First.empty(T)       // → null
monoid.First.append(a, b)   // → a orelse b
monoid.First.concat(items)  // → first non-null item

// Last — last non-null optional (identity = null)
monoid.Last.empty(T)        // → null
monoid.Last.append(a, b)    // → b orelse a
monoid.Last.concat(items)   // → last non-null item
```

### Example: intent over ceremony

```zig
const monoid = @import("zfp").monoid;

// Before — spell out identity and operation each time
var total: i32 = 1;
for (items) |x| total *= x;

var any_true = false;
for (flags) |f| any_true = any_true or f;

// After — intent captured in the name
const total    = monoid.Product.concat(&items);
const any_true = monoid.Any.concat(&flags);

// Aggregate a batch of results — find the first error, the last error
const results = [_]?[]const u8{ null, "timeout", null, "not found" };

const first_err = monoid.First.concat(&results); // → "timeout"
const last_err  = monoid.Last.concat(&results);  // → "not found"
```

---

## Why is it zero-cost?

In Zig, `inline fn` with `anytype` parameters is resolved entirely at compile time.
The compiler sees through every call and generates the same code as the manual `if`/`catch` version.
There is no virtual dispatch, no boxing, and no indirection.

---

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .zfp = .{
        .url = "https://github.com/O6lvl4/zfp/archive/<commit>.tar.gz",
        .hash = "<hash>",
    },
},
```

Then in `build.zig`:

```zig
const zfp = b.dependency("zfp", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zfp", zfp.module("zfp"));
```

---

## Development

```sh
zig build --help                 # List all available commands
zig build test --summary all     # Run all tests
zig build docs                   # Generate API docs → zig-out/docs/
zig build fmt                    # Format source files
zig build clean                  # Remove build artifacts (zig-out/, .zig-cache/)
```

Requires Zig `0.15.0` or later.

---

## License

MIT
