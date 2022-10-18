const std = @import("std");

const meta = @import("./meta.zig");

const have_type = meta.have_type;
const have_fun = meta.have_fun;

fn implDestroy(comptime T: type) bool {
    comptime {
        return switch (@typeInfo(T)) {
            .Void, .Bool, .Null, .Int, .ComptimeInt, .Float, .ComptimeFloat, .Fn, .EnumLiteral, .ErrorSet => true,
            .Vector, .Array, .Optional => implDestroy(std.meta.Child(T)),
            .Enum => |Enum| implDestroy(Enum.tag_type),
            .ErrorUnion => |ErrorUnion| implDestroy(ErrorUnion.error_set) and implDestroy(ErrorUnion.payload),
            .Struct, .Union => block: {
                if (have_fun(T, "destroy")) |destroy_ty| {
                    break :block (destroy_ty == fn (*T) void);
                } else {
                    const tagDestroy = if (meta.tag_of(T) catch null) |tag| implDestroy(tag) else true;
                    break :block tagDestroy and meta.all_field_types(T, implDestroy);
                }
            },
            else => false,
        };
    }
}
