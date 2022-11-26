const std = @import("std");

const meta = @import("./meta.zig");
const copy = @import("./copy.zig");

const testing = std.testing;
const trait = std.meta.trait;
const assert = std.debug.assert;
const have_type = meta.have_type;
const have_fun = meta.have_fun;
const deref_type = meta.deref_type;

fn implClone(comptime T: type) bool {
    comptime {
        return switch (@typeInfo(T)) {
            .Void, .Bool, .Null, .Int, .ComptimeInt, .Float, .ComptimeFloat, .Fn, .EnumLiteral, .ErrorSet => true,
            .Vector, .Array, .Optional => implClone(std.meta.Child(T)),
            .Enum => |Enum| implClone(Enum.tag_type),
            .ErrorUnion => |EU| implClone(EU.error_set) and implClone(EU.payload),
            .Struct => |_| block: {
                if (meta.have_fun(T, "clone")) |clone_ty| {
                    const Err = have_type(T, "CloneError") orelse Clone.EmptyError;
                    break :block (clone_ty == fn (*const T) Err!T);
                } else {
                    break :block meta.all_field_types(T, implClone);
                }
            },
            .Union => |Union| block: {
                if (meta.have_fun(T, "clone")) |clone_ty| {
                    const Err = have_type(T, "CloneError") orelse Clone.EmptyError;
                    break :block (clone_ty == fn (*const T) Err!T);
                } else {
                    const tagClone = if (Union.tag_type) |tag| implClone(tag) else true;
                    break :block tagClone and meta.all_field_types(T, implClone);
                }
            },
            else => false,
        };
    }
}

comptime {
    assert(implClone(u32));
    assert(implClone(f64));
    assert(!implClone(*u32));
    assert(!implClone(*const u32));
    assert(implClone([16]u32));
    assert(!implClone([]u32));
    const T = struct {
        pub const Self: type = @This();
        pub const CloneError: type = error{CloneError};
        x: u32,
        pub fn clone(self: *const Self) CloneError!Self {
            return Self{ .x = self.x };
        }
    };
    assert(implClone(T));
    assert(implClone([2]T));
    assert(!implClone([]const T));
    assert(!implClone(*T));
    assert(!implClone([*]const T));
    assert(implClone(struct { val: [2]T }));
    assert(!implClone(*struct { val: [2]T }));

    const U = struct {
        pub const Self: type = @This();
        // For never fail clone, error type is not defined.
        // pub const CloneError: type = undefined;
        x: u32,
        pub fn clone(self: *const Self) Clone.EmptyError!Self {
            return Self{ .x = self.x };
        }
    };
    assert(implClone(U));
    assert(implClone([2]U));
    assert(!implClone([]U));
    assert(implClone(struct { fst: T, snd: U }));
    assert(implClone([2]struct { fst: T, snd: U }));
}

pub fn isClonable(comptime T: type) bool {
    comptime return meta.is_or_ptrto(implClone)(T);
}

pub const Clone = struct {
    pub const EmptyError = error{};

    pub fn ErrorType(comptime T: type) type {
        comptime {
            assert(isClonable(T));
            const Out = deref_type(T);
            const Err = have_type(Out, "CloneError") orelse EmptyError;
            return Err;
        }
    }

    pub fn ResultType(comptime T: type) type {
        comptime {
            assert(isClonable(T));
            const Out = deref_type(T);
            const Err = have_type(Out, "CloneError") orelse EmptyError;
            return Err!Out;
        }
    }

    fn clone_impl(value: anytype) ResultType(@TypeOf(value)) {
        const T = @TypeOf(value);
        const E = std.meta.Child(T);
        if (comptime have_fun(E, "clone")) |_|
            return value.clone();
        comptime assert(copy.isCopyable(T));
        return value.*;
    }

    pub fn clone(value: anytype) ResultType(@TypeOf(value)) {
        const T = @TypeOf(value);
        comptime assert(isClonable(T));

        if (comptime !trait.isSingleItemPtr(T))
            return clone_impl(&value);
        return clone_impl(value);
    }
};

test "Clone" {
    const doclone = Clone.clone;

    const ax = [3]u32{ 0, 1, 2 };
    try testing.expectEqual(ax, try doclone(&ax));

    try testing.expectEqual(@as(error{}!u32, 5), doclone(@as(u32, 5)));
    try testing.expectEqual(@as(error{}!comptime_int, 5), doclone(5));
    try testing.expectEqual(@as(error{}![3]u32, [_]u32{ 1, 2, 3 }), doclone([_]u32{ 1, 2, 3 }));
    const val: u64 = 42;
    const ptr = &val;
    try testing.expectEqual(@as(error{}!u64, ptr.*), doclone(ptr));

    const T = struct {
        pub const Self: type = @This();
        pub const CloneError: type = std.mem.Allocator.Error;
        ss: []u8,
        pub fn new(ss: []u8) Self {
            return .{ .ss = ss };
        }
        pub fn clone(self: *const Self) CloneError!Self {
            var ss = try testing.allocator.dupe(u8, self.ss);
            return Self{ .ss = ss };
        }
        pub fn destroy(self: Self) void {
            var it = self;
            testing.allocator.free(it.ss);
            it.ss.len = 0;
        }
    };

    comptime assert(isClonable(T));
    var orig = T.new(try testing.allocator.dupe(u8, "foo"));
    defer orig.destroy();
    var new = doclone(orig);
    defer if (new) |*obj| obj.destroy() else |_| {};
    try testing.expect(std.mem.eql(u8, orig.ss, (try new).ss));
}
