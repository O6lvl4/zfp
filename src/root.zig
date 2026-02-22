//! zfp — Zero-cost Functional Programming toolkit for Zig
//!
//! Modules:
//!   option  — Functor / Monad / Applicative for ?T
//!   result  — Functor / Monad / Applicative for anyerror!T
//!   either  — Left(L) | Right(R) sum type — Bifunctor, Monad
//!   pipe    — Left-to-right function pipeline
//!   compose — Reusable composed callable
//!   zf      — Primitive combinators: id, flip, const_, on
//!   tap     — Side-effect injection without breaking pipelines
//!   arrow   — Pair combinators: first, second, split, fanout
//!   slice   — Foldable operations over slices
//!   monoid  — Named monoids: Sum, Product, Any, All, First, Last, Endo

pub const option = @import("option.zig");
pub const result = @import("result.zig");
pub const pipe = @import("pipe.zig");
pub const compose = @import("compose.zig");
pub const zf = @import("zf.zig");
pub const tap = @import("tap.zig");
pub const arrow = @import("arrow.zig");
pub const either = @import("either.zig");
pub const slice = @import("slice.zig");
pub const monoid = @import("monoid.zig");
