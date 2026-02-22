//! option.zig — Zero-cost Option utilities for Zig's native `?T` type.
//!
//! Design philosophy:
//!   - Do NOT wrap ?T in a struct. Work directly with native Zig optionals.
//!   - No allocations, no boxing, no runtime overhead.
//!   - All functions are `inline`; the compiler folds them into the call site.
//!   - Comptime generics via `anytype` — one definition handles every T.
//!   - The goal: eliminate deeply nested `if (value) |v| { if (...) }` chains.

// ─── Internal helpers ─────────────────────────────────────────────────────────

/// Extract the child type T from an optional type ?T.
/// Emits a compile error when the argument is not an optional type.
fn ChildType(comptime OptT: type) type {
    return switch (@typeInfo(OptT)) {
        .optional => |opt| opt.child,
        else => @compileError(
            "Expected optional type (?T), got: " ++ @typeName(OptT),
        ),
    };
}

/// Assert that T is an optional type; emit a readable error if not.
fn requireOptional(comptime T: type, comptime caller: []const u8) void {
    if (@typeInfo(T) != .optional) {
        @compileError(caller ++ ": expected optional type (?T), got " ++ @typeName(T));
    }
}

/// Extract the return type from a function type or function-pointer type.
/// Emits a compile error for non-function types or functions with inferred
/// return types.
fn FnReturnType(comptime F: type) type {
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

// ─── Public API ───────────────────────────────────────────────────────────────

/// Apply `f` to the contained value and wrap the result back in `?`.
/// Returns `null` unchanged when `value` is null.
///
///   map(?T, fn(T) U) → ?U
///
/// **Zero-cost**: `inline` + no indirection → a single conditional branch
/// in the generated code, identical to a hand-written `if (v) |x| f(x)`.
pub inline fn map(value: anytype, f: anytype) ?FnReturnType(@TypeOf(f)) {
    comptime requireOptional(@TypeOf(value), "option.map");
    return if (value) |v| f(v) else null;
}

/// Apply `f` (which returns an optional) to the contained value, flattening
/// the result. Equivalent to `flatMap` / `bind` in other languages.
/// Returns `null` when `value` is null or when `f` returns null.
///
///   andThen(?T, fn(T) ?U) → ?U
///
/// **Zero-cost**: identical machine code to nested `if` unwrapping.
pub inline fn andThen(value: anytype, f: anytype) FnReturnType(@TypeOf(f)) {
    comptime requireOptional(@TypeOf(value), "option.andThen");
    return if (value) |v| f(v) else null;
}

/// Return the contained value, or `default` when `value` is null.
///
///   unwrapOr(?T, T) → T
///
/// **Zero-cost**: compiles directly to Zig's `orelse` expression.
pub inline fn unwrapOr(value: anytype, default: anytype) ChildType(@TypeOf(value)) {
    return value orelse default;
}

/// Apply a wrapped function to a wrapped value. Both must be non-null to produce a result.
///
///   ap(?fn(T)U, ?T) → ?U
///
/// Haskell: `(<*>) :: Maybe (a -> b) -> Maybe a -> Maybe b`
///
/// **Zero-cost**: two conditional branches, no allocation.
pub inline fn ap(f: anytype, value: anytype) ?FnReturnType(ChildType(@TypeOf(f))) {
    if (f) |func| {
        if (value) |v| return func(v);
    }
    return null;
}

/// Return `value` if non-null, otherwise `fallback`.
///
///   orElse(?T, ?T) → ?T
///
/// Haskell: `(<|>) :: Alternative f => f a -> f a -> f a`
///
/// **Zero-cost**: compiles directly to Zig's `orelse` expression.
pub inline fn orElse(value: anytype, fallback: anytype) @TypeOf(value) {
    comptime requireOptional(@TypeOf(value), "option.orElse");
    return value orelse fallback;
}

/// Keep the value only when `predicate(v)` is true; otherwise return null.
///
///   filter(?T, fn(T) bool) → ?T
///
/// **Zero-cost**: two nested branches, no allocation, no boxing.
pub inline fn filter(value: anytype, predicate: anytype) @TypeOf(value) {
    comptime requireOptional(@TypeOf(value), "option.filter");
    if (value) |v| {
        if (predicate(v)) return v; // T coerces to ?T at the return site
    }
    return null;
}

/// Returns `true` when `value` is non-null.
///
/// **Zero-cost**: a null comparison; optimised away at compile time when the
/// value is comptime-known.
pub inline fn isSome(value: anytype) bool {
    comptime requireOptional(@TypeOf(value), "option.isSome");
    return value != null;
}

/// Returns `true` when `value` is null.
///
/// **Zero-cost**: same as `isSome`.
pub inline fn isNone(value: anytype) bool {
    comptime requireOptional(@TypeOf(value), "option.isNone");
    return value == null;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

const testing = @import("std").testing;

// isSome / isNone ──────────────────────────────────────────────────────────────

test "isSome: non-null returns true" {
    try testing.expect(isSome(@as(?i32, 42)));
}

test "isSome: null returns false" {
    try testing.expect(!isSome(@as(?i32, null)));
}

test "isNone: null returns true" {
    try testing.expect(isNone(@as(?i32, null)));
}

test "isNone: non-null returns false" {
    try testing.expect(!isNone(@as(?i32, 42)));
}

// map ──────────────────────────────────────────────────────────────────────────

test "map: applies f to non-null value" {
    const result = map(@as(?i32, 21), struct {
        fn call(x: i32) i32 {
            return x * 2;
        }
    }.call);
    try testing.expectEqual(@as(?i32, 42), result);
}

test "map: propagates null unchanged" {
    const result = map(@as(?i32, null), struct {
        fn call(x: i32) i32 {
            return x * 2;
        }
    }.call);
    try testing.expectEqual(@as(?i32, null), result);
}

test "map: changes the inner type" {
    const result = map(@as(?[]const u8, "hello"), struct {
        fn call(s: []const u8) usize {
            return s.len;
        }
    }.call);
    try testing.expectEqual(@as(?usize, 5), result);
}

test "map: chains cleanly" {
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
    // map twice: 3 → 6 → -6
    const result = map(map(@as(?i32, 3), double), negate);
    try testing.expectEqual(@as(?i32, -6), result);
}

// andThen ──────────────────────────────────────────────────────────────────────

test "andThen: applies f when non-null and f returns non-null" {
    const result = andThen(@as(?i32, 10), struct {
        fn call(x: i32) ?i32 {
            return x + 1;
        }
    }.call);
    try testing.expectEqual(@as(?i32, 11), result);
}

test "andThen: propagates null input" {
    const result = andThen(@as(?i32, null), struct {
        fn call(x: i32) ?i32 {
            return x + 1;
        }
    }.call);
    try testing.expectEqual(@as(?i32, null), result);
}

test "andThen: propagates when f returns null" {
    const result = andThen(@as(?i32, 0), struct {
        fn call(x: i32) ?i32 {
            if (x == 0) return null;
            return x;
        }
    }.call);
    try testing.expectEqual(@as(?i32, null), result);
}

test "andThen: chains multiple fallible operations" {
    // Safe integer division: returns null when divisor is zero
    const safe_div_100 = struct {
        fn call(x: i32) ?i32 {
            if (x == 0) return null;
            return @divTrunc(100, x);
        }
    }.call;

    // 5 → 100/5=20 → 100/20=5
    const result = andThen(andThen(@as(?i32, 5), safe_div_100), safe_div_100);
    try testing.expectEqual(@as(?i32, 5), result);

    // 0 → null (first division)
    const zero = andThen(andThen(@as(?i32, 0), safe_div_100), safe_div_100);
    try testing.expectEqual(@as(?i32, null), zero);
}

// unwrapOr ─────────────────────────────────────────────────────────────────────

test "unwrapOr: returns contained value when non-null" {
    try testing.expectEqual(@as(i32, 42), unwrapOr(@as(?i32, 42), 0));
}

test "unwrapOr: returns default when null" {
    try testing.expectEqual(@as(i32, 0), unwrapOr(@as(?i32, null), 0));
}

test "unwrapOr: works with slices" {
    const result: []const u8 = unwrapOr(@as(?[]const u8, null), "default");
    try testing.expectEqualStrings("default", result);
}

// ap ───────────────────────────────────────────────────────────────────────────

test "ap: applies wrapped function to wrapped value" {
    const double = struct {
        fn call(x: i32) i32 {
            return x * 2;
        }
    }.call;
    const result = ap(@as(?@TypeOf(double), double), @as(?i32, 21));
    try testing.expectEqual(@as(?i32, 42), result);
}

test "ap: returns null when function is null" {
    const double = struct {
        fn call(x: i32) i32 {
            return x * 2;
        }
    }.call;
    const result = ap(@as(?@TypeOf(double), null), @as(?i32, 21));
    try testing.expectEqual(@as(?i32, null), result);
}

test "ap: returns null when value is null" {
    const double = struct {
        fn call(x: i32) i32 {
            return x * 2;
        }
    }.call;
    const result = ap(@as(?@TypeOf(double), double), @as(?i32, null));
    try testing.expectEqual(@as(?i32, null), result);
}

test "ap: returns null when both are null" {
    const double = struct {
        fn call(x: i32) i32 {
            return x * 2;
        }
    }.call;
    const result = ap(@as(?@TypeOf(double), null), @as(?i32, null));
    try testing.expectEqual(@as(?i32, null), result);
}

// orElse ───────────────────────────────────────────────────────────────────────

test "orElse: returns first value when non-null" {
    try testing.expectEqual(@as(?i32, 1), orElse(@as(?i32, 1), @as(?i32, 2)));
}

test "orElse: returns fallback when first is null" {
    try testing.expectEqual(@as(?i32, 2), orElse(@as(?i32, null), @as(?i32, 2)));
}

test "orElse: returns null when both are null" {
    try testing.expectEqual(@as(?i32, null), orElse(@as(?i32, null), @as(?i32, null)));
}

// filter ───────────────────────────────────────────────────────────────────────

const isPositive = struct {
    fn call(x: i32) bool {
        return x > 0;
    }
}.call;

test "filter: keeps value when predicate is true" {
    try testing.expectEqual(@as(?i32, 5), filter(@as(?i32, 5), isPositive));
}

test "filter: returns null when predicate is false" {
    try testing.expectEqual(@as(?i32, null), filter(@as(?i32, -3), isPositive));
}

test "filter: propagates null input" {
    try testing.expectEqual(@as(?i32, null), filter(@as(?i32, null), isPositive));
}

// ─── Usage example: nested-if elimination ────────────────────────────────────
//
// Before (nested ifs):
//
//   fn process(input: ?[]const u8) ?i32 {
//       if (input) |s| {
//           const n = std.fmt.parseInt(i32, s, 10) catch return null;
//           if (n > 0) {
//               return n * 2;
//           }
//       }
//       return null;
//   }
//
// After (option pipeline):
//
//   fn process(input: ?[]const u8) ?i32 {
//       return andThen(
//           andThen(input, parseInt),
//           doubleIfPositive,
//       );
//   }
//
// Both produce identical machine code. The option version scales without
// indentation growing with every added step.

test "example: nested-if elimination" {
    const std = @import("std");

    const parseInt = struct {
        fn call(s: []const u8) ?i32 {
            return std.fmt.parseInt(i32, s, 10) catch null;
        }
    }.call;

    const doubleIfPositive = struct {
        fn call(x: i32) ?i32 {
            if (x <= 0) return null;
            return x * 2;
        }
    }.call;

    // Happy path
    try testing.expectEqual(
        @as(?i32, 42),
        andThen(andThen(@as(?[]const u8, "21"), parseInt), doubleIfPositive),
    );

    // Parse succeeds but value is non-positive → filter step discards it
    try testing.expectEqual(
        @as(?i32, null),
        andThen(andThen(@as(?[]const u8, "-5"), parseInt), doubleIfPositive),
    );

    // Null input propagates silently through the whole pipeline
    try testing.expectEqual(
        @as(?i32, null),
        andThen(andThen(@as(?[]const u8, null), parseInt), doubleIfPositive),
    );

    // Parse failure propagates as null
    try testing.expectEqual(
        @as(?i32, null),
        andThen(andThen(@as(?[]const u8, "not-a-number"), parseInt), doubleIfPositive),
    );
}
