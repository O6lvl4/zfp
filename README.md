# zfp — Zero-cost Functional Programming for Zig

A minimal, zero-cost functional programming toolkit built on top of Zig's native types.

No wrappers. No allocations. No runtime overhead.
Pure comptime generics that compile away completely.

---

## Philosophy

- **Do not wrap native types.** `option` works directly on `?T`, not a struct around it.
- **Zero cost.** Every function is `inline`. The generated code is identical to hand-written `if` blocks.
- **Minimal API.** One function per concept. Composable by design.
- **Idiomatic Zig.** No macros, no hidden allocations, no magic.

---

## Modules

| Module | Status | Description |
|--------|--------|-------------|
| `option` | ✅ | Utilities for Zig's native `?T` optional type |

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
const zfp = @import("zfp");
const opt = zfp.option;

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
    return opt.andThen(
        opt.andThen(input, parseInt),
        doubleIfPositive,
    );
}
```

### Why is it zero-cost?

In Zig, `inline fn` with `anytype` parameters is resolved entirely at compile time.
The compiler sees through every call and generates the same code as the manual `if` version.
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
# Run all tests
zig build test

# Run tests with summary
zig build test --summary all
```

Requires Zig `0.15.0` or later.

---

## License

MIT
