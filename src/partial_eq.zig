const std = @import("std");

const meta = @import("./meta.zig");
const trivial_eq = @import("./trivial_eq.zig");

const trait = std.meta.trait;
const testing = std.testing;

const math = std.math;
const assert = std.debug.assert;
const is_or_ptrto = meta.is_or_ptrto;
const have_type = meta.have_type;
const have_fun = meta.have_fun;

fn implPartialEq(comptime T: type) bool {
    comptime {
        if (trivial_eq.isTrivialEq(T))
            return true;
        if (trait.is(.Array)(T) or trait.is(.Optional)(T))
            return implPartialEq(std.meta.Child(T));
        if (trait.is(.Vector)(T) and trivial_eq.isTrivialEq(std.meta.Child(T)))
            return implPartialEq(std.meta.Child(T));
        if (trait.is(.ErrorUnion)(T) and implPartialEq(@typeInfo(T).ErrorUnion.payload))
            return true;
        if (have_fun(T, "eq")) |ty|
            return ty == fn (*const T, *const T) bool;
        return false;
    }
}

comptime {
    assert(implPartialEq(bool));
    assert(implPartialEq(void));
    assert(implPartialEq(@TypeOf(null)));
    assert(implPartialEq(std.meta.Vector(4, u32)));
    assert(implPartialEq(u32));
    assert(!implPartialEq(struct { val: f32 }));
    assert(implPartialEq(struct {
        val: u32,

        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return self.val == other.val;
        }
    }));
    assert(implPartialEq(f64));
    assert(!implPartialEq(*u64));
    assert(implPartialEq(?f64));
    assert(!implPartialEq(?*f64));
    assert(!implPartialEq([]const u8));
    assert(!implPartialEq([*]f64));
    assert(implPartialEq([5]u32));
    assert(implPartialEq(enum { A, B, C }));
    const U = union(enum) { Tag1, Tag2, Tag3 };
    assert(!implPartialEq(U));
    assert(!implPartialEq(*U));
    assert(!implPartialEq(*const U));
    const UEq = union(enum) {
        Tag1,
        Tag2,
        Tag3,
        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return std.meta.activeTag(self.*) == std.meta.activeTag(other.*);
        }
    };
    assert(implPartialEq(UEq));
    assert(!implPartialEq(*UEq));
    assert(!implPartialEq(*const UEq));
    const OverflowError = error{Overflow};
    assert(implPartialEq(@TypeOf(.Overflow))); // EnumLiteral
    assert(implPartialEq(OverflowError)); // ErrorSet
    assert(!implPartialEq(OverflowError![2]U)); // ErrorUnion
    assert(!implPartialEq(?(error{Overflow}![2]U)));
    assert(implPartialEq(?(error{Overflow}![2]UEq)));
    assert(!implPartialEq(struct { val: ?(error{Overflow}![2]U) }));
    assert(implPartialEq(struct {
        val: ?(error{Overflow}![2]UEq),
        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return PartialEq.eq(self, other);
        }
    }));
    assert(!implPartialEq(struct { val: ?(error{Overflow}![2]*const U) }));
    assert(implPartialEq(struct {
        val: u32,
        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return self.val == other.val;
        }
    }));
    assert(implPartialEq(struct {
        val: *u32,
        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return self.val == other.val;
        }
    }));
}

pub fn isPartialEq(comptime T: type) bool {
    comptime return is_or_ptrto(implPartialEq)(T);
}

test "isPartialeq" {
    try testing.expect(isPartialEq(u32));
    try testing.expect(isPartialEq(*u32));
    try testing.expect(isPartialEq(f32));
    try testing.expect(isPartialEq(*f32));
    try testing.expect(!isPartialEq([1]*const u32));

    const T = struct {
        val: u32,
        fn new(val: u32) @This() {
            return .{ .val = val };
        }
        // impl `eq` manually
        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return self.val == other.val;
        }
    };
    try testing.expect(!isPartialEq([1]*const T));
}

pub const PartialEq = struct {
    fn eq_array(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.Array)(T));
        if (x.len != y.len)
            return false;
        for (x) |xv, i| {
            if (!eq_impl(&xv, &y[i]))
                return false;
        }
        return true;
    }

    fn eq_optional(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.Optional)(T));
        if (x.*) |xv| {
            return if (y.*) |yv| eq_impl(&xv, &yv) else false;
        } else {
            return y.* == null;
        }
    }

    fn eq_vector(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.Vector)(T));
        var i: usize = 0;
        while (i < @typeInfo(std.meta.Child(T)).Vector.len) : (i += 1) {
            if (x.*[i] != y.*[i])
                return false;
        }
        return true;
    }

    fn eq_error_union(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.ErrorUnion)(T));
        if (x.*) |xv| {
            return if (y.*) |yv| eq_impl(&xv, &yv) else |_| false;
        } else |xv| {
            return if (y.*) |_| false else |yv| xv == yv;
        }
    }

    fn eq_impl(x: anytype, y: @TypeOf(x)) bool {
        const T = @TypeOf(x);
        comptime assert(trait.isSingleItemPtr(T));
        const E = std.meta.Child(T);
        comptime assert(implPartialEq(E));

        if (comptime trivial_eq.isTrivialEq(E))
            return x.* == y.*;

        if (comptime trait.is(.Array)(E))
            return eq_array(T, x, y);

        if (comptime trait.is(.Optional)(E))
            return eq_optional(T, x, y);

        if (comptime trait.is(.Vector)(E))
            return eq_vector(T, x, y);

        if (comptime trait.is(.ErrorUnion)(E))
            return eq_error_union(T, x, y);

        if (comptime have_fun(E, "eq")) |_|
            return x.eq(y);

        unreachable;
    }

    /// Compare the values
    ///
    /// # Details
    /// The type of values are required to satisfy `isPartialEq`.
    pub fn eq(x: anytype, y: @TypeOf(x)) bool {
        const T = @TypeOf(x);
        comptime assert(isPartialEq(T));

        if (comptime !trait.isSingleItemPtr(T))
            return eq_impl(&x, &y);
        return eq_impl(x, y);
    }

    pub fn ne(x: anytype, y: @TypeOf(x)) bool {
        return !eq(x, y);
    }
};

test "PartialEq" {
    {
        const x: u32 = 5;
        const y: u32 = 42;
        try testing.expect(!PartialEq.eq(x, y));
        try testing.expect(!PartialEq.eq(&x, &y));
    }
    {
        const x: u32 = 5;
        const y: u32 = 5;
        try testing.expect(PartialEq.eq(x, y));
        try testing.expect(PartialEq.eq(&x, &y));
    }
    {
        const x: u32 = 5;
        const y: u32 = 42;
        const xp: *const u32 = &x;
        const yp: *const u32 = &y;
        try testing.expect(PartialEq.eq(xp, xp));
        try testing.expect(!PartialEq.eq(xp, yp));
    }
    {
        const arr1 = [_]u32{ 0, 1, 2 };
        const arr2 = [_]u32{ 0, 1, 2 };
        try testing.expect(PartialEq.eq(arr1, arr2));
    }
    {
        const vec1 = std.meta.Vector(4, u32){ 0, 1, 2, 3 };
        const vec2 = std.meta.Vector(4, u32){ 0, 1, 2, 4 };
        try testing.expect(PartialEq.eq(&vec1, &vec1));
        try testing.expect(!PartialEq.eq(&vec1, &vec2));
    }
    {
        const T = struct {
            val: u32,
            fn new(val: u32) @This() {
                return .{ .val = val };
            }
            // impl `eq` manually
            pub fn eq(self: *const @This(), other: *const @This()) bool {
                return self.val == other.val;
            }
        };
        const x = T.new(5);
        const y = T.new(5);
        try testing.expect(PartialEq.eq(x, y));
        const arr1 = [_]T{x};
        const arr2 = [_]T{y};
        try testing.expect(PartialEq.eq(&arr1, &arr2));
        const arr11 = [1]?[1]T{@as(?[1]T, [_]T{x})};
        const arr22 = [1]?[1]T{@as(?[1]T, [_]T{y})};
        try testing.expect(PartialEq.eq(&arr11, &arr22));
    }
}

/// Derive `eq` of `PartialEq` for the type `T`
///
/// # Details
/// For type `T` which is struct or tagged union type, derive `eq` method.
/// The signature of that method should be `fn (self: *const T, other: *const T) bool`.
///
/// This function should be used like below:
/// ```zig
/// struct {
///   val1: type1, // must not be pointer type
///   val2: type2, // must not be pointer type
///   pub usingnamespace DerivePartialEq(@This());
/// }
/// ```
///
/// This definition declares the type have `eq` method same as below declaration:
/// ```zig
/// struct {
///   val1: type1,
///   val2: type2,
///   pub fn eq(self: *const @This(), other: *const @This()) bool {
///     if (!PartialEq.eq(&self.val1, &other.val1))
///       return false;
///     if (!PartialEq.eq(&self.val2, &other.val2))
///       return false;
///     return true;
///   }
/// }
/// ```
///
pub fn DerivePartialEq(comptime T: type) type {
    comptime assert(trait.is(.Struct)(T) or trait.is(.Union)(T));
    return struct {
        pub fn eq(self: *const T, other: *const T) bool {
            if (comptime trait.is(.Struct)(T)) {
                inline for (std.meta.fields(T)) |field| {
                    if (comptime trait.isSingleItemPtr(field.field_type))
                        @compileError("Cannot Derive PartialEq for " ++ @typeName(T) ++ "." ++ field.name ++ ":" ++ @typeName(field.field_type));
                    if (!PartialEq.eq(&@field(self, field.name), &@field(other, field.name)))
                        return false;
                }
                return true;
            }
            if (comptime trait.is(.Union)(T)) {
                if (@typeInfo(T).Union.tag_type == null)
                    @compileError("Cannot Derive PartialEq for untagged union type " ++ @typeName(T));

                const tag = @typeInfo(T).Union.tag_type.?;
                const self_tag = std.meta.activeTag(self.*);
                const other_tag = std.meta.activeTag(other.*);
                if (self_tag != other_tag) return false;

                inline for (std.meta.fields(T)) |field| {
                    if (comptime trait.isSingleItemPtr(field.field_type))
                        @compileError("Cannot Derive PartialEq for " ++ @typeName(T) ++ "." ++ field.name ++ ":" ++ @typeName(field.field_type));
                    if (@field(tag, field.name) == self_tag)
                        return PartialEq.eq(&@field(self, field.name), &@field(other, field.name));
                }
                return false;
            }
            @compileError("Cannot Derive PartialEq for type " ++ @typeName(T));
        }

        pub fn ne(self: *const T, other: *const T) bool {
            return !eq(self, other);
        }
    };
}

test "DerivePartialEq" {
    {
        const T = union(enum) {
            val: u32,
            // deriving `eq`
            pub usingnamespace DerivePartialEq(@This());
        };
        const x: T = T{ .val = 5 };
        const y: T = T{ .val = 5 };
        try testing.expect(PartialEq.eq(x, y));
    }
    {
        // contains pointer
        const T = struct {
            val: *u32,
            fn new(val: *u32) @This() {
                return .{ .val = val };
            }
            // pub usingnamespace DerivePartialEq(@This());
            // impl `eq` manually.
            // It is not allowed for deriving because pointer is included.
            pub fn eq(self: *const @This(), other: *const @This()) bool {
                return self.val.* == other.val.*;
            }
        };
        var v0 = @as(u32, 5);
        var v1 = @as(u32, 5);
        const x = T.new(&v0);
        const y = T.new(&v1);
        try testing.expect(PartialEq.eq(x, y));
    }
    {
        // tagged union
        const E = union(enum) {
            A,
            B,
            C,
            pub usingnamespace DerivePartialEq(@This());
        };
        // complex type
        const T = struct {
            val: ?(error{Err}![2]E),
            pub usingnamespace DerivePartialEq(@This());
        };
        try testing.expect(PartialEq.eq(T{ .val = null }, T{ .val = null }));
        try testing.expect(PartialEq.eq(T{ .val = error.Err }, T{ .val = error.Err }));
        try testing.expect(PartialEq.eq(T{ .val = [_]E{ .A, .B } }, T{ .val = [_]E{ .A, .B } }));
        try testing.expect(!PartialEq.eq(T{ .val = [_]E{ .A, .B } }, T{ .val = [_]E{ .A, .C } }));
        try testing.expect(!PartialEq.eq(T{ .val = [_]E{ .A, .B } }, T{ .val = error.Err }));
    }
}
