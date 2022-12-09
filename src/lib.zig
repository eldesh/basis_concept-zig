/// Concept for types that trivially comparable value with `==`.
/// This concept is defined for checking the type is comparable with `==`.
/// Then any extra method is not provided.
pub const trivial_eq = @import("trivial_eq.zig");

/// Concept for types that trivially destroyable implicitly.
/// Then any extra method is not provided.
pub const trivial_destroy = @import("trivial_destroy.zig");

/// Trivially copyable values with `=`.
/// `Copy` means to duplicate a value that has no resources shared with the original one.
/// In other words, it must not contain a pointer.
pub const copy = @import("copy.zig");

/// Duplicable values using `clone` method if exists.
/// Similar to Copyable, `Clonable` means that the value can be duplicated. However, the concept can be satisfied if the `clone` method is implemented even if the value cannot be copied in the trivial way.
/// In other words, if a type is `Copyable`, it is automatically `Clonable` as well.
pub const clone = @import("clone.zig");

/// `PartialEq` concept means that a partial equivalence relation is defined for the type.
/// The partiality comes from the fact that the relation does not require reflexivity.
/// That is, the relation must satisfy the following properties. for all x, y and z:
///
/// ```
/// PartialEq.eq(x, y) == PartialEq.eq(y, x)
/// PartialEq.eq(x, y) == PartialEq.eq(y, z) == PartialEq.eq(x, z)
/// ```
pub const partial_eq = @import("partial_eq.zig");

/// `Eq` concept means that a full equivalence relation is defined for the type.
/// Addition to `PartialEq`, this concept requires relations to have reflexivity.
///
/// ```
/// Eq.eq(x, y) == Eq.eq(y, x)
/// Eq.eq(x, y) and Eq.eq(y, z) implies Eq.eq(x, z)
/// Eq.eq(x, x)
/// ```
/// Furthermore, this concept also contains `ne` method, which must be consistent with `eq`.
pub const eq = @import("eq.zig");

/// `PartialOrd` concept means parial ordering relation.
/// Such relations require the type satisfies properties and have consistensy to `PartialEq`.
///
/// ```
/// PartialOrd.partial_cmp(x, y).?.compare(.eq) implies PartialEq.eq(x, y)
/// PartialOrd.partial_cmp(x, y).?.compare(.le) implies PartialOrd.partial_cmp(x, y).?.compare(.lt) or PartialEq.eq(x, y)
/// PartialOrd.partial_cmp(x, y).?.compare(.ge) implies PartialOrd.partial_cmp(x, y).?.compare(.lt) or PartialEq.eq(x, y)
/// ```
pub const partial_ord = @import("partial_ord.zig");

/// Concept for types that forms total order.
/// Implementations must be consistent with `PartialOrd`.
///
/// ```
/// Ord.cmp(x, y) == PartialOrd.partial_cmp(x, y).?
/// ```
pub const ord = @import("ord.zig");

/// The `Destroy` concept provides an interface for destroying values.
/// Values of types implementing this concept can be destroyed by `destroy(@This())` or `destroy(@This(), std.mem.Allocator)`.
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

/// Namespace provides functions on concepts.
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
