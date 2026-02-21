//! slice.zig — Zero-cost Foldable operations over Zig slices.
//!
//! All functions operate on Zig's native slice type ([]T or []const T).
//! No allocations, no boxing, no runtime overhead.
//! Each function compiles to the equivalent hand-written for loop.
//!
//! Core operations:
//!   fold(items, init, f)         — left fold (the fundamental operation)
//!   all(items, predicate)        — true if predicate holds for all items
//!   any(items, predicate)        — true if predicate holds for any item
//!   find(items, predicate)       — first matching item as ?T
//!   findIndex(items, predicate)  — index of first match as ?usize
//!   count(items, predicate)      — number of matching items
//!   forEach(items, f)            — apply f to each item for side effects
//!   sum(items)                   — sum of all numeric items
//!   min(items)                   — smallest item, or null for empty slice
//!   max(items)                   — largest item, or null for empty slice

const std = @import("std");

// ─── Internal helper ──────────────────────────────────────────────────────────

/// Extract the element type from a slice, array, or pointer-to-array.
fn Elem(comptime S: type) type {
    return std.meta.Elem(S);
}

// ─── Public API ───────────────────────────────────────────────────────────────

/// Left fold over a slice.
///
///   fold([a, b, c], init, f)  ≡  f(f(f(init, a), b), c)
///
/// Haskell: `foldl :: (b -> a -> b) -> b -> [a] -> b`
///
/// The fundamental operation — all other combinators can be expressed as folds.
///
/// **Zero-cost**: compiles to a plain accumulating for loop.
pub inline fn fold(items: anytype, init: anytype, f: anytype) @TypeOf(init) {
    var acc = init;
    for (items) |item| acc = f(acc, item);
    return acc;
}

/// Return `true` if `predicate` holds for every item.
/// Vacuously `true` for an empty slice.
///
/// Haskell: `all :: Foldable t => (a -> Bool) -> t a -> Bool`
///
/// **Zero-cost**: short-circuits on the first `false`.
pub inline fn all(items: anytype, predicate: anytype) bool {
    for (items) |item| {
        if (!predicate(item)) return false;
    }
    return true;
}

/// Return `true` if `predicate` holds for at least one item.
/// `false` for an empty slice.
///
/// Haskell: `any :: Foldable t => (a -> Bool) -> t a -> Bool`
///
/// **Zero-cost**: short-circuits on the first `true`.
pub inline fn any(items: anytype, predicate: anytype) bool {
    for (items) |item| {
        if (predicate(item)) return true;
    }
    return false;
}

/// Return the first item for which `predicate` returns `true`, or `null`.
///
/// Haskell: `find :: Foldable t => (a -> Bool) -> t a -> Maybe a`
///
/// **Zero-cost**: short-circuits on the first match.
pub inline fn find(items: anytype, predicate: anytype) ?Elem(@TypeOf(items)) {
    for (items) |item| {
        if (predicate(item)) return item;
    }
    return null;
}

/// Return the index of the first item for which `predicate` returns `true`,
/// or `null` if no item matches.
///
/// **Zero-cost**: short-circuits on the first match.
pub inline fn findIndex(items: anytype, predicate: anytype) ?usize {
    for (items, 0..) |item, i| {
        if (predicate(item)) return i;
    }
    return null;
}

/// Return the number of items for which `predicate` returns `true`.
///
/// Haskell: `length . filter p`
///
/// **Zero-cost**: a single pass with a counter.
pub inline fn count(items: anytype, predicate: anytype) usize {
    var n: usize = 0;
    for (items) |item| {
        if (predicate(item)) n += 1;
    }
    return n;
}

/// Call `f` on each item for its side effect; returns nothing.
///
/// Haskell: `traverse_ :: (Foldable t, Applicative f) => (a -> f b) -> t a -> f ()`
///
/// **Zero-cost**: a plain for loop.
pub inline fn forEach(items: anytype, f: anytype) void {
    for (items) |item| f(item);
}

/// Return the sum of all items. Returns `0` for an empty slice.
///
/// Haskell: `sum :: (Foldable t, Num a) => t a -> a`
///
/// **Zero-cost**: a single accumulating for loop.
pub inline fn sum(items: anytype) Elem(@TypeOf(items)) {
    var total: Elem(@TypeOf(items)) = 0;
    for (items) |item| total += item;
    return total;
}

/// Return the smallest item, or `null` for an empty slice.
///
/// Haskell: `minimum :: (Foldable t, Ord a) => t a -> a`
///
/// **Zero-cost**: a single-pass linear scan.
pub inline fn min(items: anytype) ?Elem(@TypeOf(items)) {
    if (items.len == 0) return null;
    var result = items[0];
    for (items[1..]) |item| {
        if (item < result) result = item;
    }
    return result;
}

/// Return the largest item, or `null` for an empty slice.
///
/// Haskell: `maximum :: (Foldable t, Ord a) => t a -> a`
///
/// **Zero-cost**: a single-pass linear scan.
pub inline fn max(items: anytype) ?Elem(@TypeOf(items)) {
    if (items.len == 0) return null;
    var result = items[0];
    for (items[1..]) |item| {
        if (item > result) result = item;
    }
    return result;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

const testing = @import("std").testing;

const isPositive = struct {
    fn call(x: i32) bool {
        return x > 0;
    }
}.call;

const isEven = struct {
    fn call(x: i32) bool {
        return @rem(x, 2) == 0;
    }
}.call;

const double = struct {
    fn call(acc: i32, x: i32) i32 {
        return acc + x * 2;
    }
}.call;

// fold ─────────────────────────────────────────────────────────────────────────

test "fold: sum via fold" {
    const items = [_]i32{ 1, 2, 3, 4 };
    const result = fold(&items, @as(i32, 0), struct {
        fn call(acc: i32, x: i32) i32 {
            return acc + x;
        }
    }.call);
    try testing.expectEqual(@as(i32, 10), result);
}

test "fold: product via fold" {
    const items = [_]i32{ 1, 2, 3, 4 };
    const result = fold(&items, @as(i32, 1), struct {
        fn call(acc: i32, x: i32) i32 {
            return acc * x;
        }
    }.call);
    try testing.expectEqual(@as(i32, 24), result);
}

test "fold: empty slice returns init" {
    const items = [_]i32{};
    const result = fold(&items, @as(i32, 42), struct {
        fn call(acc: i32, x: i32) i32 {
            return acc + x;
        }
    }.call);
    try testing.expectEqual(@as(i32, 42), result);
}

test "fold: accumulate strings via count" {
    const items = [_]i32{ 1, -2, 3, -4, 5 };
    const n = fold(&items, @as(usize, 0), struct {
        fn call(acc: usize, x: i32) usize {
            return acc + if (x > 0) @as(usize, 1) else 0;
        }
    }.call);
    try testing.expectEqual(@as(usize, 3), n);
}

// all ──────────────────────────────────────────────────────────────────────────

test "all: true when all match" {
    const items = [_]i32{ 1, 2, 3 };
    try testing.expect(all(&items, isPositive));
}

test "all: false when one does not match" {
    const items = [_]i32{ 1, -2, 3 };
    try testing.expect(!all(&items, isPositive));
}

test "all: vacuously true for empty slice" {
    const items = [_]i32{};
    try testing.expect(all(&items, isPositive));
}

// any ──────────────────────────────────────────────────────────────────────────

test "any: true when one matches" {
    const items = [_]i32{ -1, 2, -3 };
    try testing.expect(any(&items, isPositive));
}

test "any: false when none match" {
    const items = [_]i32{ -1, -2, -3 };
    try testing.expect(!any(&items, isPositive));
}

test "any: false for empty slice" {
    const items = [_]i32{};
    try testing.expect(!any(&items, isPositive));
}

// find ─────────────────────────────────────────────────────────────────────────

test "find: returns first match" {
    const items = [_]i32{ -1, -2, 3, 4 };
    try testing.expectEqual(@as(?i32, 3), find(&items, isPositive));
}

test "find: returns null when no match" {
    const items = [_]i32{ -1, -2, -3 };
    try testing.expectEqual(@as(?i32, null), find(&items, isPositive));
}

test "find: returns first of multiple matches" {
    const items = [_]i32{ -1, 2, 3 };
    try testing.expectEqual(@as(?i32, 2), find(&items, isPositive));
}

// findIndex ────────────────────────────────────────────────────────────────────

test "findIndex: returns index of first match" {
    const items = [_]i32{ -1, -2, 3, 4 };
    try testing.expectEqual(@as(?usize, 2), findIndex(&items, isPositive));
}

test "findIndex: returns null when no match" {
    const items = [_]i32{ -1, -2, -3 };
    try testing.expectEqual(@as(?usize, null), findIndex(&items, isPositive));
}

test "findIndex: returns 0 when first element matches" {
    const items = [_]i32{ 5, -1, -2 };
    try testing.expectEqual(@as(?usize, 0), findIndex(&items, isPositive));
}

// count ────────────────────────────────────────────────────────────────────────

test "count: counts matching items" {
    const items = [_]i32{ 1, -2, 3, -4, 5 };
    try testing.expectEqual(@as(usize, 3), count(&items, isPositive));
}

test "count: zero when none match" {
    const items = [_]i32{ -1, -2, -3 };
    try testing.expectEqual(@as(usize, 0), count(&items, isPositive));
}

test "count: all when all match" {
    const items = [_]i32{ 1, 2, 3 };
    try testing.expectEqual(@as(usize, 3), count(&items, isPositive));
}

test "count: zero for empty slice" {
    const items = [_]i32{};
    try testing.expectEqual(@as(usize, 0), count(&items, isPositive));
}

// forEach ──────────────────────────────────────────────────────────────────────

test "forEach: calls f for each item" {
    const items = [_]i32{ 1, 2, 3 };
    var total: i32 = 0;
    const add = struct {
        var ptr: *i32 = undefined;
        fn call(x: i32) void {
            ptr.* += x;
        }
    };
    add.ptr = &total;
    forEach(&items, add.call);
    try testing.expectEqual(@as(i32, 6), total);
}

test "forEach: does nothing for empty slice" {
    const items = [_]i32{};
    var called = false;
    const mark = struct {
        var ptr: *bool = undefined;
        fn call(_: i32) void {
            ptr.* = true;
        }
    };
    mark.ptr = &called;
    forEach(&items, mark.call);
    try testing.expect(!called);
}

// sum ──────────────────────────────────────────────────────────────────────────

test "sum: adds all items" {
    const items = [_]i32{ 1, 2, 3, 4, 5 };
    try testing.expectEqual(@as(i32, 15), sum(&items));
}

test "sum: returns 0 for empty slice" {
    const items = [_]i32{};
    try testing.expectEqual(@as(i32, 0), sum(&items));
}

test "sum: works with floats" {
    const items = [_]f32{ 1.0, 2.5, 0.5 };
    try testing.expectEqual(@as(f32, 4.0), sum(&items));
}

// min ──────────────────────────────────────────────────────────────────────────

test "min: returns smallest item" {
    const items = [_]i32{ 3, 1, 4, 1, 5, 9, 2, 6 };
    try testing.expectEqual(@as(?i32, 1), min(&items));
}

test "min: single item" {
    const items = [_]i32{42};
    try testing.expectEqual(@as(?i32, 42), min(&items));
}

test "min: null for empty slice" {
    const items = [_]i32{};
    try testing.expectEqual(@as(?i32, null), min(&items));
}

// max ──────────────────────────────────────────────────────────────────────────

test "max: returns largest item" {
    const items = [_]i32{ 3, 1, 4, 1, 5, 9, 2, 6 };
    try testing.expectEqual(@as(?i32, 9), max(&items));
}

test "max: single item" {
    const items = [_]i32{42};
    try testing.expectEqual(@as(?i32, 42), max(&items));
}

test "max: null for empty slice" {
    const items = [_]i32{};
    try testing.expectEqual(@as(?i32, null), max(&items));
}

// composition ──────────────────────────────────────────────────────────────────

test "fold then find: find max via fold" {
    const items = [_]i32{ 3, 1, 4, 1, 5, 9, 2, 6 };
    // Replicate max using fold
    const result = fold(&items, items[0], struct {
        fn call(acc: i32, x: i32) i32 {
            return if (x > acc) x else acc;
        }
    }.call);
    try testing.expectEqual(@as(i32, 9), result);
}

test "count evens and positives" {
    const items = [_]i32{ -3, -1, 1, 2, 3, 4 };
    // isEven: 2, 4 → 2
    try testing.expectEqual(@as(usize, 2), count(&items, isEven));
    // isPositive: 1, 2, 3, 4 → 4
    try testing.expectEqual(@as(usize, 4), count(&items, isPositive));
}

test "any and all compose naturally" {
    const items = [_]i32{ 2, 4, 6, 8 };
    try testing.expect(all(&items, isEven));
    try testing.expect(any(&items, isPositive));
    try testing.expect(!any(&items, struct {
        fn call(x: i32) bool {
            return x < 0;
        }
    }.call));
}
