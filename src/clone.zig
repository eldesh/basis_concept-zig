const std = @import("std");

const meta = @import("./meta.zig");
const copy = @import("./copy.zig");

const testing = std.testing;
const trait = std.meta.trait;
const assert = std.debug.assert;
const is_or_ptrto = meta.is_or_ptrto;
const have_type = meta.have_type;
const have_fun = meta.have_fun;
const deref_type = meta.deref_type;

fn implClone(comptime T: type) bool {
    comptime {
        if (copy.implCopy(T))
            return true;

        if (have_type(T, "Self")) |Self| {
            if (have_type(T, "CloneError")) |CloneError| {
                if (!trait.is(.ErrorSet)(CloneError))
                    return false;
                if (have_fun(T, "clone")) |clone_ty| {
                    if (clone_ty == fn (Self) CloneError!Self)
                        return true;
                }
            }
        }
        return false;
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
            return .{ .x = self.x };
        }
    };
    assert(implClone(T));
    assert(implClone([2]T));
    assert(!implClone([]const T));
    assert(!implClone(*T));
    assert(!implClone([*]const T));
    assert(implClone(struct { val: [2]T }));
    assert(!implClone(*struct { val: [2]T }));
}

pub fn isClonable(comptime T: type) bool {
    comptime return is_or_ptrto(implClone)(T);
}

pub const Clone = struct {
    pub const EmptyError = error{};

    pub fn ErrorType(comptime T: type) type {
        comptime assert(isClonable(T));
        const Out = deref_type(T);
        const Err = have_type(Out, "CloneError") orelse EmptyError;
        return Err;
    }

    pub fn ResultType(comptime T: type) type {
        comptime assert(isClonable(T));
        const Out = deref_type(T);
        const Err = have_type(Out, "CloneError") orelse EmptyError;
        return Err!Out;
    }

    fn clone_impl(value: anytype) ResultType(@TypeOf(value)) {
        const T = @TypeOf(value);
        const E = std.meta.Child(T);
        if (comptime have_fun(E, "clone")) |_|
            return value.clone();
        comptime assert(copy.implCopy(E));
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
        pub fn clone(self: Self) CloneError!Self {
            var ss = try testing.allocator.dupe(u8, self.ss);
            return Self{ .ss = ss };
        }
        pub fn destroy(self: *Self) void {
            testing.allocator.free(self.ss);
            self.ss.len = 0;
        }
    };

    var orig = T.new(try testing.allocator.dupe(u8, "foo"));
    defer orig.destroy();
    var new = doclone(orig);
    defer if (new) |*obj| obj.destroy() else |_| {};
    try testing.expect(std.mem.eql(u8, orig.ss, (try new).ss));
}
