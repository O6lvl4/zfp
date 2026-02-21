# pipe — Left-to-Right Function Pipeline

## The Problem: Reading Code Backwards

Functional composition in most languages requires nesting calls, which forces you to read them inside-out:

```zig
const result = normalize(clamp(parse(raw)));
//                                  ^^^^ read from here
//                         ^^^^^
//              ^^^^^^^^^
```

The execution order is `parse → clamp → normalize`, but the code reads right-to-left.
As the pipeline grows, the nesting deepens and readability drops.

---

## The Solution: pipe

`pipe` applies a sequence of functions to a value, **left to right**:

```zig
const pipe = @import("zfp").pipe;

const result = pipe.pipe(raw, .{ parse, clamp, normalize });
//                             ^^^^  ^^^^^  ^^^^^^^^^
//                             step1 step2  step3 — read left to right
```

Execution order matches reading order. Adding a step means appending to the tuple.

---

## API

```zig
pipe.pipe(value: A, fns: tuple) ReturnType
```

- `value` — the initial input
- `fns` — an anonymous struct (tuple literal) of functions, applied left to right
- Returns the output type of the last function

The empty tuple is the identity:

```zig
pipe.pipe(x, .{}) // returns x unchanged
```

---

## Type Inference

Types flow through the pipeline at **compile time**. Each function's return type becomes the next function's input type:

```zig
// i32 → i32 → bool
const positive = pipe.pipe(@as(i32, 3), .{ double, isPositive });
//                                              ^       ^
//                                         i32→i32  i32→bool
// type of `positive` is bool
```

No type annotations required. The compiler verifies each step is compatible.

---

## Examples

### Basic pipeline

```zig
const pipe = @import("zfp").pipe;

fn double(x: i32) i32 { return x * 2; }
fn addOne(x: i32) i32 { return x + 1; }
fn negate(x: i32) i32 { return -x; }

// 3 → 6 → 7 → -7
const result = pipe.pipe(@as(i32, 3), .{ double, addOne, negate });
// result == -7
```

### Type-changing pipeline

```zig
const pipe = @import("zfp").pipe;

fn length(s: []const u8) usize { return s.len; }
fn doubled(n: usize) usize { return n * 2; }

// "hello" → 5 → 10
const result = pipe.pipe(@as([]const u8, "hello"), .{ length, doubled });
// result == 10, type is usize
```

### Real-world: text processing

```zig
const pipe = @import("zfp").pipe;
const std = @import("std");

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " ");
}
fn toUpper(allocator: std.mem.Allocator) fn([]const u8) []u8 {
    // ... (allocator-aware version)
}

// Before
const result = try validate(parseInt(trim(raw)));

// After
const result = pipe.pipe(raw, .{ trim, parseInt, validate });
```

---

## Composing with option and result

`pipe` works naturally with the `option` and `result` modules since they all deal with plain functions:

```zig
const zfp = @import("zfp");
const pipe = zfp.pipe;
const option = zfp.option;

fn parseInt(s: []const u8) ?i32 {
    return std.fmt.parseInt(i32, s, 10) catch null;
}
fn doubleIfPositive(n: i32) ?i32 {
    return if (n > 0) n * 2 else null;
}

// Chain option-returning functions with option.andThen,
// then apply a final transform with pipe
const raw: ?[]const u8 = "21";
const result = option.andThen(
    option.andThen(raw, parseInt),
    doubleIfPositive,
);
// result == ?i32(42)
```

---

## Zero Cost

`pipe` is a **comptime construct**. The tuple of functions exists only at compile time.
`PipeReturn` threads the type through each step recursively at compile time.
`applyFrom` is recursively inlined — each specialisation is a distinct call the compiler sees through.

The generated machine code is identical to:

```zig
negate(addOne(double(x)))
```

No indirection. No closures. No allocations.

---

## When to Use pipe vs. Direct Nesting

| Situation | Recommendation |
|-----------|---------------|
| 1–2 transforms | Direct nesting is fine |
| 3+ transforms | `pipe` improves readability |
| Types change across steps | `pipe` with type inference |
| Conditional steps | Combine with `option`/`result` |
| Need to name intermediate values | Use `const` assignments |
