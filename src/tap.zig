//! tap.zig — Zero-cost side-effect injection for Zig pipelines.
//!
//! Apply a function for its side effects (logging, tracing, assertions)
//! without interrupting the value flowing through a pipeline.
//!
//! Two forms:
//!   tap.run(value, f)       — direct use; returns value unchanged
//!   tap.typed(T, f)         — pipeline step with explicit type; usable in pipe.run tuples

// ─── Internal helper ──────────────────────────────────────────────────────────

/// Call f(value), discarding the return value regardless of its type.
inline fn effect(value: anytype, comptime f: anytype) void {
    const R = @TypeOf(f(value));
    if (R == void) {
        f(value);
    } else {
        _ = f(value);
    }
}

// ─── Public API ───────────────────────────────────────────────────────────────

/// Call `f(value)` for its side effect, then return `value` unchanged.
///
///   tap.run(x, f)  ≡  f(x); x
///
/// `f`'s return value is discarded; only the side effect matters.
///
/// **Zero-cost**: inlines to a single call followed by the original value.
pub inline fn run(value: anytype, comptime f: anytype) @TypeOf(value) {
    effect(value, f);
    return value;
}

/// Return a concrete `fn(T) T` step for use inside `pipe.run` tuples.
///
///   pipe.run(value, .{
///       parse,
///       tap.typed(ParsedData, logFn),  // side effect; value passes through
///       validate,
///   });
///
/// The type `T` must be specified explicitly because `pipe.run` resolves
/// return types at comptime and requires a concrete function signature.
///
/// **Zero-cost**: the returned function inlines to `f(value); value`.
pub fn typed(comptime T: type, comptime f: anytype) fn (T) T {
    return struct {
        fn call(value: T) T {
            effect(value, f);
            return value;
        }
    }.call;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

const testing = @import("std").testing;

// tap.run ──────────────────────────────────────────────────────────────────────

test "run: returns value unchanged" {
    const noop = struct {
        fn call(_: i32) void {}
    }.call;

    try testing.expectEqual(@as(i32, 42), run(@as(i32, 42), noop));
}

test "run: calls f with the value" {
    var seen: i32 = 0;
    const capture = struct {
        var ptr: *i32 = undefined;
        fn call(x: i32) void {
            ptr.* = x;
        }
    };
    capture.ptr = &seen;

    _ = run(@as(i32, 99), capture.call);
    try testing.expectEqual(@as(i32, 99), seen);
}

test "run: discards non-void return from f" {
    const returnsValue = struct {
        fn call(x: i32) i32 {
            return x * 2;
        }
    }.call;

    // original value is returned, not f's return value
    try testing.expectEqual(@as(i32, 5), run(@as(i32, 5), returnsValue));
}

test "run: works with slices" {
    const noop = struct {
        fn call(_: []const u8) void {}
    }.call;

    try testing.expectEqualStrings("hello", run("hello", noop));
}

// tap.typed ────────────────────────────────────────────────────────────────────

test "typed: returns value unchanged" {
    const noop = struct {
        fn call(_: i32) void {}
    }.call;

    try testing.expectEqual(@as(i32, 42), typed(i32, noop)(@as(i32, 42)));
}

test "typed: calls f with the value" {
    var seen: i32 = 0;
    const capture = struct {
        var ptr: *i32 = undefined;
        fn call(x: i32) void {
            ptr.* = x;
        }
    };
    capture.ptr = &seen;

    _ = typed(i32, capture.call)(@as(i32, 77));
    try testing.expectEqual(@as(i32, 77), seen);
}

test "typed: usable inside pipe.run" {
    const pipe = @import("pipe.zig");

    var seen: i32 = 0;
    const capture = struct {
        var ptr: *i32 = undefined;
        fn call(x: i32) void {
            ptr.* = x;
        }
    };
    capture.ptr = &seen;

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

    // 3 → 6 → [tap: seen=6] → 7
    const result = pipe.run(@as(i32, 3), .{
        double,
        typed(i32, capture.call),
        addOne,
    });

    try testing.expectEqual(@as(i32, 7), result); // value flows through correctly
    try testing.expectEqual(@as(i32, 6), seen); // f was called with mid-pipeline value
}
