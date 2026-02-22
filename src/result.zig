//! result.zig — Zero-cost Result utilities for Zig's native `anyerror!T` type.
//!
//! Design philosophy:
//!   - Do NOT wrap anyerror!T in a struct. Work directly with native Zig error unions.
//!   - No allocations, no boxing, no runtime overhead.
//!   - All functions are `inline`; the compiler folds them into the call site.
//!   - Comptime generics via `anytype` — one definition handles every T and E.
//!   - Mirrors the `option` module API so both feel consistent.

// ─── Internal helpers ─────────────────────────────────────────────────────────

/// Extract the payload type T from an error-union type E!T.
/// Emits a compile error when the argument is not an error union.
fn PayloadType(comptime EU: type) type {
    return switch (@typeInfo(EU)) {
        .error_union => |eu| eu.payload,
        else => @compileError(
            "Expected error union type (E!T), got: " ++ @typeName(EU),
        ),
    };
}

/// Extract the error set type E from an error-union type E!T.
fn ErrorType(comptime EU: type) type {
    return switch (@typeInfo(EU)) {
        .error_union => |eu| eu.error_set,
        else => @compileError(
            "Expected error union type (E!T), got: " ++ @typeName(EU),
        ),
    };
}

/// Get the return type from a function type or function-pointer type.
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

/// Apply `f` to the error; leave the success value unchanged.
///
///   mapErr(E!T, fn(E) F) → F!T
///
/// Haskell: `Data.Bifunctor.first :: (a -> b) -> Either a c -> Either b c`
/// Rust:    `Result::map_err`
///
/// **Zero-cost**: compiles to a single `catch` branch.
pub inline fn mapErr(value: anytype, f: anytype) FnReturnType(@TypeOf(f))!PayloadType(@TypeOf(value)) {
    if (value) |v| return v else |err| return f(err);
}

/// Apply `f` to the success value. Propagates errors unchanged.
///
///   map(E!T, fn(T) U) → E!U
///
/// **Zero-cost**: `inline` + no indirection → equivalent to `try` + assignment.
pub inline fn map(value: anytype, f: anytype) ErrorType(@TypeOf(value))!FnReturnType(@TypeOf(f)) {
    return f(try value);
}

/// Apply `f` (which itself returns an error union) to the success value.
/// Equivalent to `flatMap` / `bind` for error unions.
///
///   andThen(E!T, fn(T) E!U) → E!U
///
/// **Zero-cost**: compiles to a `try` followed by a tail call.
pub inline fn andThen(value: anytype, f: anytype) FnReturnType(@TypeOf(f)) {
    return f(value catch |err| return err);
}

/// Apply a wrapped function to a wrapped value. Propagates any error.
///
///   ap(E!fn(T)U, E!T) → (E1||E2)!U
///
/// Haskell: `(<*>) :: Applicative f => f (a -> b) -> f a -> f b`
///
/// **Zero-cost**: two `try` expressions, no allocation.
pub inline fn ap(f: anytype, value: anytype) (ErrorType(@TypeOf(f)) || ErrorType(@TypeOf(value)))!FnReturnType(PayloadType(@TypeOf(f))) {
    return (try f)(try value);
}

/// Return `value` if successful, otherwise `fallback`.
///
///   orElse(E!T, E!T) → E!T
///
/// Haskell: `(<|>) :: Alternative f => f a -> f a -> f a`
///
/// **Zero-cost**: compiles directly to Zig's `catch` expression.
pub inline fn orElse(value: anytype, fallback: anytype) @TypeOf(value) {
    return value catch fallback;
}

/// Return the success value, or `default` if the result is an error.
///
///   unwrapOr(E!T, T) → T
///
/// **Zero-cost**: compiles directly to Zig's `catch` expression.
pub inline fn unwrapOr(value: anytype, default: anytype) PayloadType(@TypeOf(value)) {
    return value catch default;
}

/// Return the success value, or the result of calling `f(err)` on the error.
///
///   unwrapOrElse(E!T, fn(E) T) → T
///
/// **Zero-cost**: compiles to a `catch |err| f(err)` expression.
pub inline fn unwrapOrElse(value: anytype, f: anytype) PayloadType(@TypeOf(value)) {
    return value catch |err| f(err);
}

/// Returns `true` when the result holds a success value.
///
/// **Zero-cost**: a single null/error comparison.
pub inline fn isOk(value: anytype) bool {
    _ = value catch return false;
    return true;
}

/// Returns `true` when the result holds an error.
///
/// **Zero-cost**: a single null/error comparison.
pub inline fn isErr(value: anytype) bool {
    _ = value catch return true;
    return false;
}

/// Convert an `E!T` to `?T`, discarding the error information.
///
///   toOption(E!T) → ?T
///
/// Useful for bridging result-based and option-based code paths.
pub inline fn toOption(value: anytype) ?PayloadType(@TypeOf(value)) {
    return value catch null;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

const testing = @import("std").testing;

const Err = error{Bad};

// isOk / isErr ─────────────────────────────────────────────────────────────────

test "isOk: success returns true" {
    try testing.expect(isOk(@as(Err!i32, 42)));
}

test "isOk: error returns false" {
    try testing.expect(!isOk(@as(Err!i32, error.Bad)));
}

test "isErr: error returns true" {
    try testing.expect(isErr(@as(Err!i32, error.Bad)));
}

test "isErr: success returns false" {
    try testing.expect(!isErr(@as(Err!i32, 42)));
}

// mapErr ───────────────────────────────────────────────────────────────────────

const Err2 = error{Other};

test "mapErr: passes success value through unchanged" {
    const result = mapErr(@as(Err!i32, 42), struct {
        fn call(_: anyerror) Err2 {
            return error.Other;
        }
    }.call);
    try testing.expectEqual(@as(Err2!i32, 42), result);
}

test "mapErr: transforms the error" {
    const result = mapErr(@as(Err!i32, error.Bad), struct {
        fn call(_: anyerror) Err2 {
            return error.Other;
        }
    }.call);
    try testing.expectError(error.Other, result);
}

test "mapErr: can map error to a different error set" {
    const OtherErr = error{NotFound};
    const result = mapErr(@as(Err![]const u8, error.Bad), struct {
        fn call(_: anyerror) OtherErr {
            return error.NotFound;
        }
    }.call);
    try testing.expectError(error.NotFound, result);
}

// map ──────────────────────────────────────────────────────────────────────────

test "map: applies f to success value" {
    const result = map(@as(Err!i32, 21), struct {
        fn call(x: i32) i32 {
            return x * 2;
        }
    }.call);
    try testing.expectEqual(@as(Err!i32, 42), result);
}

test "map: propagates error unchanged" {
    const result = map(@as(Err!i32, error.Bad), struct {
        fn call(x: i32) i32 {
            return x * 2;
        }
    }.call);
    try testing.expectError(error.Bad, result);
}

test "map: changes the payload type" {
    const result = map(@as(Err![]const u8, "hello"), struct {
        fn call(s: []const u8) usize {
            return s.len;
        }
    }.call);
    try testing.expectEqual(@as(Err!usize, 5), result);
}

// andThen ──────────────────────────────────────────────────────────────────────

test "andThen: success through fallible f" {
    const result = andThen(@as(Err!i32, 10), struct {
        fn call(x: i32) Err!i32 {
            return x + 1;
        }
    }.call);
    try testing.expectEqual(@as(Err!i32, 11), result);
}

test "andThen: propagates error from value" {
    const result = andThen(@as(Err!i32, error.Bad), struct {
        fn call(x: i32) Err!i32 {
            return x + 1;
        }
    }.call);
    try testing.expectError(error.Bad, result);
}

test "andThen: propagates error from f" {
    const result = andThen(@as(Err!i32, 0), struct {
        fn call(x: i32) Err!i32 {
            if (x == 0) return error.Bad;
            return x;
        }
    }.call);
    try testing.expectError(error.Bad, result);
}

test "andThen: chains multiple fallible operations" {
    const safeDiv = struct {
        fn call(x: i32) Err!i32 {
            if (x == 0) return error.Bad;
            return @divTrunc(100, x);
        }
    }.call;

    // 5 → 100/5=20 → 100/20=5
    const result = andThen(andThen(@as(Err!i32, 5), safeDiv), safeDiv);
    try testing.expectEqual(@as(Err!i32, 5), result);

    // 0 → error (first division)
    const err = andThen(andThen(@as(Err!i32, 0), safeDiv), safeDiv);
    try testing.expectError(error.Bad, err);
}

// ap ───────────────────────────────────────────────────────────────────────────

test "ap: applies wrapped function to success value" {
    const double = struct {
        fn call(x: i32) i32 {
            return x * 2;
        }
    }.call;
    const result = ap(@as(Err!@TypeOf(double), double), @as(Err!i32, 21));
    try testing.expectEqual(@as(Err!i32, 42), result);
}

test "ap: propagates error from function" {
    const double = struct {
        fn call(x: i32) i32 {
            return x * 2;
        }
    }.call;
    const result = ap(@as(Err!@TypeOf(double), error.Bad), @as(Err!i32, 21));
    try testing.expectError(error.Bad, result);
}

test "ap: propagates error from value" {
    const double = struct {
        fn call(x: i32) i32 {
            return x * 2;
        }
    }.call;
    const result = ap(@as(Err!@TypeOf(double), double), @as(Err!i32, error.Bad));
    try testing.expectError(error.Bad, result);
}

// orElse ───────────────────────────────────────────────────────────────────────

test "orElse: returns first value when successful" {
    const result = orElse(@as(Err!i32, 1), @as(Err!i32, 2));
    try testing.expectEqual(@as(Err!i32, 1), result);
}

test "orElse: returns fallback when first is error" {
    const result = orElse(@as(Err!i32, error.Bad), @as(Err!i32, 42));
    try testing.expectEqual(@as(Err!i32, 42), result);
}

test "orElse: returns fallback error when both fail" {
    const result = orElse(@as(Err!i32, error.Bad), @as(Err!i32, error.Bad));
    try testing.expectError(error.Bad, result);
}

// unwrapOr ─────────────────────────────────────────────────────────────────────

test "unwrapOr: returns success value" {
    try testing.expectEqual(@as(i32, 42), unwrapOr(@as(Err!i32, 42), 0));
}

test "unwrapOr: returns default on error" {
    try testing.expectEqual(@as(i32, 0), unwrapOr(@as(Err!i32, error.Bad), 0));
}

// unwrapOrElse ─────────────────────────────────────────────────────────────────

test "unwrapOrElse: returns success value" {
    try testing.expectEqual(@as(i32, 42), unwrapOrElse(@as(Err!i32, 42), struct {
        fn call(_: anyerror) i32 {
            return -1;
        }
    }.call));
}

test "unwrapOrElse: calls f with error on failure" {
    const result = unwrapOrElse(@as(Err!i32, error.Bad), struct {
        fn call(_: anyerror) i32 {
            return -1;
        }
    }.call);
    try testing.expectEqual(@as(i32, -1), result);
}

// toOption ─────────────────────────────────────────────────────────────────────

test "toOption: success becomes Some" {
    try testing.expectEqual(@as(?i32, 42), toOption(@as(Err!i32, 42)));
}

test "toOption: error becomes null" {
    try testing.expectEqual(@as(?i32, null), toOption(@as(Err!i32, error.Bad)));
}

// ─── Usage example ────────────────────────────────────────────────────────────
//
// Before (nested if/catch):
//
//   fn process(input: anyerror![]const u8) anyerror!i32 {
//       const s = try input;
//       const n = try std.fmt.parseInt(i32, s, 10);
//       if (n <= 0) return error.OutOfRange;
//       return n * 2;
//   }
//
// After (result pipeline):
//
//   fn process(input: anyerror![]const u8) anyerror!i32 {
//       return result.andThen(
//           result.andThen(input, parseInt),
//           doubleIfPositive,
//       );
//   }
//
// Both produce identical machine code.

test "example: pipeline over fallible operations" {
    const std = @import("std");

    const parseInt = struct {
        fn call(s: []const u8) anyerror!i32 {
            return std.fmt.parseInt(i32, s, 10);
        }
    }.call;

    const doubleIfPositive = struct {
        fn call(x: i32) anyerror!i32 {
            if (x <= 0) return error.OutOfRange;
            return x * 2;
        }
    }.call;

    // Happy path
    try testing.expectEqual(
        @as(anyerror!i32, 42),
        andThen(andThen(@as(anyerror![]const u8, "21"), parseInt), doubleIfPositive),
    );

    // Parse failure propagates as error
    try testing.expectError(
        error.InvalidCharacter,
        andThen(andThen(@as(anyerror![]const u8, "abc"), parseInt), doubleIfPositive),
    );

    // Value present but out of range
    try testing.expectError(
        error.OutOfRange,
        andThen(andThen(@as(anyerror![]const u8, "-5"), parseInt), doubleIfPositive),
    );
}
