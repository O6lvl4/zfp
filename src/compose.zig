//! compose.zig — Higher-order function composition for Zig.
//!
//! Returns a reusable callable by composing a sequence of functions, left to right.
//! Unlike `pipe`, which applies functions to a value immediately,
//! `compose` produces a zero-size struct you can call, store, and pass around.
//!
//!   const f = compose(.{ g, h });
//!   f.call(x)  ≡  h(g(x))    — reusable, named, zero-cost

// ─── Internal helpers ─────────────────────────────────────────────────────────

/// Get the return type of a function or function-pointer type.
fn FnReturn(comptime F: type) type {
    return switch (@typeInfo(F)) {
        .@"fn" => |info| info.return_type orelse
            @compileError("Function must declare an explicit return type"),
        .pointer => |ptr| switch (@typeInfo(ptr.child)) {
            .@"fn" => |info| info.return_type orelse
                @compileError("Function must declare an explicit return type"),
            else => @compileError(
                "Expected a function or function pointer, got: " ++ @typeName(F),
            ),
        },
        else => @compileError(
            "Expected a function type, got: " ++ @typeName(F),
        ),
    };
}

/// Get the type of the first parameter of a function or function-pointer type.
fn FnParam(comptime F: type) type {
    const params = switch (@typeInfo(F)) {
        .@"fn" => |info| info.params,
        .pointer => |ptr| switch (@typeInfo(ptr.child)) {
            .@"fn" => |info| info.params,
            else => @compileError(
                "Expected a function or function pointer, got: " ++ @typeName(F),
            ),
        },
        else => @compileError(
            "Expected a function type, got: " ++ @typeName(F),
        ),
    };
    if (params.len == 0) @compileError("Function must have at least one parameter");
    return params[0].type orelse
        @compileError("Function parameter must have an explicit type");
}

/// Compute the output type after applying all functions in `Fns` starting from `idx`.
fn PipeReturn(comptime idx: usize, comptime T: type, comptime Fns: type) type {
    const fields = @typeInfo(Fns).@"struct".fields;
    if (idx >= fields.len) return T;
    return PipeReturn(idx + 1, FnReturn(fields[idx].type), Fns);
}

/// Recursively apply functions in `fns` from `idx` onward.
fn applyFrom(comptime idx: usize, value: anytype, fns: anytype) PipeReturn(idx, @TypeOf(value), @TypeOf(fns)) {
    const fields = @typeInfo(@TypeOf(fns)).@"struct".fields;
    if (comptime idx >= fields.len) return value;
    return applyFrom(idx + 1, fns[idx](value), fns);
}

// ─── Public API ───────────────────────────────────────────────────────────────

/// The type returned by `compose`. A zero-size struct with a single `call` method.
///
/// Use `compose(fns)` instead of constructing this directly.
pub fn Compose(comptime fns: anytype) type {
    const Fns = @TypeOf(fns);
    const fields = @typeInfo(Fns).@"struct".fields;
    if (fields.len == 0) @compileError("compose requires at least one function");

    const In = FnParam(fields[0].type);
    const Out = PipeReturn(0, In, Fns);

    return struct {
        /// Apply the composed function to `value`.
        pub inline fn call(self: @This(), value: In) Out {
            _ = self;
            return applyFrom(0, value, fns);
        }
    };
}

/// Compose a sequence of functions into a reusable callable, applied left to right.
///
///   from(.{ f, g, h }).call(x)  ≡  h(g(f(x)))
///
/// **Reusable**: unlike `pipe`, the result can be stored, named, and called many times.
///
///   const process = from(.{ trim, parse, validate });
///   const a = process.call(input_a);
///   const b = process.call(input_b);
///
/// **Types flow through the pipeline**:
///
///   from(.{ f: A→B, g: B→C }).call(x: A) → C
///
/// **Zero-cost**: the struct has no fields. `call` inlines to the same code as
/// a hand-written `h(g(f(x)))`.
pub inline fn from(comptime fns: anytype) Compose(fns) {
    return .{};
}

// ─── Tests ────────────────────────────────────────────────────────────────────

const testing = @import("std").testing;

const double = struct {
    fn call(x: i32) i32 {
        return x * 2;
    }
}.call;

const addOne = struct {
    fn call(x: i32) i32 {
        return x + 1;
    }
}.call;

const negate = struct {
    fn call(x: i32) i32 {
        return -x;
    }
}.call;

const isPositive = struct {
    fn call(x: i32) bool {
        return x > 0;
    }
}.call;

// compose ──────────────────────────────────────────────────────────────────────

test "compose: single function" {
    // 3 → 6
    const f = from(.{double});
    try testing.expectEqual(@as(i32, 6), f.call(3));
}

test "compose: two functions" {
    // 3 → 6 → 7
    const f = from(.{ double, addOne });
    try testing.expectEqual(@as(i32, 7), f.call(3));
}

test "compose: three functions" {
    // 3 → 6 → 7 → -7
    const f = from(.{ double, addOne, negate });
    try testing.expectEqual(@as(i32, -7), f.call(3));
}

test "compose: type changes across steps" {
    // i32 → i32 → bool
    const f = from(.{ double, isPositive });
    try testing.expect(f.call(3));
    try testing.expect(!f.call(0));
}

test "compose: reusable across multiple inputs" {
    const f = from(.{ double, addOne });
    // Apply to several values independently
    try testing.expectEqual(@as(i32, 7), f.call(3)); // 3 → 6 → 7
    try testing.expectEqual(@as(i32, 9), f.call(4)); // 4 → 8 → 9
    try testing.expectEqual(@as(i32, 3), f.call(1)); // 1 → 2 → 3
}

test "compose: order is left to right" {
    // double then addOne ≠ addOne then double
    const double_then_add = from(.{ double, addOne });
    const add_then_double = from(.{ addOne, double });
    try testing.expectEqual(@as(i32, 7), double_then_add.call(3)); // 3 → 6 → 7
    try testing.expectEqual(@as(i32, 8), add_then_double.call(3)); // 3 → 4 → 8
}

test "compose: string → length → doubled" {
    const length = struct {
        fn call(s: []const u8) usize {
            return s.len;
        }
    }.call;
    const doubleUsize = struct {
        fn call(n: usize) usize {
            return n * 2;
        }
    }.call;

    const f = from(.{ length, doubleUsize });
    // "hello" → 5 → 10
    try testing.expectEqual(@as(usize, 10), f.call("hello"));
    // "hi" → 2 → 4
    try testing.expectEqual(@as(usize, 4), f.call("hi"));
}

// ─── Usage example ────────────────────────────────────────────────────────────
//
// Define a named transformation once, apply many times:
//
//   const normalise = compose.from(.{ trim, parse, clamp });
//
//   const a = normalise.call(raw_a);
//   const b = normalise.call(raw_b);
//
// Compared to pipe (single-use, applied immediately):
//
//   const a = pipe.run(raw_a, .{ trim, parse, clamp });
//   const b = pipe.run(raw_b, .{ trim, parse, clamp });  // tuple repeated
//
// Both produce identical machine code.
