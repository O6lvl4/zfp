# arrow — Arrow Combinators

```zig
const arrow = @import("zfp").arrow;
```

## What is it?

`arrow` provides combinators for working with **pairs** (two-element tuples),
inspired by Haskell's `Arrow` typeclass.

Where `pipe` and `compose` thread a single value through a sequence of functions,
`arrow` lets you work with **two values in parallel** — transforming each side
of a pair independently, or splitting a single value into two paths.

---

## The Problem

Without `arrow`, parallel transformations on pairs require unpacking and repacking manually:

```zig
// Before — verbose pair manipulation
const raw_pair: struct { i32, []const u8 } = .{ -3, "hello" };
const result: struct { i32, usize } = .{
    @abs(raw_pair[0]),   // transform first
    raw_pair[1].len,     // transform second
};
```

With `arrow`, the intent is clear:

```zig
const arrow = @import("zfp").arrow;

const result = arrow.split(absInt, strLen, .{ @as(i32, -3), "hello" });
// → .{ 3, 5 }
```

---

## `first` — Transform the first element

**Haskell**: `first f (a, b) = (f a, b)`

Apply `f` to the first element; leave the second unchanged.

```zig
const arrow = @import("zfp").arrow;

arrow.first(double, .{ @as(i32, 3), @as(i32, 4) })
// → .{ 6, 4 }
```

The type of the first element can change:

```zig
arrow.first(isPositive, .{ @as(i32, 3), "hello" })
// → .{ true, "hello" }   (i32 → bool, []const u8 unchanged)
```

---

## `second` — Transform the second element

**Haskell**: `second g (a, b) = (a, g b)`

Apply `g` to the second element; leave the first unchanged.

```zig
const arrow = @import("zfp").arrow;

arrow.second(double, .{ @as(i32, 4), @as(i32, 3) })
// → .{ 4, 6 }
```

---

## `split` — Transform each element independently (`***`)

**Haskell**: `(f *** g) (a, b) = (f a, g b)`

Apply `f` to the first element and `g` to the second.

```zig
const arrow = @import("zfp").arrow;

arrow.split(double, negate, .{ @as(i32, 3), @as(i32, 4) })
// → .{ 6, -4 }
```

Types can differ across both sides:

```zig
arrow.split(isPositive, double, .{ @as(i32, 5), @as(i32, 3) })
// → .{ true, 6 }   (i32→bool on left, i32→i32 on right)
```

---

## `fanout` — Apply two functions to the same value (`&&&`)

**Haskell**: `(f &&& g) a = (f a, g a)`

Apply both `f` and `g` to a single value, producing a pair.

```zig
const arrow = @import("zfp").arrow;

arrow.fanout(double, isPositive, @as(i32, 5))
// → .{ 10, true }
```

`fanout` is the dual of `split`: where `split` takes a pair and transforms each
side, `fanout` takes a single value and fans it out into two paths.

---

## Why is it zero-cost?

All four functions are `pub inline fn` with `anytype` parameters.
Each compiles to the minimum number of function calls plus a tuple construction:

- `first(f, .{a, b})` → one call to `f`, one tuple literal
- `second(g, .{a, b})` → one call to `g`, one tuple literal
- `split(f, g, .{a, b})` → one call each to `f` and `g`, one tuple literal
- `fanout(f, g, a)` → one call each to `f` and `g`, one tuple literal

No allocation, no boxing, no intermediate structs.

---

## Composition example

`first`, `second`, `split`, and `fanout` compose naturally with `pipe.run`:

```zig
const arrow = @import("zfp").arrow;
const pipe  = @import("zfp").pipe;

// Parse a raw input into a (value, label) pair, then transform each side
const process = pipe.run("42:meters", .{
    splitOnColon,                                 // → .{ "42", "meters" }
    tap.typed(struct { []const u8, []const u8 }, logRaw),
    struct {
        fn call(p: struct { []const u8, []const u8 }) struct { i32, []const u8 } {
            return arrow.split(parseInt, toUpperCase, p);
        }
    }.call,                                       // → .{ 42, "METERS" }
});
```

Or building a summary pair with `fanout`:

```zig
// Compute both sum and count from a slice in one pass
const stats = arrow.fanout(sumSlice, countSlice, items);
// stats[0] = sum, stats[1] = count
```

---

## Relationship table

| Haskell | zfp | What it does |
|---------|-----|--------------|
| `first f (a, b)` | `arrow.first(f, .{a, b})` | `.{f(a), b}` |
| `second g (a, b)` | `arrow.second(g, .{a, b})` | `.{a, g(b)}` |
| `(f *** g) (a, b)` | `arrow.split(f, g, .{a, b})` | `.{f(a), g(b)}` |
| `(f &&& g) a` | `arrow.fanout(f, g, a)` | `.{f(a), g(a)}` |

---

## Further reading

- [Haskell Control.Arrow](https://hackage.haskell.org/package/base/docs/Control-Arrow.html)
- [Understanding Arrows (Haskell wiki)](https://wiki.haskell.org/Arrow_tutorial)
- [Zig anonymous struct tuples](https://ziglang.org/documentation/master/#Anonymous-Struct-Literals)
