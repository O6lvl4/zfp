# zfp Roadmap

This document tracks the current state and planned direction of `zfp`.

Every module must satisfy the core constraints:

- Works directly on Zig's native types — no wrapper structs
- Zero allocations, zero runtime overhead
- All public functions are `pub inline fn` with `anytype`
- Identical machine code to hand-written Zig

---

## Status

| Module | Native type | Status | Key functions |
|--------|------------|--------|---------------|
| `option` | `?T` | ✅ Done | `map`, `andThen`, `unwrapOr`, `filter`, `isSome`, `isNone` |
| `result` | `anyerror!T` | ✅ Done | `map`, `andThen`, `unwrapOr`, `unwrapOrElse`, `toOption`, `isOk`, `isErr` |
| `pipe` | — | ✅ Done | `run` |
| `compose` | — | ✅ Done | `from`, `run` |

---

## Planned

### `tap` — Side-effect injection in pipelines

Insert a side-effecting function (logging, debugging, tracing) into a `pipe.run` chain without altering the value flowing through.

```zig
const tap = @import("zfp").tap;

pipe.run(value, .{
    parse,
    tap.run(std.debug.print("after parse: {}\n", .{})),  // side effect, value passes through
    validate,
});
```

**Why**: Debugging pipelines currently requires breaking the chain. `tap` solves this without any runtime cost — the injected call is inlined and the value is forwarded unchanged.

---

### `fn` — Function combinators

Primitive building blocks for composing and transforming functions.

```zig
const f = @import("zfp").fn;

f.id(x)            // identity: returns x unchanged
f.flip(func, b, a) // swap first two arguments
f.const_(x)        // returns a function that always returns x
```

**Why**: Useful as glue in `pipe.run` and `compose.from` chains where a small adapter is needed without defining a named function.

---

### `slice` — Functional operations over slices

Zero-cost `fold` and `all`/`any` over slices. `filter` and runtime `map` are excluded as they require allocation.

```zig
const slice = @import("zfp").slice;

slice.fold(items, 0, add)        // left fold, no allocation
slice.all(items, isPositive)     // true if predicate holds for all
slice.any(items, isPositive)     // true if predicate holds for any
slice.find(items, isPositive)    // returns ?T, first matching element
```

**Why**: The most common use case for functional style in Zig is processing slices. `fold` is always zero-cost; `all`/`any`/`find` are short-circuiting loops — no allocation needed.

---

## Ideas (not yet planned)

These are worth exploring but need more thought before committing to an API.

| Idea | Note |
|------|------|
| `iter` | Functional adapters for Zig's `while (iter.next()) \|v\|` pattern. Needs a clean API that works without closures. |
| `comptime slice` | Fully comptime `map`/`filter` over arrays — possible with Zig's comptime, but API ergonomics are unclear. |
| `memo` | Memoization for pure functions. Requires allocation; may conflict with the zero-alloc constraint. |

---

## Non-goals

- **No allocator-required APIs in core modules.** Anything needing allocation belongs in a separate, clearly-named module.
- **No wrapper types.** `option` stays as `?T`, `result` stays as `anyerror!T`.
- **No async/concurrency utilities.** Out of scope.
