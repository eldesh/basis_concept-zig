const std = @import("std");

const testing = std.testing;

const assert = std.debug.assert;

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

test "trivial_eq" {
    try testing.expect({} == {}); // Void
    try testing.expect(true == true);
    try testing.expect(true != false);
    try testing.expect(null == null);
    try testing.expect(42 == 42);
    try testing.expect(42 != 314);
    try testing.expect(@as(u32, 42) == @as(u32, 42));
    try testing.expect(@as(u32, 42) != @as(u32, 41));
    try testing.expect(.Overflow != .NotFound); // EnumLiteral
    try testing.expect(.Overflow == .Overflow); // EnumLiteral
    const AnEnum = enum { Foo, Bar };
    try testing.expect(AnEnum.Foo == AnEnum.Foo);
    try testing.expect(AnEnum.Foo != AnEnum.Bar);
    const AnEnumT = enum(u8) { Foo, Bar };
    try testing.expect(AnEnumT.Foo == AnEnumT.Foo);
    try testing.expect(AnEnumT.Foo != AnEnumT.Bar);
    const AnError = error{ FooE, BarE };
    try testing.expect(AnError.FooE == AnError.FooE);
    try testing.expect(AnError.FooE != AnError.BarE);
}
