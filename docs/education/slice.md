# slice — Foldable over Slices

```zig
const slice = @import("zfp").slice;
```

## What is it?

`slice` brings Haskell's `Foldable` typeclass to Zig slices (`[]T` and `[]const T`).

Every function compiles to the equivalent hand-written `for` loop. There are no allocations, no boxing, and no abstraction overhead — just a zero-cost vocabulary for common slice operations.

---

## The Problem

Without `slice`, every traversal is a manual `for` loop with ad-hoc accumulation:

```zig
// Before — boilerplate for every traversal
var total: i32 = 0;
for (scores) |s| total += s;

var passing: usize = 0;
for (scores) |s| if (s >= 50) { passing += 1; };

var best: ?i32 = null;
for (scores) |s| if (best == null or s > best.?) { best = s; };
```

With `slice`, the intent is on the surface:

```zig
const slice = @import("zfp").slice;

const total   = slice.sum(&scores);
const passing = slice.count(&scores, struct { fn call(x: i32) bool { return x >= 50; } }.call);
const best    = slice.max(&scores);
```

---

## `fold` — The fundamental operation

**Haskell**: `foldl :: (b -> a -> b) -> b -> [a] -> b`

Left fold. All other combinators can be expressed as fold.

```zig
const slice = @import("zfp").slice;

// Sum
slice.fold(&items, @as(i32, 0), struct {
    fn call(acc: i32, x: i32) i32 { return acc + x; }
}.call)
// → 10  for items = [1, 2, 3, 4]

// Product
slice.fold(&items, @as(i32, 1), struct {
    fn call(acc: i32, x: i32) i32 { return acc * x; }
}.call)
// → 24  for items = [1, 2, 3, 4]
```

Returns `init` for an empty slice.

---

## `all` / `any` — Predicates

**Haskell**: `all`, `any`

```zig
const slice = @import("zfp").slice;

const isPositive = struct { fn call(x: i32) bool { return x > 0; } }.call;

slice.all(&.{ 1, 2, 3 }, isPositive)   // → true
slice.all(&.{ 1, -2, 3 }, isPositive)  // → false (short-circuits)
slice.all(&.{}, isPositive)             // → true  (vacuously true)

slice.any(&.{ -1, 2, -3 }, isPositive)  // → true  (short-circuits)
slice.any(&.{ -1, -2, -3 }, isPositive) // → false
slice.any(&.{}, isPositive)             // → false
```

Both short-circuit: `all` returns `false` on the first failure; `any` returns `true` on the first match.

---

## `find` — First match

**Haskell**: `find :: Foldable t => (a -> Bool) -> t a -> Maybe a`

```zig
const slice = @import("zfp").slice;

slice.find(&.{ -1, -2, 3, 4 }, isPositive)  // → @as(?i32, 3)
slice.find(&.{ -1, -2, -3 }, isPositive)    // → null
```

Returns `?T` — `null` when no item matches.

---

## `findIndex` — Index of first match

```zig
const slice = @import("zfp").slice;

slice.findIndex(&.{ -1, -2, 3, 4 }, isPositive)  // → @as(?usize, 2)
slice.findIndex(&.{ -1, -2, -3 }, isPositive)    // → null
```

Returns `?usize` — `null` when no item matches.

---

## `count` — Count matching items

**Haskell**: `length . filter p`

```zig
const slice = @import("zfp").slice;

slice.count(&.{ 1, -2, 3, -4, 5 }, isPositive)  // → 3
slice.count(&.{ -1, -2, -3 }, isPositive)        // → 0
slice.count(&.{}, isPositive)                    // → 0
```

---

## `forEach` — Side effects

**Haskell**: `traverse_`

Call `f` on each item for its side effect. Returns nothing; the value is not threaded through.

```zig
const slice = @import("zfp").slice;

slice.forEach(&items, struct {
    fn call(x: i32) void {
        std.debug.print("{d}\n", .{x});
    }
}.call);
```

Use `fold` when you need to accumulate; use `forEach` when you only need side effects.

---

## `sum` — Sum of all items

**Haskell**: `sum :: (Foldable t, Num a) => t a -> a`

Works on any numeric type (`i32`, `u64`, `f32`, …).

```zig
const slice = @import("zfp").slice;

slice.sum(&.{ 1, 2, 3, 4, 5 })    // → @as(i32, 15)
slice.sum(&.{ 1.0, 2.5, 0.5 })    // → @as(f32, 4.0)
slice.sum(&([_]i32{})[0..])        // → @as(i32, 0)  (empty → 0)
```

---

## `min` / `max` — Extreme values

**Haskell**: `minimum`, `maximum`

```zig
const slice = @import("zfp").slice;

slice.min(&.{ 3, 1, 4, 1, 5, 9 })  // → @as(?i32, 1)
slice.max(&.{ 3, 1, 4, 1, 5, 9 })  // → @as(?i32, 9)

slice.min(&([_]i32{})[0..])         // → null  (empty slice)
slice.max(&([_]i32{})[0..])         // → null  (empty slice)
```

Returns `?T` — `null` for an empty slice (no sensible default exists).

---

## Why is it zero-cost?

All ten functions are `pub inline fn` with `anytype` parameters.

Each compiles to the minimum loop Zig's optimizer would generate by hand:

```zig
// slice.count(items, predicate) compiles to:
var n: usize = 0;
for (items) |item| {
    if (predicate(item)) n += 1;
}
```

No virtual dispatch. No allocations. No intermediate collections.

The element type is extracted at comptime using `std.meta.Elem` — this avoids any runtime type information and works with `[]T`, `[]const T`, and `*[N]T` (pointer-to-array) equally.

---

## Composition example

```zig
const slice = @import("zfp").slice;
const pipe  = @import("zfp").pipe;

const scores = [_]i32{ 42, 7, 98, 13, 55, 76 };

// How many passing scores (≥ 50)?
const isPassing = struct { fn call(x: i32) bool { return x >= 50; } }.call;
const passing = slice.count(&scores, isPassing);
// → 3

// Best score
const best = slice.max(&scores);
// → @as(?i32, 98)

// Sum of passing scores only
const total = slice.fold(&scores, @as(i32, 0), struct {
    fn call(acc: i32, x: i32) i32 {
        return acc + if (x >= 50) x else 0;
    }
}.call);
// → 229

// Is every score non-negative?
const allNonNeg = slice.all(&scores, struct {
    fn call(x: i32) bool { return x >= 0; }
}.call);
// → true
```

Combining with `option` for safe lookup:

```zig
const option = @import("zfp").option;

// Find the first score above 90, then double it
const result = option.map(
    slice.find(&scores, struct { fn call(x: i32) bool { return x > 90; } }.call),
    struct { fn call(x: i32) i32 { return x * 2; } }.call,
);
// → @as(?i32, 196)
```

---

## Relationship table

| Haskell | zfp | What it does |
|---------|-----|--------------|
| `foldl f z xs` | `slice.fold(xs, z, f)` | Left fold |
| `all p xs` | `slice.all(xs, p)` | All match |
| `any p xs` | `slice.any(xs, p)` | Any match |
| `find p xs` | `slice.find(xs, p)` | First match as `?T` |
| `findIndex p xs` | `slice.findIndex(xs, p)` | Index of first match as `?usize` |
| `length (filter p xs)` | `slice.count(xs, p)` | Count matching |
| `mapM_ f xs` | `slice.forEach(xs, f)` | Side effects only |
| `sum xs` | `slice.sum(xs)` | Sum of all items |
| `minimum xs` | `slice.min(xs)` | Smallest item as `?T` |
| `maximum xs` | `slice.max(xs)` | Largest item as `?T` |

---

## Further reading

- [Haskell Data.Foldable](https://hackage.haskell.org/package/base/docs/Data-Foldable.html)
- [Rust Iterator](https://doc.rust-lang.org/std/iter/trait.Iterator.html) — similar combinators
- [Zig for loops](https://ziglang.org/documentation/master/#for)
- [std.meta.Elem](https://ziglang.org/documentation/master/std/#std.meta.Elem)
