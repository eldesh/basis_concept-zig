const std = @import("std");

const meta = @import("./meta.zig");

const testing = std.testing;
const trait = std.meta.trait;
const have_type = meta.have_type;
const have_fun = meta.have_fun;
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

fn isTrivialDestroy(comptime T: type) bool {
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
    assert(isTrivialDestroy(union {
        u0: [5]u32,
        u1: bool,
        u2: comptime_float,
    }));
}

fn implDestroy(comptime T: type) bool {
    comptime {
        if (isTrivialDestroy(T))
            return true;
        return switch (@typeInfo(T)) {
            .Struct, .Union => block: {
                if (have_fun(T, "destroy")) |destroy_ty| {
                    break :block (destroy_ty == fn (*T) void or destroy_ty == fn (*T, Allocator) void);
                } else {
                    const tagDestroy = if (meta.tag_of(T) catch null) |tag| implDestroy(tag) else true;
                    break :block tagDestroy and meta.all_field_types(T, implDestroy);
                }
            },
            else => false,
        };
    }
}

pub fn isDestroy(comptime T: type) bool {
    comptime return implDestroy(T);
}

comptime {
    assert(isDestroy(u32));
    assert(!isDestroy(*u32));
    assert(isDestroy(f32));
    assert(isDestroy(?f32));
    assert(isDestroy([5]u8));
    assert(isDestroy(struct {
        s0: [5]u32,
        s1: bool,
        s2: comptime_int,
    }));
    assert(isDestroy(union {
        u0: [5]u32,
        u1: bool,
        u2: comptime_float,
    }));
    assert(isDestroy(struct {
        s0: [5]u32,
        s1: bool,
        s2: u32,
        s3: ***u32,
        s4: *[]const u8,

        pub fn destroy(self: *@This()) void {
            _ = self;
        }
    }));
    assert(isDestroy(union {
        u0: [5]u32,
        u1: bool,
        u2: f32,
        u3: ***u32,
        u4: *[]const u8,

        pub fn destroy(self: *@This()) void {
            _ = self;
        }
    }));
    assert(isDestroy(struct {
        alloc: Allocator,
        s1: *struct {
            s0: [5]u32,
            s1: bool,
            s2: u32,
            s3: ***u32,
            s4: *[]const u8,

            pub fn destroy(self: *@This()) void {
                _ = self;
            }
        },

        pub fn destroy(self: *@This()) void {
            _ = self;
        }
    }));
}

pub const Destroy = struct {
    fn destroy_struct(comptime T: type, value: T, alloc: Allocator) void {
        comptime assert(trait.is(.Struct)(T));
        var v = value;
        if (have_fun(T, "destroy")) |ty| {
            if (ty == fn (*T) void)
                return v.destroy();
            if (ty == fn (*T, Allocator) void)
                return v.destroy(alloc);
            unreachable;
        }
        inline for (std.meta.fields(T)) |field| {
            return destroy(@field(v, field.name), alloc);
        }
    }

    fn destroy_union(comptime T: type, value: T, alloc: Allocator) void {
        comptime assert(trait.is(.Union)(T));
        var v = value;
        if (have_fun(T, "destroy")) |ty| {
            if (ty == fn (*T) void)
                return v.destroy();
            if (ty == fn (*T, Allocator) void)
                return v.destroy(alloc);
            unreachable;
        }
        inline for (std.meta.fields(T)) |field| {
            if (@field(v, field.name) == std.meta.activeTag(v))
                return destroy(@field(v, field.name));
        }
    }

    pub fn on(comptime T: type) fn (T, Allocator) void {
        return struct {
            fn impl(value: T, allocator: Allocator) void {
                comptime assert(isDestroy(T));
                var v = value;
                switch (@typeInfo(T)) {
                    .Struct => destroy_struct(T, v, allocator),
                    .Union => destroy_union(T, v, allocator),
                    else => {},
                }
            }
        }.impl;
    }

    pub fn destroy(value: anytype, allocator: Allocator) void {
        on(@TypeOf(value))(value, allocator);
    }
};

test "Destroy" {
    const allocator = testing.allocator;

    {
        var v0: u32 = 314;
        Destroy.destroy(v0, allocator);
    }
    {
        var v1: f32 = 3.14;
        Destroy.destroy(v1, allocator);
    }
    {
        var v2: ?f32 = 0.5;
        Destroy.destroy(v2, allocator);
    }
    {
        var v3: [5]u8 = [5]u8{ 0, 1, 2, 3, 4 };
        Destroy.destroy(v3, allocator);
    }
    {
        const S = struct {
            s0: [5]u32,
            s1: bool,
            s2: u32,
        };
        var s0: S = .{ .s0 = [5]u32{ 0, 1, 2, 3, 4 }, .s1 = true, .s2 = 42 };
        Destroy.destroy(s0, allocator);
    }
    {
        const S = struct {
            alloc: Allocator,
            s0: [5]u32,
            s1: bool,
            s2: u32,
            s3: ***u32,
            s4: *[]const u8,

            pub fn new(
                alloc: Allocator,
                s0: [5]u32,
                s1: bool,
                s2: u32,
            ) Allocator.Error!@This() {
                var s3p = try alloc.create(u32);
                s3p.* = 5;
                var s3pp = try alloc.create(*u32);
                s3pp.* = s3p;
                var s3 = try alloc.create(**u32);
                s3.* = s3pp;
                var s4s = try std.fmt.allocPrint(alloc, "{s}", .{"hello"});
                var s4 = try alloc.create([]const u8);
                s4.* = s4s;
                return @This(){ .alloc = alloc, .s0 = s0, .s1 = s1, .s2 = s2, .s3 = s3, .s4 = s4 };
            }

            pub fn destroy(self: *@This()) void {
                self.alloc.destroy(self.s3.*.*);
                self.alloc.destroy(self.s3.*);
                self.alloc.destroy(self.s3);
                self.alloc.free(self.s4.*);
                self.alloc.destroy(self.s4);
            }
        };
        var s0: S = try S.new(
            allocator,
            [5]u32{ 0, 1, 2, 3, 4 },
            false,
            42,
        );
        defer Destroy.destroy(s0, allocator);

        const S2 = struct {
            alloc: Allocator,
            s1: *S,

            pub fn new(alloc: Allocator, s1: S) !@This() {
                var p = try alloc.create(S);
                p.* = s1;
                return @This(){ .alloc = alloc, .s1 = p };
            }

            pub fn destroy(self: *@This()) void {
                Destroy.destroy(self.s1.*, self.alloc);
                self.alloc.destroy(self.s1);
            }
        };
        comptime assert(isDestroy(S2));

        var s1: S = try S.new(allocator, [5]u32{ 5, 4, 3, 2, 1 }, true, 128);
        var s2: S2 = try S2.new(allocator, s1);
        defer Destroy.destroy(s2, allocator);
    }
    {
        const U = union(enum) {
            u0: [5]u32,
            u1: bool,
            u2: f32,
            u3: ***u32,
            u4: *[]const u8,

            pub fn destroy(self: *@This()) void {
                switch (self.*) {
                    .u0, .u1, .u2 => {},
                    .u3 => |ppp| {
                        allocator.destroy(ppp.*.*);
                        allocator.destroy(ppp.*);
                        allocator.destroy(ppp);
                    },
                    .u4 => |s| {
                        allocator.free(s.*);
                        allocator.destroy(s);
                    },
                }
            }
        };

        var v0: U = .{ .u0 = [5]u32{ 0, 1, 2, 3, 4 } };
        defer Destroy.destroy(v0, allocator);
        var v1: U = .{ .u1 = true };
        defer Destroy.destroy(v1, allocator);
        var v2: U = .{ .u2 = 0.12345 };
        defer Destroy.destroy(v2, allocator);

        var s3p = try allocator.create(u32);
        s3p.* = 5;
        var s3pp = try allocator.create(*u32);
        s3pp.* = s3p;
        var s3 = try allocator.create(**u32);
        s3.* = s3pp;
        var v3: U = .{ .u3 = s3 };
        defer Destroy.destroy(v3, allocator);

        var s4s = try std.fmt.allocPrint(allocator, "{s}", .{"hello"});
        var s4 = try allocator.create([]const u8);
        s4.* = s4s;
        var v4: U = .{ .u4 = s4 };
        defer Destroy.destroy(v4, allocator);
    }
}
