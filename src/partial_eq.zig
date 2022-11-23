const std = @import("std");

const meta = @import("./meta.zig");
const trivial_eq = @import("./trivial_eq.zig");

const trait = std.meta.trait;
const testing = std.testing;

const assert = std.debug.assert;
const have_fun_sig = meta.have_fun_sig;

/// Checks if type `T` satisfies the concept `PartialEq`.
///
/// # Details
/// Checks the type `T` satisfies at least one of the following conditions:
/// - `T` is `isTrivialEq` or
/// - `T` is an Array, an Optional, a Vector or an ErrorUnion type
/// - `T` is a struct or tagged-union type and all fields are `PartialEq` or
/// - `T` has an `eq` and a `ne` method
fn implPartialEq(comptime T: type) bool {
    comptime {
        return switch (@typeInfo(T)) {
            .Int, .Float, .ComptimeInt, .ComptimeFloat, .Void, .Bool, .Null, .EnumLiteral, .ErrorSet => true,
            .Enum => |Enum| implPartialEq(Enum.tag_type),
            .Array, .Optional => implPartialEq(std.meta.Child(T)),
            .Vector => trivial_eq.isTrivialEq(std.meta.Child(T)) and implPartialEq(std.meta.Child(T)),
            .ErrorUnion => |ErrorUnion| implPartialEq(ErrorUnion.payload),
            .Struct, .Union => {
                const sig = fn (*const T, *const T) bool;
                // only one of 'eq' and 'ne' is implemented
                if (have_fun_sig(T, "eq", sig) != have_fun_sig(T, "ne", sig))
                    return false;
                // both 'eq' and 'ne' are implemented
                if (have_fun_sig(T, "eq", sig) and have_fun_sig(T, "ne", sig))
                    return true;
                if (trait.is(.Union)(T)) {
                    if (if (meta.tag_of(T) catch null) |tag| !implPartialEq(tag) else true)
                        return false;
                }
                return meta.all_field_types(T, implPartialEq);
            },
            else => false,
        };
    }
}

comptime {
    assert(implPartialEq(bool));
    assert(implPartialEq(void));
    assert(implPartialEq(@TypeOf(null)));
    assert(implPartialEq(std.meta.Vector(4, u32)));
    assert(implPartialEq(u32));
    assert(implPartialEq(struct { val: f32 }));
    assert(implPartialEq(struct {
        val: u32,

        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return self.val == other.val;
        }
        pub fn ne(self: *const @This(), other: *const @This()) bool {
            return !self.eq(other);
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
    assert(implPartialEq(U));
    assert(!implPartialEq(*U));
    assert(!implPartialEq(*const U));
    const UEq = union(enum) {
        Tag1,
        Tag2,
        Tag3,
        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return std.meta.activeTag(self.*) == std.meta.activeTag(other.*);
        }
        pub fn ne(self: *const @This(), other: *const @This()) bool {
            return !self.eq(other);
        }
    };
    assert(implPartialEq(UEq));
    assert(!implPartialEq(*UEq));
    assert(!implPartialEq(*const UEq));
    const OverflowError = error{Overflow};
    assert(implPartialEq(@TypeOf(.Overflow))); // EnumLiteral
    assert(implPartialEq(OverflowError)); // ErrorSet
    assert(implPartialEq(OverflowError![2]U)); // ErrorUnion
    assert(implPartialEq(?(error{Overflow}![2]U)));
    assert(implPartialEq(?(error{Overflow}![2]UEq)));
    assert(implPartialEq(struct { val: ?(error{Overflow}![2]U) }));
    assert(implPartialEq(struct {
        val: ?(error{Overflow}![2]UEq),
        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return PartialEq.eq(self, other);
        }
        pub fn ne(self: *const @This(), other: *const @This()) bool {
            return !self.eq(other);
        }
    }));
    assert(!implPartialEq(struct { val: ?(error{Overflow}![2]*const U) }));
    assert(implPartialEq(struct {
        val: u32,
        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return self.val == other.val;
        }
        pub fn ne(self: *const @This(), other: *const @This()) bool {
            return self.val != other.val;
        }
    }));
    assert(implPartialEq(struct {
        val: *u32,
        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return self.val == other.val;
        }
        pub fn ne(self: *const @This(), other: *const @This()) bool {
            return self.val != other.val;
        }
    }));
}

/// Checks if the type `T` satisfies the concept `PartialEq` or
/// is a pointer type to such a type.
pub fn isPartialEq(comptime T: type) bool {
    comptime return meta.is_or_ptrto(implPartialEq)(T);
}

test "isPartialEq" {
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
        pub fn ne(self: *const @This(), other: *const @This()) bool {
            return !self.eq(other);
        }
    };
    try testing.expect(isPartialEq(T));
    try testing.expect(isPartialEq(*const [2]T));
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

    fn ne_array(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.Array)(T));
        comptime assert(x.len == y.len);
        for (x) |xv, i| {
            if (ne_impl(&xv, &y[i]))
                return true;
        }
        return false;
    }

    fn eq_optional(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.Optional)(T));
        if (x.*) |xv| {
            return if (y.*) |yv| eq_impl(&xv, &yv) else false;
        } else {
            return y.* == null;
        }
    }

    fn ne_optional(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.Optional)(T));
        if (x.*) |xv| {
            return if (y.*) |yv| ne_impl(&xv, &yv) else true;
        } else {
            return y.* != null;
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

    fn ne_vector(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.Vector)(T));
        var i: usize = 0;
        while (i < @typeInfo(std.meta.Child(T)).Vector.len) : (i += 1) {
            if (x.*[i] != y.*[i])
                return true;
        }
        return false;
    }

    fn eq_error_union(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.ErrorUnion)(T));
        if (x.*) |xv| {
            return if (y.*) |yv| eq_impl(&xv, &yv) else |_| false;
        } else |xv| {
            return if (y.*) |_| false else |yv| xv == yv;
        }
    }

    fn ne_error_union(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.ErrorUnion)(T));
        if (x.*) |xv| {
            return if (y.*) |yv| ne_impl(&xv, &yv) else |_| true;
        } else |xv| {
            return if (y.*) |_| true else |yv| xv != yv;
        }
    }

    fn eq_struct(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.Struct)(T));
        inline for (std.meta.fields(std.meta.Child(T))) |field| {
            if (!eq_impl(&@field(x, field.name), &@field(y, field.name)))
                return false;
        }
        return true;
    }

    fn ne_struct(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.Struct)(T));
        inline for (std.meta.fields(std.meta.Child(T))) |field| {
            if (ne_impl(&@field(x, field.name), &@field(y, field.name)))
                return true;
        }
        return false;
    }

    fn eq_union(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.Union)(T));
        const tag = comptime (meta.tag_of(std.meta.Child(T)) catch unreachable).?;
        if (std.meta.activeTag(x.*) != std.meta.activeTag(y.*))
            return false;
        inline for (std.meta.fields(std.meta.Child(T))) |field| {
            if (@field(tag, field.name) == std.meta.activeTag(x.*))
                return eq_impl(&@field(x, field.name), &@field(y, field.name));
        }
        return true;
    }

    fn ne_union(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.Union)(T));
        const tag = comptime (meta.tag_of(std.meta.Child(T)) catch unreachable).?;
        if (std.meta.activeTag(x.*) != std.meta.activeTag(y.*))
            return true;
        inline for (std.meta.fields(std.meta.Child(T))) |field| {
            if (@field(tag, field.name) == std.meta.activeTag(x.*))
                return ne_impl(&@field(x, field.name), &@field(y, field.name));
        }
        return false;
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

        if (comptime meta.have_fun(E, "eq")) |_|
            return x.eq(y);

        if (comptime trait.is(.Struct)(E))
            return eq_struct(T, x, y);

        if (comptime trait.is(.Union)(E))
            return eq_union(T, x, y);

        unreachable;
    }

    fn ne_impl(x: anytype, y: @TypeOf(x)) bool {
        const T = @TypeOf(x);
        comptime assert(trait.isSingleItemPtr(T));
        const E = std.meta.Child(T);
        comptime assert(implPartialEq(E));

        if (comptime trivial_eq.isTrivialEq(E))
            return x.* != y.*;

        if (comptime trait.is(.Array)(E))
            return ne_array(T, x, y);

        if (comptime trait.is(.Optional)(E))
            return ne_optional(T, x, y);

        if (comptime trait.is(.Vector)(E))
            return ne_vector(T, x, y);

        if (comptime trait.is(.ErrorUnion)(E))
            return ne_error_union(T, x, y);

        if (comptime meta.have_fun(E, "ne")) |_|
            return x.ne(y);

        if (comptime trait.is(.Struct)(E))
            return ne_struct(T, x, y);

        if (comptime trait.is(.Union)(E))
            return ne_union(T, x, y);

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
        const T = @TypeOf(x);
        comptime assert(isPartialEq(T));

        if (comptime !trait.isSingleItemPtr(T))
            return ne_impl(&x, &y);
        return ne_impl(x, y);
    }

    /// Acquiring a type has functions `eq` and `ne` specialized for `T`.
    ///
    /// # Details
    /// Acquiring a type has functions `eq` and `ne`.
    /// These functions are specialized `PartialEq.eq` and `PartialEq.ne` for type `T`.
    ///
    /// ```
    /// const eq_T: fn (T, T) bool = PartialEq.on(T).eq;
    /// const ne_T: fn (T, T) bool = PartialEq.on(T).ne;
    /// ```
    pub fn on(comptime T: type) type {
        return struct {
            fn eq(x: T, y: T) bool {
                return PartialEq.eq(x, y);
            }

            fn ne(x: T, y: T) bool {
                return PartialEq.ne(x, y);
            }
        };
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
        const S = union(enum) {
            val1: u32, // same type to typeof(val2)
            val2: u32,
        };
        const s1 = S{ .val1 = 42 };
        const s2 = S{ .val1 = 314 };
        try testing.expect(PartialEq.eq(&s1, &s1));
        try testing.expect(!PartialEq.ne(&s1, &s1));
        try testing.expect(!PartialEq.eq(&s1, &s2));
        try testing.expect(PartialEq.ne(&s1, &s2));
    }
    {
        const S = union(enum) {
            val1: u32,
            val2: [3]u8,
        };
        const s1 = S{ .val1 = 42 };
        const s2 = S{ .val2 = [_]u8{ 1, 2, 3 } };
        try testing.expect(PartialEq.eq(&s1, &s1));
        try testing.expect(!PartialEq.ne(&s1, &s1));
        try testing.expect(!PartialEq.eq(&s1, &s2));
        try testing.expect(PartialEq.ne(&s1, &s2));
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
            pub fn ne(self: *const @This(), other: *const @This()) bool {
                return self.val != other.val;
            }
        };
        const x = T.new(5);
        const y = T.new(5);
        try testing.expect(PartialEq.eq(x, y));
        try testing.expect(!PartialEq.ne(x, y));
        const arr1 = [_]T{x};
        const arr2 = [_]T{y};
        try testing.expect(PartialEq.eq(&arr1, &arr2));
        try testing.expect(!PartialEq.ne(&arr1, &arr2));
        const arr11 = [1]?[1]T{@as(?[1]T, [_]T{x})};
        const arr22 = [1]?[1]T{@as(?[1]T, [_]T{y})};
        try testing.expect(PartialEq.eq(&arr11, &arr22));
        try testing.expect(!PartialEq.ne(&arr11, &arr22));
    }
}

/// Derive `eq` and `ne` of `PartialEq` for the type `T`
///
/// # Details
/// For type `T` which is struct or tagged union type, derive `eq` method.
/// The signature of that method should be `fn (self: *const T, other: *const T) bool`.
///
/// This function should be used like below:
///
/// ```
/// struct {
///   val1: type1, // must not be pointer type
///   val2: type2, // must not be pointer type
///   pub usingnamespace DerivePartialEq(@This());
/// }
/// ```
///
/// This definition declares the type have `eq` method same as below declaration:
///
/// ```
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
///   pub fn ne(self: *const @This(), other: *const @This()) bool {
///     return !self.eq(other);
///   }
/// }
/// ```
///
pub fn DerivePartialEq(comptime T: type) type {
    comptime {
        assert(trait.is(.Struct)(T) or trait.is(.Union)(T));
        // check pre-conditions of `T`
        for (std.meta.fields(T)) |field| {
            if (!isPartialEq(field.field_type))
                @compileError("Cannot Derive PartialEq for " ++ @typeName(T) ++ "::" ++ @typeName(field.field_type) ++ ":" ++ field.name);
            if (trait.isSingleItemPtr(field.field_type))
                @compileError("Cannot Derive PartialEq for " ++ @typeName(T) ++ "::" ++ @typeName(field.field_type) ++ ":" ++ field.name);
        }
        return struct {
            pub usingnamespace if (meta.have_fun(T, "eq")) |_|
                struct {}
            else
                derive_partial_eq(T);
            pub usingnamespace derive_partial_ne(T);
        };
    }
}

fn derive_partial_eq(comptime T: type) type {
    return struct {
        pub fn eq(self: *const T, other: *const T) bool {
            if (comptime trait.is(.Struct)(T)) {
                inline for (std.meta.fields(T)) |field| {
                    if (!PartialEq.eq(&@field(self, field.name), &@field(other, field.name)))
                        return false;
                }
                return true;
            }
            if (comptime trait.is(.Union)(T)) {
                const tag = comptime @typeInfo(T).Union.tag_type.?;
                const self_tag = std.meta.activeTag(self.*);
                const other_tag = std.meta.activeTag(other.*);
                if (self_tag != other_tag) return false;

                inline for (std.meta.fields(T)) |field| {
                    if (@field(tag, field.name) == self_tag)
                        return PartialEq.eq(&@field(self, field.name), &@field(other, field.name));
                }
                return true;
            }
            @compileError("Cannot Derive PartialEq.eq for type " ++ @typeName(T));
        }
    };
}

// Derive a 'ne' function that uses `eq` for consistency.
fn derive_partial_ne(comptime T: type) type {
    return struct {
        pub fn ne(self: *const T, other: *const T) bool {
            return !self.eq(other);
        }
    };
}

test "DerivePartialEq" {
    {
        const T = union(enum) {
            val: u32,
            // deriving `eq` and `ne`
            pub usingnamespace DerivePartialEq(@This());
        };
        const x: T = T{ .val = 5 };
        const y: T = T{ .val = 5 };
        try testing.expect(PartialEq.eq(x, y));
        try testing.expect(!PartialEq.ne(x, y));
    }
    {
        const T = union(enum) {
            val: u32,
            pub fn eq(self: *const @This(), other: *const @This()) bool {
                return self.val / 2 == other.val / 2;
            }
            // deriving `ne`
            pub usingnamespace DerivePartialEq(@This());
        };
        const x: T = T{ .val = 4 };
        const y: T = T{ .val = 5 };
        // 4/2 = 2 = 5/2
        try testing.expect(PartialEq.eq(x, y));
        // !eq(x, y)
        try testing.expect(!PartialEq.ne(x, y));
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
            pub fn ne(self: *const @This(), other: *const @This()) bool {
                return !self.eq(other);
            }
        };
        var v0 = @as(u32, 5);
        var v1 = @as(u32, 5);
        const x = T.new(&v0);
        const y = T.new(&v1);
        try testing.expect(PartialEq.eq(x, y));
        try testing.expect(!PartialEq.ne(x, y));
    }
    {
        // tagged union
        const E: type = union(enum) {
            A,
            B,
            C,
            pub usingnamespace DerivePartialEq(@This());
        };
        comptime try testing.expect(isPartialEq(E));
        const ea: E = E{ .A = void{} };
        try testing.expect((E{ .A = void{} }).eq(&E{ .A = void{} }));
        try testing.expect(!ea.ne(&ea));
        try testing.expect(PartialEq.eq(ea, ea));
        try testing.expect(PartialEq.eq(E.A, E.A));
        try testing.expect(PartialEq.ne(E.A, E.B));

        // complex type
        const T = struct {
            val: ?(error{Err}![2]E),
            pub usingnamespace DerivePartialEq(@This());
        };
        comptime try testing.expect(isPartialEq(?(error{Err}![2]E)));
        comptime try testing.expect(isPartialEq(T));
        try testing.expect(PartialEq.eq(T{ .val = null }, T{ .val = null }));
        try testing.expect(PartialEq.eq(T{ .val = error.Err }, T{ .val = error.Err }));
        try testing.expect(PartialEq.eq(T{ .val = [_]E{ .A, .B } }, T{ .val = [_]E{ .A, .B } }));
        try testing.expect(PartialEq.eq(&T{ .val = null }, &T{ .val = null }));
        try testing.expect(PartialEq.eq(&T{ .val = error.Err }, &T{ .val = error.Err }));
        try testing.expect(PartialEq.eq(&T{ .val = [_]E{ .A, .B } }, &T{ .val = [_]E{ .A, .B } }));
        try testing.expect(!PartialEq.eq(T{ .val = [_]E{ .A, .B } }, T{ .val = [_]E{ .A, .C } }));
        try testing.expect(!PartialEq.eq(T{ .val = [_]E{ .A, .B } }, T{ .val = error.Err }));

        try testing.expect(!PartialEq.ne(T{ .val = null }, T{ .val = null }));
        try testing.expect(!PartialEq.ne(T{ .val = error.Err }, T{ .val = error.Err }));
        try testing.expect(!PartialEq.ne(T{ .val = [_]E{ .A, .B } }, T{ .val = [_]E{ .A, .B } }));
        try testing.expect(!PartialEq.ne(&T{ .val = null }, &T{ .val = null }));
        try testing.expect(!PartialEq.ne(&T{ .val = error.Err }, &T{ .val = error.Err }));
        try testing.expect(!PartialEq.ne(&T{ .val = [_]E{ .A, .B } }, &T{ .val = [_]E{ .A, .B } }));
        try testing.expect(PartialEq.ne(T{ .val = [_]E{ .A, .B } }, T{ .val = [_]E{ .A, .C } }));
        try testing.expect(PartialEq.ne(T{ .val = [_]E{ .A, .B } }, T{ .val = error.Err }));
    }
}
