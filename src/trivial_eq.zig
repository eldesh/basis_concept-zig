const std = @import("std");

const meta = @import("./meta.zig");

const trait = std.meta.trait;
const testing = std.testing;

const math = std.math;
const assert = std.debug.assert;
const is_or_ptrto = meta.is_or_ptrto;
const have_type = meta.have_type;
const have_fun = meta.have_fun;

/// Trivially comparable with `==`.
///
/// # Details
/// Checks that values of the type `T` is comparable with operator `==`.
/// Except for pointer types.
pub fn implTrivialEq(comptime T: type) bool {
    comptime {
        if (trait.isNumber(T))
            return true;
        if (trait.is(.Void)(T))
            return true;
        if (trait.is(.Bool)(T) or trait.is(.Null)(T))
            return true;
        // Result of comparison should be @Vector(_, bool).
        // if (trait.is(.Vector)(T))
        //     return implTrivialEq(std.meta.Child(T));
        if (trait.is(.Enum)(T))
            return implTrivialEq(@typeInfo(T).Enum.tag_type);
        if (trait.is(.EnumLiteral)(T))
            return true;
        if (trait.is(.ErrorSet)(T))
            return true;
        if (trait.is(.Fn)(T))
            return true;
        return false;
    }
}

comptime {
    assert(@as(u32, 1) == @as(u32, 1));
    assert(null == null);
    assert(true == true);
    assert(true != false);
    // assert(@Vector(2, u32){ 0, 0 } == @Vector(2, u32){ 0, 0 });
    const E = enum { EA, EB, EC };
    assert(E.EA == E.EA);
    assert(.EB == .EB);
    assert(.EB != .EC);
    const Err = error{ ErrA, ErrB, ErrC };
    assert(Err.ErrA == Err.ErrA);
    assert(Err.ErrB != Err.ErrC);
}
