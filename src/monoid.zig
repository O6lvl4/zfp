//! monoid.zig — Zero-cost Semigroup / Monoid combinators for Zig.
//!
//! A Monoid is a type with:
//!   - an identity element `empty`
//!   - an associative binary operation `append`
//!   - `concat` = fold over a slice using `append`, starting from `empty`
//!
//! Named monoids provided:
//!   Sum     — numeric addition:         empty = 0,     append = a + b
//!   Product — numeric multiplication:   empty = 1,     append = a * b
//!   Any     — boolean disjunction:      empty = false, append = a or b
//!   All     — boolean conjunction:      empty = true,  append = a and b
//!   First   — first non-null optional:  empty = null,  append = a orelse b
//!   Last    — last non-null optional:   empty = null,  append = b orelse a
//!
//! Each monoid is a namespace with three functions:
//!   empty()           — identity element
//!   append(a, b)      — combine two values
//!   concat(items)     — fold a slice

const std = @import("std");

fn Elem(comptime S: type) type {
    return std.meta.Elem(S);
}

// ─── Sum ──────────────────────────────────────────────────────────────────────

/// Monoid over numeric addition.
///
///   empty  = 0
///   append = a + b
///
/// Haskell: `newtype Sum a = Sum { getSum :: a }` with `Monoid` instance.
pub const Sum = struct {
    /// The additive identity: `0`.
    pub inline fn empty(comptime T: type) T {
        return 0;
    }

    /// Combine two values by addition.
    ///
    ///   append(3, 4)  →  7
    pub inline fn append(a: anytype, b: anytype) @TypeOf(a) {
        return a + b;
    }

    /// Sum all items in a slice. Returns `0` for an empty slice.
    ///
    ///   concat(&.{1, 2, 3, 4})  →  10
    pub inline fn concat(items: anytype) Elem(@TypeOf(items)) {
        var acc: Elem(@TypeOf(items)) = 0;
        for (items) |item| acc += item;
        return acc;
    }
};

// ─── Product ──────────────────────────────────────────────────────────────────

/// Monoid over numeric multiplication.
///
///   empty  = 1
///   append = a * b
///
/// Haskell: `newtype Product a = Product { getProduct :: a }` with `Monoid` instance.
pub const Product = struct {
    /// The multiplicative identity: `1`.
    pub inline fn empty(comptime T: type) T {
        return 1;
    }

    /// Combine two values by multiplication.
    ///
    ///   append(3, 4)  →  12
    pub inline fn append(a: anytype, b: anytype) @TypeOf(a) {
        return a * b;
    }

    /// Multiply all items in a slice. Returns `1` for an empty slice.
    ///
    ///   concat(&.{1, 2, 3, 4})  →  24
    pub inline fn concat(items: anytype) Elem(@TypeOf(items)) {
        var acc: Elem(@TypeOf(items)) = 1;
        for (items) |item| acc *= item;
        return acc;
    }
};

// ─── Any ──────────────────────────────────────────────────────────────────────

/// Monoid over boolean disjunction (OR).
///
///   empty  = false
///   append = a or b
///
/// Haskell: `newtype Any = Any { getAny :: Bool }` with `Monoid` instance.
pub const Any = struct {
    /// The identity for OR: `false`.
    pub inline fn empty() bool {
        return false;
    }

    /// Combine two booleans with OR.
    ///
    ///   append(false, true)  →  true
    pub inline fn append(a: bool, b: bool) bool {
        return a or b;
    }

    /// `true` if any item is `true`. `false` for an empty slice.
    ///
    ///   concat(&.{false, true, false})  →  true
    pub inline fn concat(items: anytype) bool {
        for (items) |item| if (item) return true;
        return false;
    }
};

// ─── All ──────────────────────────────────────────────────────────────────────

/// Monoid over boolean conjunction (AND).
///
///   empty  = true
///   append = a and b
///
/// Haskell: `newtype All = All { getAll :: Bool }` with `Monoid` instance.
pub const All = struct {
    /// The identity for AND: `true`.
    pub inline fn empty() bool {
        return true;
    }

    /// Combine two booleans with AND.
    ///
    ///   append(true, false)  →  false
    pub inline fn append(a: bool, b: bool) bool {
        return a and b;
    }

    /// `true` if all items are `true`. `true` for an empty slice (vacuously).
    ///
    ///   concat(&.{true, false, true})  →  false
    pub inline fn concat(items: anytype) bool {
        for (items) |item| if (!item) return false;
        return true;
    }
};

// ─── First ────────────────────────────────────────────────────────────────────

/// Monoid over optional values — keeps the first non-null.
///
///   empty  = null
///   append = a orelse b
///
/// Haskell: `newtype First a = First { getFirst :: Maybe a }` with `Monoid` instance.
pub const First = struct {
    /// The identity for First: `null`.
    pub inline fn empty(comptime T: type) ?T {
        return null;
    }

    /// Return `a` if non-null, otherwise `b`.
    ///
    ///   append(?i32, null, @as(?i32, 42))  →  42
    ///   append(?i32, @as(?i32, 1), @as(?i32, 2))  →  1
    pub inline fn append(a: anytype, b: anytype) @TypeOf(a) {
        return a orelse b;
    }

    /// Return the first non-null item, or `null` if all items are null.
    ///
    ///   concat(&.{null, @as(?i32, 2), @as(?i32, 3)})  →  @as(?i32, 2)
    pub inline fn concat(items: anytype) Elem(@TypeOf(items)) {
        for (items) |item| if (item != null) return item;
        return null;
    }
};

// ─── Last ─────────────────────────────────────────────────────────────────────

/// Monoid over optional values — keeps the last non-null.
///
///   empty  = null
///   append = b orelse a
///
/// Haskell: `newtype Last a = Last { getLast :: Maybe a }` with `Monoid` instance.
pub const Last = struct {
    /// The identity for Last: `null`.
    pub inline fn empty(comptime T: type) ?T {
        return null;
    }

    /// Return `b` if non-null, otherwise `a`.
    ///
    ///   append(?i32, @as(?i32, 1), null)  →  1
    ///   append(?i32, @as(?i32, 1), @as(?i32, 2))  →  2
    pub inline fn append(a: anytype, b: anytype) @TypeOf(a) {
        return b orelse a;
    }

    /// Return the last non-null item, or `null` if all items are null.
    ///
    ///   concat(&.{@as(?i32, 1), @as(?i32, 2), null})  →  @as(?i32, 2)
    pub inline fn concat(items: anytype) Elem(@TypeOf(items)) {
        var result: Elem(@TypeOf(items)) = null;
        for (items) |item| if (item != null) { result = item; };
        return result;
    }
};

// ─── Tests ────────────────────────────────────────────────────────────────────

const testing = std.testing;

// Sum ──────────────────────────────────────────────────────────────────────────

test "Sum.empty: identity for i32" {
    try testing.expectEqual(@as(i32, 0), Sum.empty(i32));
}

test "Sum.append: adds two values" {
    try testing.expectEqual(@as(i32, 7), Sum.append(@as(i32, 3), @as(i32, 4)));
}

test "Sum.append: identity laws" {
    const x: i32 = 5;
    try testing.expectEqual(x, Sum.append(Sum.empty(i32), x));
    try testing.expectEqual(x, Sum.append(x, Sum.empty(i32)));
}

test "Sum.concat: sums all items" {
    const items = [_]i32{ 1, 2, 3, 4 };
    try testing.expectEqual(@as(i32, 10), Sum.concat(&items));
}

test "Sum.concat: empty slice returns 0" {
    const items = [_]i32{};
    try testing.expectEqual(@as(i32, 0), Sum.concat(&items));
}

test "Sum.concat: works with floats" {
    const items = [_]f32{ 1.0, 2.5, 0.5 };
    try testing.expectEqual(@as(f32, 4.0), Sum.concat(&items));
}

// Product ──────────────────────────────────────────────────────────────────────

test "Product.empty: identity for i32" {
    try testing.expectEqual(@as(i32, 1), Product.empty(i32));
}

test "Product.append: multiplies two values" {
    try testing.expectEqual(@as(i32, 12), Product.append(@as(i32, 3), @as(i32, 4)));
}

test "Product.append: identity laws" {
    const x: i32 = 5;
    try testing.expectEqual(x, Product.append(Product.empty(i32), x));
    try testing.expectEqual(x, Product.append(x, Product.empty(i32)));
}

test "Product.concat: multiplies all items" {
    const items = [_]i32{ 1, 2, 3, 4 };
    try testing.expectEqual(@as(i32, 24), Product.concat(&items));
}

test "Product.concat: empty slice returns 1" {
    const items = [_]i32{};
    try testing.expectEqual(@as(i32, 1), Product.concat(&items));
}

// Any ──────────────────────────────────────────────────────────────────────────

test "Any.empty: false" {
    try testing.expect(!Any.empty());
}

test "Any.append: OR of two booleans" {
    try testing.expect(Any.append(false, true));
    try testing.expect(!Any.append(false, false));
}

test "Any.append: identity laws" {
    try testing.expect(Any.append(Any.empty(), true));
    try testing.expect(!Any.append(Any.empty(), false));
}

test "Any.concat: true if any is true" {
    const items = [_]bool{ false, false, true };
    try testing.expect(Any.concat(&items));
}

test "Any.concat: false if all are false" {
    const items = [_]bool{ false, false, false };
    try testing.expect(!Any.concat(&items));
}

test "Any.concat: false for empty slice" {
    const items = [_]bool{};
    try testing.expect(!Any.concat(&items));
}

// All ──────────────────────────────────────────────────────────────────────────

test "All.empty: true" {
    try testing.expect(All.empty());
}

test "All.append: AND of two booleans" {
    try testing.expect(All.append(true, true));
    try testing.expect(!All.append(true, false));
}

test "All.append: identity laws" {
    try testing.expect(All.append(All.empty(), true));
    try testing.expect(!All.append(All.empty(), false));
}

test "All.concat: false if any is false" {
    const items = [_]bool{ true, false, true };
    try testing.expect(!All.concat(&items));
}

test "All.concat: true if all are true" {
    const items = [_]bool{ true, true, true };
    try testing.expect(All.concat(&items));
}

test "All.concat: true for empty slice" {
    const items = [_]bool{};
    try testing.expect(All.concat(&items));
}

// First ────────────────────────────────────────────────────────────────────────

test "First.empty: null" {
    try testing.expectEqual(@as(?i32, null), First.empty(i32));
}

test "First.append: returns first non-null" {
    try testing.expectEqual(@as(?i32, 1), First.append(@as(?i32, 1), @as(?i32, 2)));
}

test "First.append: returns second when first is null" {
    try testing.expectEqual(@as(?i32, 2), First.append(@as(?i32, null), @as(?i32, 2)));
}

test "First.append: identity laws" {
    const x: ?i32 = 42;
    try testing.expectEqual(x, First.append(First.empty(i32), x));
    try testing.expectEqual(x, First.append(x, First.empty(i32)));
}

test "First.concat: returns first non-null" {
    const items = [_]?i32{ null, 2, 3 };
    try testing.expectEqual(@as(?i32, 2), First.concat(&items));
}

test "First.concat: null for all-null slice" {
    const items = [_]?i32{ null, null };
    try testing.expectEqual(@as(?i32, null), First.concat(&items));
}

test "First.concat: null for empty slice" {
    const items = [_]?i32{};
    try testing.expectEqual(@as(?i32, null), First.concat(&items));
}

// Last ─────────────────────────────────────────────────────────────────────────

test "Last.empty: null" {
    try testing.expectEqual(@as(?i32, null), Last.empty(i32));
}

test "Last.append: returns last non-null" {
    try testing.expectEqual(@as(?i32, 2), Last.append(@as(?i32, 1), @as(?i32, 2)));
}

test "Last.append: returns first when second is null" {
    try testing.expectEqual(@as(?i32, 1), Last.append(@as(?i32, 1), @as(?i32, null)));
}

test "Last.append: identity laws" {
    const x: ?i32 = 42;
    try testing.expectEqual(x, Last.append(Last.empty(i32), x));
    try testing.expectEqual(x, Last.append(x, Last.empty(i32)));
}

test "Last.concat: returns last non-null" {
    const items = [_]?i32{ 1, 2, null };
    try testing.expectEqual(@as(?i32, 2), Last.concat(&items));
}

test "Last.concat: null for all-null slice" {
    const items = [_]?i32{ null, null };
    try testing.expectEqual(@as(?i32, null), Last.concat(&items));
}

test "Last.concat: null for empty slice" {
    const items = [_]?i32{};
    try testing.expectEqual(@as(?i32, null), Last.concat(&items));
}

// composition ──────────────────────────────────────────────────────────────────

test "Sum and Product compose: sum of products" {
    // sum of [1*2, 3*4, 5*6] = 2 + 12 + 30 = 44
    const pairs = [_][2]i32{ .{ 1, 2 }, .{ 3, 4 }, .{ 5, 6 } };
    var products: [3]i32 = undefined;
    for (pairs, 0..) |p, i| products[i] = Product.append(p[0], p[1]);
    try testing.expectEqual(@as(i32, 44), Sum.concat(&products));
}

test "Any and All together: any true but not all" {
    const items = [_]bool{ true, false, true };
    try testing.expect(Any.concat(&items));
    try testing.expect(!All.concat(&items));
}

test "First and Last: bracket a sequence" {
    const items = [_]?i32{ null, 1, 2, 3, null };
    try testing.expectEqual(@as(?i32, 1), First.concat(&items));
    try testing.expectEqual(@as(?i32, 3), Last.concat(&items));
}
