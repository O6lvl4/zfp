//! either.zig — Zero-cost Left/Right sum type for Zig.
//!
//! `Either(L, R)` represents a value that is one of two alternatives:
//!   - `Left(L)` — typically the "error" or "secondary" case
//!   - `Right(R)` — typically the "success" or "primary" case
//!
//! Inspired by Haskell's `Data.Either`. Builds on Zig's native tagged unions.
//!
//! Core operations:
//!   map(e, f)                — apply f to Right; leave Left unchanged
//!   mapLeft(e, f)            — apply f to Left;  leave Right unchanged
//!   bimap(e, lf, rf)         — apply lf to Left or rf to Right
//!   andThen(e, f)            — flatMap on Right; short-circuit on Left
//!   ap(ef, ea)               — apply wrapped function to wrapped value
//!   isLeft(e)                — true if Left
//!   isRight(e)               — true if Right
//!   unwrapOr(e, default)     — Right value or default
//!   unwrapOrElse(e, f)       — Right value or f(left)
//!   fromOption(opt, lv)      — ?R → Either(L, R)
//!   toOption(e)              — Either(L, R) → ?R

const std = @import("std");

// ─── Type constructor ─────────────────────────────────────────────────────────

/// A value that is either `Left(L)` or `Right(R)`.
///
/// By convention, `Right` is the "success" / primary side and
/// `Left` is the "error" / secondary side — matching Haskell's Either.
///
/// Usage:
///   const E = either.Either([]const u8, i32);
///   const ok  = E{ .right = 42 };
///   const err = E{ .left  = "oops" };
pub fn Either(comptime L: type, comptime R: type) type {
    return union(enum) {
        left: L,
        right: R,
    };
}

// ─── Internal helpers ─────────────────────────────────────────────────────────

fn LeftOf(comptime E: type) type {
    for (@typeInfo(E).@"union".fields) |field| {
        if (std.mem.eql(u8, field.name, "left")) return field.type;
    }
    @compileError("not an Either type: missing `left` field");
}

fn RightOf(comptime E: type) type {
    for (@typeInfo(E).@"union".fields) |field| {
        if (std.mem.eql(u8, field.name, "right")) return field.type;
    }
    @compileError("not an Either type: missing `right` field");
}

fn FnReturnType(comptime F: type) type {
    return switch (@typeInfo(F)) {
        .@"fn" => |info| info.return_type orelse
            @compileError("Function must declare an explicit return type"),
        .pointer => |ptr| switch (@typeInfo(ptr.child)) {
            .@"fn" => |info| info.return_type orelse
                @compileError("Function must declare an explicit return type"),
            else => @compileError("Expected a function or function pointer, got: " ++ @typeName(F)),
        },
        else => @compileError("Expected a function type, got: " ++ @typeName(F)),
    };
}

// ─── Public API ───────────────────────────────────────────────────────────────

/// Apply `f` to the `Right` value; leave `Left` unchanged.
///
///   map(.{.right = r}, f)  →  .{.right = f(r)}
///   map(.{.left  = l}, f)  →  .{.left  = l}
///
/// Haskell: `fmap :: (a -> b) -> Either l a -> Either l b`
///
/// **Zero-cost**: inlines to a switch + function call + union construction.
pub inline fn map(e: anytype, f: anytype) Either(
    LeftOf(@TypeOf(e)),
    @TypeOf(f(@as(RightOf(@TypeOf(e)), undefined))),
) {
    return switch (e) {
        .left => |l| .{ .left = l },
        .right => |r| .{ .right = f(r) },
    };
}

/// Apply `f` to the `Left` value; leave `Right` unchanged.
///
///   mapLeft(.{.left  = l}, f)  →  .{.left  = f(l)}
///   mapLeft(.{.right = r}, f)  →  .{.right = r}
///
/// **Zero-cost**: inlines to a switch + function call + union construction.
pub inline fn mapLeft(e: anytype, f: anytype) Either(
    @TypeOf(f(@as(LeftOf(@TypeOf(e)), undefined))),
    RightOf(@TypeOf(e)),
) {
    return switch (e) {
        .left => |l| .{ .left = f(l) },
        .right => |r| .{ .right = r },
    };
}

/// Apply `lf` to `Left` or `rf` to `Right`, returning a new Either.
///
///   bimap(.{.left  = l}, lf, rf)  →  .{.left  = lf(l)}
///   bimap(.{.right = r}, lf, rf)  →  .{.right = rf(r)}
///
/// Haskell: `bimap :: (a -> c) -> (b -> d) -> Either a b -> Either c d`
///
/// **Zero-cost**: inlines to a switch + one function call + union construction.
pub inline fn bimap(e: anytype, lf: anytype, rf: anytype) Either(
    @TypeOf(lf(@as(LeftOf(@TypeOf(e)), undefined))),
    @TypeOf(rf(@as(RightOf(@TypeOf(e)), undefined))),
) {
    return switch (e) {
        .left => |l| .{ .left = lf(l) },
        .right => |r| .{ .right = rf(r) },
    };
}

/// Monadic bind on `Right`; short-circuit on `Left`.
///
///   andThen(.{.right = r}, f)  →  f(r)           (f must return an Either)
///   andThen(.{.left  = l}, f)  →  .{.left = l}
///
/// Haskell: `(>>=) :: Either l a -> (a -> Either l b) -> Either l b`
///
/// **Zero-cost**: inlines to a switch + optional function call.
pub inline fn andThen(e: anytype, f: anytype) @TypeOf(f(@as(RightOf(@TypeOf(e)), undefined))) {
    const Ret = @TypeOf(f(@as(RightOf(@TypeOf(e)), undefined)));
    return switch (e) {
        .left => |l| Ret{ .left = l },
        .right => |r| f(r),
    };
}

/// Apply a wrapped function to a wrapped value.
///
///   ap(.{.right = f}, .{.right = x})  →  .{.right = f(x)}
///   ap(.{.left  = l}, .{.right = x})  →  .{.left  = l}    (function was Left)
///   ap(.{.right = f}, .{.left  = l})  →  .{.left  = l}    (value was Left)
///
/// Haskell: `(<*>) :: Either l (a -> b) -> Either l a -> Either l b`
///
/// **Zero-cost**: inlines to a nested switch with at most one function call.
pub inline fn ap(ef: anytype, ea: anytype) Either(
    LeftOf(@TypeOf(ef)),
    FnReturnType(RightOf(@TypeOf(ef))),
) {
    const Ret = Either(LeftOf(@TypeOf(ef)), FnReturnType(RightOf(@TypeOf(ef))));
    return switch (ef) {
        .left => |l| Ret{ .left = l },
        .right => |f| switch (ea) {
            .left => |l| Ret{ .left = l },
            .right => |a| Ret{ .right = f(a) },
        },
    };
}

/// Return `true` if the value is `Left`.
pub inline fn isLeft(e: anytype) bool {
    return switch (e) {
        .left => true,
        .right => false,
    };
}

/// Return `true` if the value is `Right`.
pub inline fn isRight(e: anytype) bool {
    return switch (e) {
        .left => false,
        .right => true,
    };
}

/// Extract the `Right` value, or return `default` if `Left`.
///
///   unwrapOr(.{.right = r}, d)  →  r
///   unwrapOr(.{.left  = l}, d)  →  d
pub inline fn unwrapOr(e: anytype, default: RightOf(@TypeOf(e))) RightOf(@TypeOf(e)) {
    return switch (e) {
        .left => default,
        .right => |r| r,
    };
}

/// Extract the `Right` value, or call `f(left)` if `Left`.
///
///   unwrapOrElse(.{.right = r}, f)  →  r
///   unwrapOrElse(.{.left  = l}, f)  →  f(l)
pub inline fn unwrapOrElse(e: anytype, f: anytype) RightOf(@TypeOf(e)) {
    return switch (e) {
        .left => |l| f(l),
        .right => |r| r,
    };
}

/// Convert `?R` to `Either(L, R)`.
/// `null` becomes `Left(left_val)`; a non-null value becomes `Right`.
///
///   fromOption(@as(?i32, 42), "none")  →  .{.right = 42}
///   fromOption(@as(?i32, null), "none")  →  .{.left = "none"}
pub inline fn fromOption(
    opt: anytype,
    left_val: anytype,
) Either(@TypeOf(left_val), std.meta.Child(@TypeOf(opt))) {
    return if (opt) |r| .{ .right = r } else .{ .left = left_val };
}

/// Convert `Either(L, R)` to `?R`, discarding `Left`.
///
///   toOption(.{.right = r})  →  r     (non-null)
///   toOption(.{.left  = l})  →  null
pub inline fn toOption(e: anytype) ?RightOf(@TypeOf(e)) {
    return switch (e) {
        .left => null,
        .right => |r| r,
    };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

const testing = std.testing;

const StrInt = Either([]const u8, i32);

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

const strLen = struct {
    fn call(s: []const u8) usize {
        return s.len;
    }
}.call;

const lenAsI32 = struct {
    fn call(s: []const u8) i32 {
        return @intCast(s.len);
    }
}.call;

// isLeft / isRight ─────────────────────────────────────────────────────────────

test "isLeft: returns true for Left" {
    const e = StrInt{ .left = "oops" };
    try testing.expect(isLeft(e));
    try testing.expect(!isRight(e));
}

test "isRight: returns true for Right" {
    const e = StrInt{ .right = 42 };
    try testing.expect(isRight(e));
    try testing.expect(!isLeft(e));
}

// map ──────────────────────────────────────────────────────────────────────────

test "map: applies f to Right" {
    const e = StrInt{ .right = 3 };
    const result = map(e, double);
    try testing.expectEqual(@as(i32, 6), result.right);
}

test "map: passes Left through unchanged" {
    const e = StrInt{ .left = "error" };
    const result = map(e, double);
    try testing.expectEqualStrings("error", result.left);
}

test "map: Right type can change" {
    const e = StrInt{ .right = 5 };
    const result = map(e, isPositive); // i32 → bool
    try testing.expect(result.right);
}

// mapLeft ──────────────────────────────────────────────────────────────────────

test "mapLeft: applies f to Left" {
    const e = StrInt{ .left = "hi" };
    const result = mapLeft(e, strLen); // []const u8 → usize
    try testing.expectEqual(@as(usize, 2), result.left);
}

test "mapLeft: passes Right through unchanged" {
    const e = StrInt{ .right = 42 };
    const result = mapLeft(e, strLen);
    try testing.expectEqual(@as(i32, 42), result.right);
}

// bimap ────────────────────────────────────────────────────────────────────────

test "bimap: applies lf to Left" {
    const e = StrInt{ .left = "hi" };
    const result = bimap(e, strLen, double);
    try testing.expectEqual(@as(usize, 2), result.left);
}

test "bimap: applies rf to Right" {
    const e = StrInt{ .right = 5 };
    const result = bimap(e, strLen, double);
    try testing.expectEqual(@as(i32, 10), result.right);
}

// andThen ──────────────────────────────────────────────────────────────────────

test "andThen: applies f to Right" {
    const safeDouble = struct {
        fn call(x: i32) StrInt {
            return if (x > 0) .{ .right = x * 2 } else .{ .left = "non-positive" };
        }
    }.call;

    const e = StrInt{ .right = 3 };
    const result = andThen(e, safeDouble);
    try testing.expectEqual(@as(i32, 6), result.right);
}

test "andThen: short-circuits on Left" {
    const safeDouble = struct {
        fn call(x: i32) StrInt {
            return if (x > 0) .{ .right = x * 2 } else .{ .left = "non-positive" };
        }
    }.call;

    const e = StrInt{ .left = "already failed" };
    const result = andThen(e, safeDouble);
    try testing.expectEqualStrings("already failed", result.left);
}

test "andThen: chain two operations" {
    const step = struct {
        fn call(x: i32) StrInt {
            return if (x < 100) .{ .right = x * 2 } else .{ .left = "too large" };
        }
    }.call;

    const e = StrInt{ .right = 10 };
    const result = andThen(andThen(e, step), step); // 10 → 20 → 40
    try testing.expectEqual(@as(i32, 40), result.right);
}

test "andThen: propagates first Left in chain" {
    const step = struct {
        fn call(x: i32) StrInt {
            return if (x < 100) .{ .right = x * 2 } else .{ .left = "too large" };
        }
    }.call;

    const e = StrInt{ .right = 60 };
    const result = andThen(andThen(e, step), step); // 60 → 120 → Left
    try testing.expectEqualStrings("too large", result.left);
}

// ap ───────────────────────────────────────────────────────────────────────────

const FnStrInt = Either([]const u8, fn (i32) i32);
const FnStrBool = Either([]const u8, fn (i32) bool);

test "ap: applies Right function to Right value" {
    const ef = FnStrInt{ .right = double };
    const ea = StrInt{ .right = 3 };
    const result = ap(ef, ea);
    try testing.expectEqual(@as(i32, 6), result.right);
}

test "ap: Left function short-circuits" {
    const ef = FnStrInt{ .left = "no function" };
    const ea = StrInt{ .right = 3 };
    const result = ap(ef, ea);
    try testing.expectEqualStrings("no function", result.left);
}

test "ap: Left value short-circuits" {
    const ef = FnStrInt{ .right = double };
    const ea = StrInt{ .left = "no value" };
    const result = ap(ef, ea);
    try testing.expectEqualStrings("no value", result.left);
}

test "ap: function can change Right type" {
    const ef = FnStrBool{ .right = isPositive };
    const ea = StrInt{ .right = 5 };
    const result = ap(ef, ea);
    try testing.expect(result.right);
}

// unwrapOr ─────────────────────────────────────────────────────────────────────

test "unwrapOr: returns Right value" {
    const e = StrInt{ .right = 42 };
    try testing.expectEqual(@as(i32, 42), unwrapOr(e, 0));
}

test "unwrapOr: returns default on Left" {
    const e = StrInt{ .left = "error" };
    try testing.expectEqual(@as(i32, 0), unwrapOr(e, 0));
}

// unwrapOrElse ─────────────────────────────────────────────────────────────────

test "unwrapOrElse: returns Right value" {
    const e = StrInt{ .right = 42 };
    try testing.expectEqual(@as(i32, 42), unwrapOrElse(e, lenAsI32));
}

test "unwrapOrElse: calls f on Left" {
    const e = StrInt{ .left = "hello" };
    try testing.expectEqual(@as(i32, 5), unwrapOrElse(e, lenAsI32));
}

// fromOption ───────────────────────────────────────────────────────────────────

test "fromOption: non-null becomes Right" {
    const opt: ?i32 = 42;
    const result = fromOption(opt, "missing");
    try testing.expectEqual(@as(i32, 42), result.right);
}

test "fromOption: null becomes Left" {
    const opt: ?i32 = null;
    const result = fromOption(opt, "missing");
    try testing.expectEqualStrings("missing", result.left);
}

// toOption ─────────────────────────────────────────────────────────────────────

test "toOption: Right becomes non-null" {
    const e = StrInt{ .right = 42 };
    const result = toOption(e);
    try testing.expectEqual(@as(?i32, 42), result);
}

test "toOption: Left becomes null" {
    const e = StrInt{ .left = "error" };
    const result = toOption(e);
    try testing.expectEqual(@as(?i32, null), result);
}

// composition ──────────────────────────────────────────────────────────────────

test "map then andThen" {
    const parse = struct {
        fn call(x: i32) StrInt {
            return if (x >= 0) .{ .right = x } else .{ .left = "negative" };
        }
    }.call;

    // map doubles, then andThen validates
    const e = StrInt{ .right = 3 };
    const result = andThen(map(e, double), parse); // 3 → 6 → Right(6)
    try testing.expectEqual(@as(i32, 6), result.right);
}

test "fromOption then map" {
    const opt: ?i32 = 5;
    const e = fromOption(opt, "missing");
    const result = map(e, double);
    try testing.expectEqual(@as(i32, 10), result.right);
}
