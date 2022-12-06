pub const copy = @import("copy.zig");
pub const clone = @import("clone.zig");
pub const partial_ord = @import("partial_ord.zig");
pub const ord = @import("ord.zig");
pub const partial_eq = @import("partial_eq.zig");
pub const trivial_eq = @import("trivial_eq.zig");
pub const eq = @import("eq.zig");
pub const trivial_destroy = @import("trivial_destroy.zig");
pub const destroy = @import("destroy.zig");

pub const isCopyable = copy.isCopyable;

pub const isClonable = clone.isClonable;
pub const Clone = clone.Clone;

pub const isPartialOrd = partial_ord.isPartialOrd;
pub const PartialOrd = partial_ord.PartialOrd;

pub const isOrd = ord.isOrd;
pub const Ord = ord.Ord;

pub const isPartialEq = partial_eq.isPartialEq;
pub const PartialEq = partial_eq.PartialEq;

pub const isEq = eq.isEq;
pub const Eq = eq.Eq;

pub const isDestroy = destroy.isDestroy;
pub const Destroy = destroy.Destroy;

pub const isTrivialEq = trivial_eq.isTrivialEq;
pub const isTrivialDestroy = trivial_destroy.isTrivialDestroy;

/// Namespace provides basic functions.
pub const prelude = struct {
    pub const Clone = clone.Clone;
    pub const PartialOrd = partial_ord.PartialOrd;
    pub const Ord = ord.Ord;
    pub const PartialEq = partial_eq.PartialEq;
    pub const Eq = eq.Eq;
    pub const Destroy = destroy.Destroy;
};

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());

    const assert = std.debug.assert;
    comptime assert(ord.isOrd(clone.Clone.EmptyError!u32));
    comptime assert(ord.isOrd(*const (clone.Clone.EmptyError!u32)));
}
