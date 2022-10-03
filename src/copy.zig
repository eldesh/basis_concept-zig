const std = @import("std");
const meta = @import("./meta.zig");

const trait = std.meta.trait;
const assert = std.debug.assert;
const is_or_ptrto = meta.is_or_ptrto;

/// Checks that the type `T` is `traivially copyable`.
///
/// # Details
/// Values of that types are able to be duplicated with just copying the binary sequence.
fn implCopy(comptime T: type) bool {
    comptime {
        if (trait.is(.Void)(T))
            return true;
        if (trait.is(.Bool)(T) or trait.is(.Null)(T))
            return true;
        if (trait.isNumber(T))
            return true;
        if (trait.is(.Vector)(T) or trait.is(.Array)(T) or trait.is(.Optional)(T))
            return implCopy(std.meta.Child(T));
        if (trait.is(.Fn)(T))
            return true;
        if (trait.is(.Enum)(T))
            return implCopy(@typeInfo(T).Enum.tag_type);
        if (trait.is(.EnumLiteral)(T))
            return true;
        if (trait.is(.ErrorSet)(T))
            return true;
        if (trait.is(.ErrorUnion)(T))
            return implCopy(@typeInfo(T).ErrorUnion.error_set) and implCopy(@typeInfo(T).ErrorUnion.payload);
        if (trait.is(.Struct)(T) or trait.is(.Union)(T)) {
            if (meta.tag_of(T) catch null) |tag| {
                if (!implCopy(tag))
                    return false;
            }
            // all type of fields are copyable
            return meta.all_field_types(T, implCopy);
        }
        return false;
    }
}

comptime {
    assert(implCopy(u32));
    assert(implCopy(struct { val: u32 }));
    assert(implCopy(f64));
    assert(!implCopy(*u64));
    assert(implCopy(?f64));
    assert(implCopy(struct { val: f32 }));
    assert(!implCopy([]const u8));
    assert(!implCopy([*]f64));
    assert(implCopy([5]u32));
    const U = union(enum) { Tag1, Tag2, Tag3 };
    assert(implCopy(U));
    assert(!implCopy(*U));
    assert(!implCopy(*const U));
    const OverflowError = error{Overflow};
    assert(implCopy(@TypeOf(.Overflow))); // EnumLiteral
    assert(implCopy(OverflowError)); // ErrorSet
    assert(implCopy(OverflowError![2]U)); // ErrorUnion
    assert(implCopy(?(error{Overflow}![2]U)));
    assert(implCopy(struct { val: ?(error{Overflow}![2]U) }));
    assert(!implCopy(struct { val: ?(error{Overflow}![2]*const U) }));
}

pub fn isCopyable(comptime T: type) bool {
    comptime return is_or_ptrto(implCopy)(T);
}

test "Copy" {
    const x: u32 = 42;
    const y = x;
    _ = y;

    const mx: ?u32 = 42;
    const my = mx;
    _ = my;

    const ax = [3]u32{ 1, 2, 3 };
    const bx = ax;
    _ = bx;
}
