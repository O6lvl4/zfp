# compose — Reusable Function Composition

## pipe vs. compose

The `pipe` module applies functions to a value immediately and returns the result.
The `compose` module returns a **new callable** that you can apply later, store, and reuse.

```zig
const pipe    = @import("zfp").pipe;
const compose = @import("zfp").compose;

// pipe: apply now, get result
const result = pipe.run(3, .{ double, addOne }); // 7

// compose: create a reusable function, apply later
const f = compose.from(.{ double, addOne });
const result = f.call(3); // 7
const again  = f.call(5); // 11  — same transformation, different input
```

---

## The Problem: Repeated Transformation Tuples

When the same pipeline is applied at multiple call sites, `pipe` requires repeating the tuple:

```zig
const a = normalize(clamp(parse(raw_a)));
const b = normalize(clamp(parse(raw_b)));
const c = normalize(clamp(parse(raw_c)));
```

Even with `pipe`, the tuple is repeated:

```zig
const a = pipe.run(raw_a, .{ parse, clamp, normalize });
const b = pipe.run(raw_b, .{ parse, clamp, normalize }); // repeated
const c = pipe.run(raw_c, .{ parse, clamp, normalize }); // repeated
```

---

## The Solution: Named, Reusable Composition

`compose` lets you define the transformation once and give it a name:

```zig
const compose = @import("zfp").compose;

const process = compose.from(.{ parse, clamp, normalize });

const a = process.call(raw_a);
const b = process.call(raw_b);
const c = process.call(raw_c);
```

The transformation is defined in one place. Both machine code paths are identical.

---

## API

```zig
compose.from(fns: tuple) Callable
```

- `fns` — anonymous struct (tuple literal) of functions, applied left to right
- Returns a **zero-size struct** with a single `call` method

```zig
callable.call(value: A) ReturnType
```

- Applies the composed function to `value`
- Return type is inferred from the last function in the tuple

### Compose type

You can also use `compose.Compose(fns)` to name the type explicitly:

```zig
const compose = @import("zfp").compose;

const MyFn = compose.Compose(.{ double, addOne });
// MyFn.call(3) == 7
```

---

## Type Inference

Types flow left to right at compile time. Each step's return type becomes the next step's input:

```zig
// i32 → i32 → bool
const check = compose.from(.{ double, isPositive });
const ok: bool = check.call(3); // true  (3 → 6 → true)
const no: bool = check.call(0); // false (0 → 0 → false)
```

---

## Examples

### Basic composition

```zig
const compose = @import("zfp").compose;

fn double(x: i32) i32  { return x * 2; }
fn addOne(x: i32) i32  { return x + 1; }
fn negate(x: i32) i32  { return -x; }

const f = compose.from(.{ double, addOne, negate });
// f.call(3) → double(3)=6 → addOne(6)=7 → negate(7)=-7
```

### Type-changing composition

```zig
const compose = @import("zfp").compose;

fn length(s: []const u8) usize { return s.len; }
fn doubled(n: usize) usize     { return n * 2; }

const f = compose.from(.{ length, doubled });
// f.call("hello") → 5 → 10   (type: usize)
// f.call("hi")    → 2 → 4
```

### Batch processing

```zig
const compose = @import("zfp").compose;
const std = @import("std");

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " ");
}
fn toUpperFirst(s: []const u8) u8 {
    return if (s.len > 0) std.ascii.toUpper(s[0]) else 0;
}

const firstChar = compose.from(.{ trim, toUpperFirst });

const inputs = [_][]const u8{ "  hello", " world ", "zig " };
for (inputs) |input| {
    const c = firstChar.call(input);
    // 'H', 'W', 'Z'
    _ = c;
}
```

---

## Zero Cost

`Compose` returns a struct with **no fields**. It is zero-size. `call` inlines directly into:

```zig
negate(addOne(double(x)))
```

No heap allocation. No indirection. No runtime cost.
The struct exists only as a compile-time namespace for the `call` function.

---

## When to Use compose vs. pipe

| Use case | Tool |
|----------|------|
| One-off transformation | `pipe` |
| Reused at multiple call sites | `compose` |
| Named abstraction for readability | `compose` |
| Passed as a value to another function | `compose` (use `.call`) |
| Applied inside a loop | `compose` (define outside the loop) |
