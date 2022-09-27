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
fn implTrivialEq(comptime T: type) bool {
    comptime {
        return switch (@typeInfo(T)) {
            .Int, .Float, .ComptimeInt, .ComptimeFloat, .Void, .Bool, .Null, .EnumLiteral, .ErrorSet => true,
            .Enum => |e| return implTrivialEq(e.tag_type),
            else => false,
        };
    }
}

comptime {
    assert(implTrivialEq(u32));
    assert(implTrivialEq(void));
    assert(implTrivialEq(bool));
    assert(implTrivialEq(@TypeOf(null)));
    assert(!implTrivialEq(?u32));
    assert(!implTrivialEq(*u32));
    assert(!implTrivialEq(?*u32));
    assert(!implTrivialEq(?**u32));
    assert(!implTrivialEq([3]u32));
    assert(implTrivialEq(error{FooError}));
    assert(implTrivialEq(@TypeOf(.Tag1)));
    assert(!implTrivialEq(struct { v: u32 }));
    assert(!implTrivialEq(union(enum) { I: u32, F: u64 }));
    const Err = error{ ErrA, ErrB, ErrC };
    assert(implTrivialEq(Err));
    assert(!implTrivialEq(Err!u32));
}

comptime {
    assert(@as(u32, 1) == @as(u32, 1));
    assert(void{} == void{});
    assert(true == true);
    assert(true != false);
    assert(null == null);
    // assert(@Vector(2, u32){ 0, 0 } == @Vector(2, u32){ 0, 0 });
    const E = enum { EA, EB, EC };
    assert(E.EA == E.EA);
    assert(.EB == .EB);
    assert(.EB != .EC);
    const Err = error{ ErrA, ErrB, ErrC };
    assert(Err.ErrA == Err.ErrA);
    assert(Err.ErrB != Err.ErrC);
}

pub fn isTrivialEq(comptime T: type) bool {
    return implTrivialEq(T);
}
