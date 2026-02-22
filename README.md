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

| Module | Description |
|--------|-------------|
| `option` | Functor / Monad / Applicative for `?T` |
| `result` | Functor / Monad / Applicative for `anyerror!T` |
| `either` | `Left(L) \| Right(R)` sum type — Bifunctor, Monad |
| `pipe` | Left-to-right function pipeline |
| `compose` | Reusable composed callable |
| `zf` | Primitive combinators: `id`, `flip`, `const_`, `on` |
| `tap` | Side-effect injection without breaking pipelines |
| `arrow` | Pair combinators: `first`, `second`, `split`, `fanout` |
| `slice` | Foldable operations over slices |
| `monoid` | Named monoids: `Sum`, `Product`, `Any`, `All`, `First`, `Last`, `Endo` |

---

## option

Eliminate deeply nested `if (value) |v|` chains.

```zig
const option = @import("zfp").option;

// Before — nesting grows with every step
fn process(input: ?[]const u8) ?i32 {
    if (input) |s| {
        const n = std.fmt.parseInt(i32, s, 10) catch return null;
        if (n > 0) return n * 2;
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

Eliminate nested `try`/`catch` chains.

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

## either

`Left(L) | Right(R)` — when both sides carry meaningful values, unlike `anyerror!T`.

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

either.andThen(parse("42"), validate);  // → .{ .right = 42 }
either.andThen(parse("999"), validate); // → .{ .left = "out of range" }
```

---

## pipe

Apply a sequence of functions left to right.

```zig
const pipe = @import("zfp").pipe;

// Before — nested calls, read right to left
const result = normalize(clamp(parse(raw)));

// After — pipeline, read left to right
const result = pipe.run(raw, .{ parse, clamp, normalize });
```

---

## compose

Like `pipe`, but returns a **reusable callable** instead of applying immediately.

```zig
const compose = @import("zfp").compose;

const process = compose.from(.{ parse, clamp, normalize });

const a = process.run(raw_a);
const b = process.run(raw_b);
```

---

## zf

Primitive function combinators.

```zig
const zf = @import("zfp").zf;

// Compare strings by length using `on`
const byLength = struct {
    fn call(a: []const u8, b: []const u8) std.math.Order {
        return zf.on(std.math.order, strLen, a, b);
    }
}.call;

byLength("foo", "hello") // → .lt
```

---

## tap

Inject side effects into a pipeline without interrupting the value flow.

```zig
const tap  = @import("zfp").tap;
const pipe = @import("zfp").pipe;

const result = pipe.run(raw, .{
    parse,
    tap.typed(ParsedData, logParsed), // logs, then passes value through unchanged
    validate,
    transform,
});
```

---

## arrow

Combinators for pairs (two-element tuples).

```zig
const arrow = @import("zfp").arrow;

// Apply f to first element, g to second  (f *** g)
arrow.split(absInt, strLen, .{ @as(i32, -3), "hello" });
// → .{ 3, 5 }

// Fork a single value into two paths  (f &&& g)
arrow.fanout(sumSlice, countSlice, items);
// → .{ sum, count }
```

---

## slice

Foldable operations over slices.

```zig
const slice = @import("zfp").slice;

const scores = [_]i32{ 42, 7, 98, 13, 55, 76 };

slice.count(&scores, isPassingGrade); // → 3
slice.max(&scores);                   // → @as(?i32, 98)
slice.fold(&scores, @as(i32, 0), sumPassing); // → 229
```

---

## monoid

Named monoids — fold a slice with a named combining strategy.

```zig
const monoid = @import("zfp").monoid;

// Before — spell out identity and operation each time
var total: i32 = 1;
for (items) |x| total *= x;

// After — intent captured in the name
const total    = monoid.Product.concat(&items);
const any_true = monoid.Any.concat(&flags);

// First / Last over optional slices
const results = [_]?[]const u8{ null, "timeout", null, "not found" };
monoid.First.concat(&results); // → "timeout"
monoid.Last.concat(&results);  // → "not found"
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
