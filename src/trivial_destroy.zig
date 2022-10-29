const std = @import("std");

const meta = @import("./meta.zig");

const testing = std.testing;
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;

fn implTrivialDestroy(comptime T: type) bool {
    comptime {
        return switch (@typeInfo(T)) {
            .Void, .Bool, .Null, .Int, .ComptimeInt, .Float, .ComptimeFloat, .Fn, .EnumLiteral, .ErrorSet => true,
            .Vector, .Array, .Optional => implTrivialDestroy(std.meta.Child(T)),
            .Enum => |Enum| implTrivialDestroy(Enum.tag_type),
            .ErrorUnion => |ErrorUnion| implTrivialDestroy(ErrorUnion.error_set) and implTrivialDestroy(ErrorUnion.payload),
            .Struct, .Union => block: {
                const tagDestroy = if (meta.tag_of(T) catch null) |tag| implTrivialDestroy(tag) else true;
                break :block tagDestroy and meta.all_field_types(T, implTrivialDestroy);
            },
            else => false,
        };
    }
}

pub fn isTrivialDestroy(comptime T: type) bool {
    comptime return implTrivialDestroy(T);
}

comptime {
    assert(isTrivialDestroy(u32));
    assert(!isTrivialDestroy(*u32));
    assert(isTrivialDestroy(f32));
    assert(isTrivialDestroy(?f32));
    assert(isTrivialDestroy([5]u8));
    assert(isTrivialDestroy(struct {
        s0: [5]u32,
        s1: bool,
        s2: comptime_int,
    }));
    assert(isTrivialDestroy(struct { s0: [5]u32, s1: bool, s2: comptime_int, s3: struct {
        s30: [3]u8,
        s31: struct {},
    } }));
    assert(isTrivialDestroy(union {
        u0: [5]u32,
        u1: bool,
        u2: comptime_float,
    }));
    assert(isTrivialDestroy(union {
        u0: [5]u32,
        u1: bool,
        u2: comptime_float,
        u3: trivial,

        const trivial = struct {
            s0: f64,
            s1: u32,
            s2: [2][3][4]u8,
        };
    }));
}
