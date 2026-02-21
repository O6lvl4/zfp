# monoid — Semigroup / Monoid Combinators

```zig
const monoid = @import("zfp").monoid;
```

## What is it?

A **Monoid** is a type with three things:

1. An **identity element** `empty` — combining it with anything leaves the other value unchanged
2. An **associative binary operation** `append` — order of grouping doesn't matter
3. **`concat`** — fold a whole slice using `append`, starting from `empty`

`monoid` provides six named monoids as comptime namespaces, each with `empty`, `append`, and `concat`:

| Namespace | Identity | Operation |
|-----------|----------|-----------|
| `Sum` | `0` | `a + b` |
| `Product` | `1` | `a * b` |
| `Any` | `false` | `a or b` |
| `All` | `true` | `a and b` |
| `First` | `null` | first non-null |
| `Last` | `null` | last non-null |

---

## The Problem

Folding a slice with different "combine" semantics requires repeating the pattern every time:

```zig
// Before — spell out identity and operation each time
var total: i32 = 1;
for (items) |x| total *= x;

var any_true = false;
for (flags) |f| any_true = any_true or f;

var first: ?i32 = null;
for (opts) |o| if (first == null) { first = o; };
```

With `monoid`, the intent is captured in the name:

```zig
const monoid = @import("zfp").monoid;

const total     = monoid.Product.concat(&items);
const any_true  = monoid.Any.concat(&flags);
const first_val = monoid.First.concat(&opts);
```

---

## `Sum` — Numeric addition

**Haskell**: `newtype Sum a = Sum { getSum :: a }`

```zig
const monoid = @import("zfp").monoid;

monoid.Sum.empty(i32)                    // → 0
monoid.Sum.append(@as(i32, 3), 4)        // → 7
monoid.Sum.concat(&.{ 1, 2, 3, 4 })     // → 10
monoid.Sum.concat(&([_]i32{})[0..])     // → 0  (empty)
```

Works with any numeric type — `i32`, `u64`, `f32`, …

---

## `Product` — Numeric multiplication

**Haskell**: `newtype Product a = Product { getProduct :: a }`

```zig
const monoid = @import("zfp").monoid;

monoid.Product.empty(i32)                  // → 1
monoid.Product.append(@as(i32, 3), 4)      // → 12
monoid.Product.concat(&.{ 1, 2, 3, 4 })   // → 24
monoid.Product.concat(&([_]i32{})[0..])   // → 1  (empty)
```

---

## `Any` — Boolean disjunction (OR)

**Haskell**: `newtype Any = Any { getAny :: Bool }`

```zig
const monoid = @import("zfp").monoid;

monoid.Any.empty()                              // → false
monoid.Any.append(false, true)                  // → true
monoid.Any.concat(&.{ false, false, true })     // → true
monoid.Any.concat(&.{ false, false, false })    // → false
monoid.Any.concat(&([_]bool{})[0..])            // → false (empty)
```

`concat` short-circuits: stops at the first `true`.

---

## `All` — Boolean conjunction (AND)

**Haskell**: `newtype All = All { getAll :: Bool }`

```zig
const monoid = @import("zfp").monoid;

monoid.All.empty()                              // → true
monoid.All.append(true, false)                  // → false
monoid.All.concat(&.{ true, true, true })       // → true
monoid.All.concat(&.{ true, false, true })      // → false
monoid.All.concat(&([_]bool{})[0..])            // → true (vacuously)
```

`concat` short-circuits: stops at the first `false`.

---

## `First` — First non-null optional

**Haskell**: `newtype First a = First { getFirst :: Maybe a }`

```zig
const monoid = @import("zfp").monoid;

monoid.First.empty(i32)                                      // → null
monoid.First.append(@as(?i32, 1), @as(?i32, 2))             // → 1
monoid.First.append(@as(?i32, null), @as(?i32, 2))          // → 2
monoid.First.concat(&.{ @as(?i32, null), 2, 3 })            // → 2
monoid.First.concat(&([_]?i32{})[0..])                      // → null (empty)
```

---

## `Last` — Last non-null optional

**Haskell**: `newtype Last a = Last { getLast :: Maybe a }`

```zig
const monoid = @import("zfp").monoid;

monoid.Last.empty(i32)                                       // → null
monoid.Last.append(@as(?i32, 1), @as(?i32, 2))              // → 2
monoid.Last.append(@as(?i32, 1), @as(?i32, null))           // → 1
monoid.Last.concat(&.{ @as(?i32, 1), 2, null })             // → 2
monoid.Last.concat(&([_]?i32{})[0..])                       // → null (empty)
```

---

## The Monoid laws

Every monoid satisfies these laws. `zfp` verifies them in tests:

```
append(empty, x)        ≡  x       (left identity)
append(x, empty)        ≡  x       (right identity)
append(append(x,y), z)  ≡  append(x, append(y,z))  (associativity)
```

`concat(items) ≡ fold(items, empty, append)` for any non-empty or empty slice.

---

## Why is it zero-cost?

All functions are `pub inline fn`. Each compiles to the simplest possible expression:

```zig
// Sum.concat compiles to:
var acc: T = 0;
for (items) |item| acc += item;

// Any.concat compiles to:
for (items) |item| if (item) return true;
return false;
```

No virtual dispatch. No runtime type information. No allocations.

---

## Composition example

Aggregate a batch of results — count successes and find the first failure:

```zig
const monoid = @import("zfp").monoid;
const slice  = @import("zfp").slice;

const results = [_]?[]const u8{
    null,           // success (no error message)
    "timeout",      // failure
    null,           // success
    "not found",    // failure
};

// How many successes? (null = success)
const successes = slice.count(&results, struct {
    fn call(r: ?[]const u8) bool { return r == null; }
}.call);
// → 2

// First error message
const first_error = monoid.First.concat(&results);
// → @as(?[]const u8, "timeout")

// Last error message
const last_error = monoid.Last.concat(&results);
// → @as(?[]const u8, "not found")
```

---

## Relationship table

| Haskell | zfp | Identity | Operation |
|---------|-----|----------|-----------|
| `Sum` | `monoid.Sum` | `Sum.empty(T)` = `0` | `Sum.append(a, b)` = `a + b` |
| `Product` | `monoid.Product` | `Product.empty(T)` = `1` | `Product.append(a, b)` = `a * b` |
| `Any` | `monoid.Any` | `Any.empty()` = `false` | `Any.append(a, b)` = `a or b` |
| `All` | `monoid.All` | `All.empty()` = `true` | `All.append(a, b)` = `a and b` |
| `First` | `monoid.First` | `First.empty(T)` = `null` | `First.append(a, b)` = `a orelse b` |
| `Last` | `monoid.Last` | `Last.empty(T)` = `null` | `Last.append(a, b)` = `b orelse a` |

---

## Further reading

- [Haskell Data.Monoid](https://hackage.haskell.org/package/base/docs/Data-Monoid.html)
- [Haskell Data.Semigroup](https://hackage.haskell.org/package/base/docs/Data-Semigroup.html)
- [Monoids — Typeclassopedia](https://wiki.haskell.org/Typeclassopedia#Monoid)
- [Zig comptime](https://ziglang.org/documentation/master/#comptime)
