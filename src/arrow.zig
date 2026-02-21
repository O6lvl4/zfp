//! arrow.zig — Zero-cost Arrow combinators for Zig.
//!
//! Combinators for working with pairs (two-element tuples), inspired by
//! Haskell's Arrow typeclass. All functions operate on Zig's native
//! anonymous struct tuples: `.{ a, b }`.
//!
//! Core operations:
//!   first(f, pair)      — apply f to the first element;  second unchanged
//!   second(g, pair)     — apply g to the second element; first unchanged
//!   split(f, g, pair)   — f *** g: apply f to first, g to second
//!   fanout(f, g, value) — f &&& g: apply both f and g to the same value

// ─── Public API ───────────────────────────────────────────────────────────────

/// Apply `f` to the first element of a pair, leaving the second unchanged.
///
///   first(f, .{a, b})  ≡  .{f(a), b}
///
/// Haskell: `first :: Arrow a => a b c -> a (b, d) (c, d)`
/// For plain functions: `first f (a, b) = (f a, b)`
///
/// **Zero-cost**: compiles to a single call followed by a tuple construction.
pub inline fn first(f: anytype, pair: anytype) @TypeOf(.{ f(pair[0]), pair[1] }) {
    return .{ f(pair[0]), pair[1] };
}

/// Apply `g` to the second element of a pair, leaving the first unchanged.
///
///   second(g, .{a, b})  ≡  .{a, g(b)}
///
/// Haskell: `second :: Arrow a => a b c -> a (d, b) (d, c)`
/// For plain functions: `second g (a, b) = (a, g b)`
///
/// **Zero-cost**: compiles to a single call followed by a tuple construction.
pub inline fn second(g: anytype, pair: anytype) @TypeOf(.{ pair[0], g(pair[1]) }) {
    return .{ pair[0], g(pair[1]) };
}

/// Apply `f` to the first element and `g` to the second element of a pair.
///
///   split(f, g, .{a, b})  ≡  .{f(a), g(b)}
///
/// Haskell: `(***)  :: Arrow a => a b c -> a b' c' -> a (b, b') (c, c')`
/// For plain functions: `(f *** g) (a, b) = (f a, g b)`
///
/// **Zero-cost**: two calls followed by a tuple construction.
pub inline fn split(f: anytype, g: anytype, pair: anytype) @TypeOf(.{ f(pair[0]), g(pair[1]) }) {
    return .{ f(pair[0]), g(pair[1]) };
}

/// Apply both `f` and `g` to the same value, returning a pair of results.
///
///   fanout(f, g, a)  ≡  .{f(a), g(a)}
///
/// Haskell: `(&&&) :: Arrow a => a b c -> a b c' -> a b (c, c')`
/// For plain functions: `(f &&& g) a = (f a, g a)`
///
/// **Zero-cost**: two calls followed by a tuple construction.
pub inline fn fanout(f: anytype, g: anytype, value: anytype) @TypeOf(.{ f(value), g(value) }) {
    return .{ f(value), g(value) };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

const testing = @import("std").testing;

const double = struct {
    fn call(x: i32) i32 {
        return x * 2;
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

const addOne = struct {
    fn call(x: i32) i32 {
        return x + 1;
    }
}.call;

// first ────────────────────────────────────────────────────────────────────────

test "first: applies f to first element" {
    const result = first(double, .{ @as(i32, 3), @as(i32, 4) });
    try testing.expectEqual(@as(i32, 6), result[0]);
    try testing.expectEqual(@as(i32, 4), result[1]);
}

test "first: second element is unchanged" {
    const result = first(negate, .{ @as(i32, 5), @as(i32, 99) });
    try testing.expectEqual(@as(i32, -5), result[0]);
    try testing.expectEqual(@as(i32, 99), result[1]);
}

test "first: first element type can change" {
    // i32 → bool in first position, i32 unchanged in second
    const result = first(isPositive, .{ @as(i32, 3), @as(i32, 7) });
    try testing.expect(result[0]); // bool
    try testing.expectEqual(@as(i32, 7), result[1]); // i32 unchanged
}

// second ───────────────────────────────────────────────────────────────────────

test "second: applies g to second element" {
    const result = second(double, .{ @as(i32, 4), @as(i32, 3) });
    try testing.expectEqual(@as(i32, 4), result[0]);
    try testing.expectEqual(@as(i32, 6), result[1]);
}

test "second: first element is unchanged" {
    const result = second(negate, .{ @as(i32, 99), @as(i32, 5) });
    try testing.expectEqual(@as(i32, 99), result[0]);
    try testing.expectEqual(@as(i32, -5), result[1]);
}

test "second: second element type can change" {
    const result = second(isPositive, .{ @as(i32, 7), @as(i32, 3) });
    try testing.expectEqual(@as(i32, 7), result[0]); // i32 unchanged
    try testing.expect(result[1]); // bool
}

// split ────────────────────────────────────────────────────────────────────────

test "split: applies f to first, g to second" {
    const result = split(double, negate, .{ @as(i32, 3), @as(i32, 4) });
    try testing.expectEqual(@as(i32, 6), result[0]); // double(3)
    try testing.expectEqual(@as(i32, -4), result[1]); // negate(4)
}

test "split: both element types can change independently" {
    const result = split(isPositive, double, .{ @as(i32, 5), @as(i32, 3) });
    try testing.expect(result[0]); // isPositive(5) → bool
    try testing.expectEqual(@as(i32, 6), result[1]); // double(3) → i32
}

test "split: same function applied to both" {
    // split(f, f, pair) is equivalent to applying f independently to each element
    const result = split(double, double, .{ @as(i32, 3), @as(i32, 5) });
    try testing.expectEqual(@as(i32, 6), result[0]);
    try testing.expectEqual(@as(i32, 10), result[1]);
}

// fanout ───────────────────────────────────────────────────────────────────────

test "fanout: applies both functions to the same value" {
    const result = fanout(double, negate, @as(i32, 5));
    try testing.expectEqual(@as(i32, 10), result[0]); // double(5)
    try testing.expectEqual(@as(i32, -5), result[1]); // negate(5)
}

test "fanout: output types can differ" {
    const result = fanout(double, isPositive, @as(i32, 3));
    try testing.expectEqual(@as(i32, 6), result[0]); // i32
    try testing.expect(result[1]); // bool
}

test "fanout: same function produces equal results" {
    const result = fanout(double, double, @as(i32, 7));
    try testing.expectEqual(result[0], result[1]);
}

// composition ──────────────────────────────────────────────────────────────────

test "split composed with fanout" {
    // fanout produces a pair, then split transforms each element
    const pair = fanout(double, addOne, @as(i32, 3)); // .{6, 4}
    const result = split(negate, isPositive, pair); // .{-6, true}
    try testing.expectEqual(@as(i32, -6), result[0]);
    try testing.expect(result[1]);
}

test "first and second chained" {
    // Apply transformations to each side independently
    const step1 = first(double, .{ @as(i32, 3), @as(i32, 5) }); // .{6, 5}
    const step2 = second(negate, step1); // .{6, -5}
    try testing.expectEqual(@as(i32, 6), step2[0]);
    try testing.expectEqual(@as(i32, -5), step2[1]);
}
