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
        return switch (@typeInfo(T)) {
            .Void, .Bool, .Null, .Int, .ComptimeInt, .Float, .ComptimeFloat, .Fn, .EnumLiteral, .ErrorSet => true,
            .Vector => |V| implCopy(V.child),
            .Array => |A| implCopy(A.child),
            .Optional => |O| implCopy(O.child),
            .Enum => |Enum| implCopy(Enum.tag_type),
            .ErrorUnion => |EU| implCopy(EU.error_set) and implCopy(EU.payload),
            .Struct => |_| return block: {
                break :block meta.all_field_types(T, implCopy);
            },
            .Union => |Union| return block: {
                const tagCopy = if (Union.tag_type) |tag| implCopy(tag) else false;
                break :block tagCopy and meta.all_field_types(T, implCopy);
            },
            else => false,
        };
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
