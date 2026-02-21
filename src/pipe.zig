//! pipe.zig — Zero-cost function pipeline for Zig.
//!
//! Apply a sequence of functions to a value from left to right.
//! No allocations, no closures, no runtime overhead.
//! Types flow through the pipeline entirely at compile time.

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

/// Compute the output type after applying all functions in `Fns` starting from `idx`.
/// Recursively threads the type through each function's return type.
fn PipeReturn(comptime idx: usize, comptime T: type, comptime Fns: type) type {
    const fields = @typeInfo(Fns).@"struct".fields;
    if (idx >= fields.len) return T;
    return PipeReturn(idx + 1, FnReturn(fields[idx].type), Fns);
}

/// Recursively apply functions in `fns` from `idx` onward.
/// Each call is a distinct instantiation (different comptime `idx` and `value` type),
/// so the compiler specialises and optimises each step independently.
fn applyFrom(comptime idx: usize, value: anytype, fns: anytype) PipeReturn(idx, @TypeOf(value), @TypeOf(fns)) {
    const fields = @typeInfo(@TypeOf(fns)).@"struct".fields;
    if (comptime idx >= fields.len) return value;
    return applyFrom(idx + 1, fns[idx](value), fns);
}

// ─── Public API ───────────────────────────────────────────────────────────────

/// Apply a sequence of functions to a value, left to right.
///
///   pipe(x, .{ f, g, h }) ≡ h(g(f(x)))
///
/// Types flow through the pipeline:
///
///   pipe(x: A, .{ f: A→B, g: B→C, h: C→D }) → D
///
/// An empty function list is the identity:
///
///   pipe(x, .{}) ≡ x
///
/// **Zero-cost**: the tuple is a comptime construct. Each function application
/// is resolved at compile time; the generated code is identical to a
/// hand-written `h(g(f(x)))`.
pub inline fn pipe(value: anytype, fns: anytype) PipeReturn(0, @TypeOf(value), @TypeOf(fns)) {
    return applyFrom(0, value, fns);
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

// pipe ─────────────────────────────────────────────────────────────────────────

test "pipe: identity — empty function list" {
    try testing.expectEqual(@as(i32, 42), pipe(@as(i32, 42), .{}));
}

test "pipe: single function" {
    // 3 → 6
    try testing.expectEqual(@as(i32, 6), pipe(@as(i32, 3), .{double}));
}

test "pipe: two functions" {
    // 3 → 6 → 7
    try testing.expectEqual(@as(i32, 7), pipe(@as(i32, 3), .{ double, addOne }));
}

test "pipe: three functions" {
    // 3 → 6 → 7 → -7
    try testing.expectEqual(@as(i32, -7), pipe(@as(i32, 3), .{ double, addOne, negate }));
}

test "pipe: type changes across steps" {
    // i32 → i32 → bool
    try testing.expect(pipe(@as(i32, 3), .{ double, isPositive }));
    try testing.expect(!pipe(@as(i32, 0), .{ negate, isPositive }));
}

test "pipe: string → length → doubled" {
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
    // "hello" → 5 → 10
    try testing.expectEqual(@as(usize, 10), pipe(@as([]const u8, "hello"), .{ length, doubleUsize }));
}

test "pipe: order is left to right" {
    // Verify left-to-right: double then negate ≠ negate then double (for non-zero)
    // 3 → 6 → -6
    try testing.expectEqual(@as(i32, -6), pipe(@as(i32, 3), .{ double, negate }));
    // 3 → -3 → -6
    try testing.expectEqual(@as(i32, -6), pipe(@as(i32, 3), .{ negate, double }));
    // Both -6 here, use a value where order matters
    // 3 → 6 → 7 (double then addOne)
    try testing.expectEqual(@as(i32, 7), pipe(@as(i32, 3), .{ double, addOne }));
    // 3 → 4 → 8 (addOne then double)
    try testing.expectEqual(@as(i32, 8), pipe(@as(i32, 3), .{ addOne, double }));
}

// ─── Usage example ────────────────────────────────────────────────────────────
//
// Before (nested calls, read right to left):
//
//   const result = normalize(clamp(parse(raw)));
//
// After (pipe, read left to right):
//
//   const result = pipe.pipe(raw, .{ parse, clamp, normalize });
//
// Both produce identical machine code.
// The pipeline grows naturally: add a step by appending to the tuple.
