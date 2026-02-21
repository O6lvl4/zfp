//! func.zig — Zero-cost function combinators for Zig.
//!
//! Primitive building blocks for composing and transforming functions.
//! Inspired by Haskell's Prelude: id, flip, const, on.
//!
//! Design philosophy:
//!   - No allocations, no closures, no runtime overhead.
//!   - All functions are `inline`; the compiler folds them into the call site.
//!   - Named `func` (not `fn`) because `fn` is a reserved keyword in Zig.

// ─── Public API ───────────────────────────────────────────────────────────────

/// Identity function. Returns its argument unchanged.
///
///   id :: a -> a
///   id(x) ≡ x
///
/// **Zero-cost**: compiles away completely; the value is forwarded as-is.
pub inline fn id(x: anytype) @TypeOf(x) {
    return x;
}

/// Flip the first two arguments of a binary function.
///
///   flip :: (a -> b -> c) -> b -> a -> c
///   flip(f, a, b) ≡ f(b, a)
///
/// Useful when argument order doesn't match what a pipeline expects.
///
/// **Zero-cost**: a single call with swapped arguments.
pub inline fn flip(f: anytype, a: anytype, b: anytype) @TypeOf(f(b, a)) {
    return f(b, a);
}

/// Constant function. Returns the first argument, ignoring the second.
///
///   const :: a -> b -> a
///   const_(x, _) ≡ x
///
/// Named `const_` because `const` is a reserved keyword in Zig.
///
/// **Zero-cost**: the second argument is discarded at compile time.
pub inline fn const_(x: anytype, _: anytype) @TypeOf(x) {
    return x;
}

/// Apply a binary function after mapping both arguments through a unary function.
///
///   on :: (b -> b -> c) -> (a -> b) -> a -> a -> c
///   on(f, g, a, b) ≡ f(g(a), g(b))
///
/// Example: compare two values by a derived key.
///
///   on(std.math.order, getLength, "foo", "hello")
///   ≡ std.math.order(getLength("foo"), getLength("hello"))
///   ≡ .lt
///
/// **Zero-cost**: two applications of `g` followed by one application of `f`.
pub inline fn on(f: anytype, g: anytype, a: anytype, b: anytype) @TypeOf(f(g(a), g(b))) {
    return f(g(a), g(b));
}

// ─── Tests ────────────────────────────────────────────────────────────────────

const testing = @import("std").testing;

// id ───────────────────────────────────────────────────────────────────────────

test "id: returns integer unchanged" {
    try testing.expectEqual(@as(i32, 42), id(@as(i32, 42)));
}

test "id: returns bool unchanged" {
    try testing.expect(id(true));
}

test "id: returns slice unchanged" {
    const s = "hello";
    try testing.expectEqualStrings(s, id(s));
}

// flip ─────────────────────────────────────────────────────────────────────────

test "flip: swaps arguments for subtraction" {
    const sub = struct {
        fn call(a: i32, b: i32) i32 {
            return a - b;
        }
    }.call;

    // sub(10, 3) = 7, flip(sub, 10, 3) = sub(3, 10) = -7
    try testing.expectEqual(@as(i32, 7), sub(10, 3));
    try testing.expectEqual(@as(i32, -7), flip(sub, 10, 3));
}

test "flip: swaps arguments for string comparison" {
    const std = @import("std");
    const startsWith = struct {
        fn call(haystack: []const u8, prefix: []const u8) bool {
            return std.mem.startsWith(u8, haystack, prefix);
        }
    }.call;

    try testing.expect(startsWith("hello world", "hello"));
    // flip: now prefix comes first, haystack second
    try testing.expect(!flip(startsWith, "hello world", "hello"));
    try testing.expect(flip(startsWith, "hello", "hello world"));
}

// const_ ──────────────────────────────────────────────────────────────────────

test "const_: returns first argument regardless of second" {
    try testing.expectEqual(@as(i32, 42), const_(@as(i32, 42), "ignored"));
    try testing.expectEqual(@as(i32, 42), const_(@as(i32, 42), 9999));
    try testing.expectEqual(true, const_(true, false));
}

test "const_: works as a fixed-value function in a pipeline" {
    const pipe = @import("pipe.zig");

    const double = struct {
        fn call(x: i32) i32 {
            return x * 2;
        }
    }.call;
    const alwaysZero = struct {
        fn call(x: i32) i32 {
            return const_(@as(i32, 0), x);
        }
    }.call;

    // 3 → 6 → 0
    try testing.expectEqual(@as(i32, 0), pipe.run(@as(i32, 3), .{ double, alwaysZero }));
}

// on ───────────────────────────────────────────────────────────────────────────

test "on: compares lengths of two strings" {
    const std = @import("std");

    const orderInts = struct {
        fn call(a: usize, b: usize) std.math.Order {
            return std.math.order(a, b);
        }
    }.call;
    const length = struct {
        fn call(s: []const u8) usize {
            return s.len;
        }
    }.call;

    // "foo".len=3 vs "hello".len=5 → .lt
    try testing.expectEqual(std.math.Order.lt, on(orderInts, length, "foo", "hello"));
    // "hi".len=2 vs "hi".len=2 → .eq
    try testing.expectEqual(std.math.Order.eq, on(orderInts, length, "hi", "ok"));
}

test "on: doubles both then adds" {
    const add = struct {
        fn call(a: i32, b: i32) i32 {
            return a + b;
        }
    }.call;
    const double = struct {
        fn call(x: i32) i32 {
            return x * 2;
        }
    }.call;

    // on(add, double, 3, 4) = add(double(3), double(4)) = add(6, 8) = 14
    try testing.expectEqual(@as(i32, 14), on(add, double, 3, 4));
}
