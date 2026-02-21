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
| `option` | ✅ | Utilities for Zig's native `?T` optional type |
| `result` | ✅ | Utilities for Zig's native `anyerror!T` error union type |
| `pipe` | ✅ | Left-to-right function pipeline with full type inference |
| `compose` | ✅ | Compose functions into a reusable callable |
| `func` | ✅ | Function combinators: `id`, `flip`, `const_`, `on` |

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

## func

Primitive function combinators — the Zig equivalents of Haskell's `id`, `flip`, `const`, and `on`.

### API

```zig
const func = @import("zfp").func;

// Identity — returns the argument unchanged
func.id(x: T) T

// Flip — call f with arguments swapped: flip(f, a, b) ≡ f(b, a)
func.flip(f: fn(A,B)C, a: A, b: B) C

// Constant — return x, ignore the second argument
func.const_(x: T, _: anytype) T

// On — apply g to both arguments, then combine with f: on(f, g, a, b) ≡ f(g(a), g(b))
func.on(f: fn(B,B)C, g: fn(A)B, a: A, b: A) C
```

### Example: composing with combinators

```zig
const func = @import("zfp").func;

// Compare two strings by length
const byLength = struct {
    fn call(a: []const u8, b: []const u8) std.math.Order {
        return func.on(std.math.order, strLen, a, b);
    }
}.call;

byLength("foo", "hello") // → .lt
byLength("hi",  "ok")    // → .eq
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
