# zfp Roadmap

The goal of `zfp` is a **complete, zero-cost functional programming library for Zig**, drawing from Haskell's typeclass hierarchy as the design reference.

Every module must satisfy the core constraints:

- Works directly on Zig's native types — no wrapper structs where possible
- Zero allocations, zero runtime overhead (allocation-requiring modules are clearly marked)
- All public functions are `pub inline fn` with `anytype`
- Identical machine code to hand-written Zig

> **Note on HKT**: Zig has no higher-kinded types. There is no single `Functor` typeclass that spans all modules. Instead, each module implements the same interface (`map`, `andThen`, …) independently and consistently. This is the Zig-idiomatic equivalent.

---

## Haskell → zfp Mapping

| Haskell concept | zfp module | Notes |
|----------------|-----------|-------|
| `Maybe` | `option` ✅ | Native `?T` |
| `Either e a` | `either` | Native tagged union |
| `Functor` (`fmap`) | `map` in each module | Per-type, no HKT |
| `Monad` (`>>=`) | `andThen` in each module | Per-type |
| `Applicative` (`<*>`) | `ap` in each module | Applying wrapped fn to wrapped value |
| `Alternative` (`<\|>`) | `orElse` in each module | First success wins |
| `Category` (`id`, `>>>`) | `compose` ✅ | `from`, `run` |
| `Arrow` (`arr`, `>>>`, `***`) | `arrow` | Builds on `compose` |
| `Foldable` | `slice` | `fold`, `all`, `any`, `find` over slices |
| `Traversable` | `traverse` | Needs allocation — clearly marked |
| `Semigroup` / `Monoid` | `monoid` | `append`, `empty` protocol |
| `State` monad | `state` | Comptime pure, zero-cost |
| `Reader` monad | `reader` | Dependency injection pattern |
| `Writer` monad | `writer` | Accumulation / logging |
| `Cont` monad | `cont` | Continuation-passing style |
| Function combinators | `zf` ✅ | `id`, `flip`, `const_`, `on` |
| Debug / tracing | `tap` | Side-effects in pipelines |
| `List` monad | `list` | Requires allocation — clearly marked |
| `IO` monad | — | Not applicable; Zig is imperative |

---

## Status

| Module | Native type | Status | Key functions |
|--------|------------|--------|---------------|
| `option` | `?T` | ✅ Done | `map`, `andThen`, `unwrapOr`, `filter`, `isSome`, `isNone` |
| `result` | `anyerror!T` | ✅ Done | `map`, `andThen`, `unwrapOr`, `unwrapOrElse`, `toOption`, `isOk`, `isErr` |
| `pipe` | — | ✅ Done | `run` |
| `compose` | — | ✅ Done | `from`, `run` |
| `zf` | — | ✅ Done | `id`, `flip`, `const_`, `on` |
| `tap` | — | ✅ Done | `run`, `typed` |
| `arrow` | — | ✅ Done | `first`, `second`, `split`, `fanout` |
| `either` | tagged union | ✅ Done | `map`, `mapLeft`, `bimap`, `andThen`, `isLeft`, `isRight`, `unwrapOr`, `unwrapOrElse`, `fromOption`, `toOption` |
| `slice` | `[]T` | ✅ Done | `fold`, `all`, `any`, `find`, `findIndex`, `count`, `forEach`, `sum`, `min`, `max` |
| `monoid` | — | ✅ Done | `Sum`, `Product`, `Any`, `All`, `First`, `Last` (each with `empty`, `append`, `concat`) |

---

## Phase 2 — Arrow & Function primitives

### ~~`zf` — Function combinators~~ ✅ Done

### ~~`tap` — Side-effect injection in pipelines~~ ✅ Done

```zig
const tap = @import("zfp").tap;

pipe.run(value, .{
    parse,
    tap.run(logFn),  // calls logFn(value) for side effect, passes value through
    validate,
});
```

### ~~`arrow` — Arrow typeclass~~ ✅ Done

Extends `compose` with parallel and fanout combinators.

```zig
const arrow = @import("zfp").arrow;

arrow.split(f, g, .{ a, b })   // (f *** g): apply f to a, g to b → .{ f(a), g(b) }
arrow.fanout(f, g, a)          // (f &&& g): apply both f and g to a → .{ f(a), g(a) }
arrow.first(f, .{ a, b })      // apply f only to first element
arrow.second(g, .{ a, b })     // apply g only to second element
```

---

## Phase 3 — Typeclass analogs

### ~~`either` — Explicit Left / Right (Bifunctor)~~ ✅ Done

Zig's `anyerror!T` is close to `Either` but the error side is restricted to error sets. `either` provides a proper `Left(A) | Right(B)` tagged union with full `bimap`.

```zig
const either = @import("zfp").either;

// either.Either(L, R) — a tagged union
either.map(e, f)                   // apply f to Right, pass Left unchanged
either.mapLeft(e, f)               // apply f to Left, pass Right unchanged
either.bimap(e, leftFn, rightFn)   // apply to whichever side is active
either.andThen(e, f)               // monadic bind on Right
either.fromOption(opt, leftVal)    // ?T → Either(L, R)
either.toOption(e)                 // Either → ?T, discarding Left
```

### ~~`ap` — Applicative (`<*>`)~~ ✅ Done

Applying a wrapped function to a wrapped value. Added to `option` and `result`.

```zig
// option.ap(?fn(T)U, ?T) → ?U
option.ap(some_fn, some_val)

// result.ap(E!fn(T)U, E!T) → E!U
result.ap(ok_fn, ok_val)
```

### ~~`orElse` — Alternative (`<|>`)~~ ✅ Done

First success wins. Added to `option` and `result`.

```zig
option.orElse(null, @as(?i32, 42))    // → 42
result.orElse(error.Bad, fallback)    // → fallback if error
```

### ~~`slice` — Foldable over slices~~ ✅ Done

```zig
const slice = @import("zfp").slice;

slice.fold(items, initial, f)   // left fold — no allocation
slice.all(items, predicate)     // true if predicate holds for all
slice.any(items, predicate)     // true if any
slice.find(items, predicate)    // returns ?T, first match
slice.count(items, predicate)   // count matching elements
```

### ~~`monoid` — Semigroup / Monoid protocol~~ ✅ Done

```zig
const monoid = @import("zfp").monoid;

monoid.Sum.concat(&items)    // sum of all items
monoid.Product.concat(&items)// product of all items
monoid.Any.concat(&flags)    // true if any is true
monoid.All.concat(&flags)    // true if all are true
monoid.First.concat(&opts)   // first non-null
monoid.Last.concat(&opts)    // last non-null
```

---

## Phase 4 — Monad transformers

### `state` — State monad

A pure, zero-cost state threading pattern. The state is passed explicitly — no globals, no mutation.

```zig
const state = @import("zfp").state;

// State(S, A) = fn(S) struct { value: A, next: S }
const counter = state.get();
const incremented = state.modify(counter, addOne);
const result = state.run(incremented, initialState);
```

### `reader` — Reader monad (dependency injection)

```zig
const reader = @import("zfp").reader;

// Reader(R, A) = fn(R) A
const getName = reader.asks(fn(env: Env) []const u8 { return env.name; });
const program = reader.map(getName, toUpperCase);
const result  = reader.run(program, myEnv);
```

### `writer` — Writer monad (accumulation)

```zig
const writer = @import("zfp").writer;

// Writer(W, A) = struct { value: A, log: W }
const w = writer.tell("step 1 complete");
const mapped = writer.map(w, double);
const .{ value, log } = writer.run(mapped);
```

### `cont` — Continuation monad (CPS)

```zig
const cont = @import("zfp").cont;

// Cont(R, A) = fn(fn(A) R) R
const c = cont.pure(42);
const mapped = cont.map(c, double);
const result = cont.run(mapped, identity);
```

---

## Phase 5 — Allocation-aware (clearly marked)

These modules require an allocator and are explicitly not zero-cost. They are still zero-overhead in the sense that they do exactly what a hand-written version would do.

### `traverse` — Traversable

Convert a sequence of wrapped values into a wrapped sequence.

```zig
// [?T] → ?[]T  (returns null if any element is null)
traverse.option(allocator, items, f)

// [E!T] → E![]T  (returns first error if any)
traverse.result(allocator, items, f)
```

### `list` — List monad (non-determinism)

```zig
// flatMap over slices — like Haskell's list monad
list.andThen(allocator, items, f)   // f returns a slice; results are concatenated
list.pure(allocator, x)             // wrap single value in a list
```

---

## Non-goals

- **No wrapper types for `?T` and `anyerror!T`.** These stay as native Zig types.
- **No lazy evaluation by default.** Zig is strict; laziness requires explicit opt-in.
- **No `IO` monad.** Zig handles effects imperatively.
- **No runtime typeclass dispatch.** All generics are resolved at comptime.
