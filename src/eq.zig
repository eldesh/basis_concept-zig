const std = @import("std");

const meta = @import("./meta.zig");
const trivial_eq = @import("./trivial_eq.zig");
const partial_eq = @import("./partial_eq.zig");

const trait = std.meta.trait;
const testing = std.testing;

const assert = std.debug.assert;
const have_fun = meta.have_fun;

/// Checks if type `T` satisfies the concept `Eq`.
///
/// # Details
/// Checks the type `T` satisfies at least one of the following conditions:
/// - `T` is `isTrivialEq` and is not floating point number or
/// - `T` is an Array, an Optional, a Vector or an ErrorUnion type
/// - `T` is a struct or a tagged-union type and all fields are `Eq` or
/// - `T` has an `eq` method
/// - `T` has an `eq` and a `ne` method
fn implEq(comptime T: type) bool {
    comptime {
        if (trait.is(.Float)(T))
            return false;
        if (trait.is(.ComptimeFloat)(T))
            return false;
        if (trivial_eq.isTrivialEq(T))
            return true;
        if (trait.is(.Array)(T))
            return implEq(std.meta.Child(T));
        if (trait.is(.Optional)(T))
            return implEq(std.meta.Child(T));
        if (trait.is(.Vector)(T) and trivial_eq.isTrivialEq(std.meta.Child(T)))
            return implEq(std.meta.Child(T));
        if (trait.is(.ErrorUnion)(T) and implEq(@typeInfo(T).ErrorUnion.payload))
            return true;
        if (trait.is(.Struct)(T) or trait.is(.Union)(T)) {
            if (have_fun(T, "eq")) |eq| {
                const sig = fn (*const T, *const T) bool;
                if (have_fun(T, "ne")) |ne|
                    return eq == sig and ne == sig;
                return eq == sig;
            }
            if (trait.is(.Union)(T)) {
                if (meta.tag_of(T) catch null) |tag| { // get tag of Union
                    if (!implEq(tag))
                        return false;
                } else return false;
            }
            return meta.all_field_types(T, implEq);
        }
        return false;
    }
}

comptime {
    assert(implEq(bool));
    assert(implEq(void));
    assert(implEq(@TypeOf(null)));
    assert(implEq(std.meta.Vector(4, u32)));
    assert(implEq(u32));
    assert(!implEq(struct { val: f32 }));
    assert(implEq(struct {
        val: u32,

        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return self.val == other.val;
        }
        pub fn ne(self: *const @This(), other: *const @This()) bool {
            return self.val != other.val;
        }
    }));
    assert(!implEq(f64));
    assert(!implEq(*u64));
    assert(!implEq(?f64));
    assert(!implEq(?*f64));
    assert(!implEq([]const u8));
    assert(!implEq([*]f64));
    assert(implEq([5]u32));
    assert(implEq(enum { A, B, C }));
    const U = union(enum) { Tag1, Tag2, Tag3 };
    assert(implEq(U));
    assert(!implEq(*U));
    assert(!implEq(*const U));
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
    assert(implEq(UEq));
    assert(!implEq(*UEq));
    assert(!implEq(*const UEq));
    const OverflowError = error{Overflow};
    assert(implEq(@TypeOf(.Overflow))); // EnumLiteral
    assert(implEq(OverflowError)); // ErrorSet
    assert(implEq(OverflowError![2]U)); // ErrorUnion
    assert(implEq(?(error{Overflow}![2]U)));
    assert(implEq(?(error{Overflow}![2]UEq)));
    assert(implEq(struct { val: ?(error{Overflow}![2]U) }));
    assert(implEq(struct {
        val: ?(error{Overflow}![2]UEq),
        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return Eq.eq(self, other);
        }
        pub fn ne(self: *const @This(), other: *const @This()) bool {
            return Eq.ne(self, other);
        }
    }));
    assert(!implEq(struct { val: ?(error{Overflow}![2]*const U) }));
    assert(implEq(struct {
        val: u32,
        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return self.val == other.val;
        }
        pub fn ne(self: *const @This(), other: *const @This()) bool {
            return self.val != other.val;
        }
    }));
    assert(implEq(struct {
        val: *u32,
        pub fn eq(self: *const @This(), other: *const @This()) bool {
            return self.val == other.val;
        }
        pub fn ne(self: *const @This(), other: *const @This()) bool {
            return !self.eq(other);
        }
    }));
}

/// Checks if the type `T` satisfies the concept `Eq` or
/// is a pointer type to such a type.
pub fn isEq(comptime T: type) bool {
    comptime return meta.is_or_ptrto(implEq)(T);
}

test "isEq" {
    try testing.expect(isEq(u32));
    try testing.expect(isEq(*u32));
    try testing.expect(!isEq(f32));
    try testing.expect(!isEq(*f32));
    try testing.expect(!isEq([1]*const u32));

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
    try testing.expect(!isEq([1]*const T));
}

pub const Eq = struct {
    fn eq_array(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.Array)(T));
        comptime assert(x.len == y.len);
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
        const tag = comptime meta.tag_of(T) catch unreachable;
        if (std.meta.activeTag(x) != std.meta.activeTag(y))
            return false;
        inline for (std.meta.fields(std.meta.Child(T))) |field| {
            if (@field(tag, field.name) == std.meta.activeTag(x))
                return eq_impl(&@field(x, field.name), &@field(y, field.name));
        }
        return true;
    }

    fn ne_union(comptime T: type, x: T, y: T) bool {
        comptime assert(trait.isPtrTo(.Union)(T));
        const tag = comptime meta.tag_of(T) catch unreachable;
        if (std.meta.activeTag(x) != std.meta.activeTag(y))
            return true;
        inline for (std.meta.fields(std.meta.Child(T))) |field| {
            if (@field(tag, field.name) == std.meta.activeTag(x))
                return ne_impl(&@field(x, field.name), &@field(y, field.name));
        }
        return false;
    }

    fn eq_impl(x: anytype, y: @TypeOf(x)) bool {
        const T = @TypeOf(x);
        comptime assert(trait.isSingleItemPtr(T));
        const E = std.meta.Child(T);
        comptime assert(implEq(E));

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
        comptime assert(implEq(E));

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

        if (comptime have_fun(E, "ne")) |_|
            return x.ne(y);

        if (comptime have_fun(E, "eq")) |_|
            return !x.eq(y);

        if (comptime trait.is(.Struct)(E))
            return ne_struct(T, x, y);

        if (comptime trait.is(.Union)(E))
            return ne_union(T, x, y);

        unreachable;
    }

    /// Compare the values
    ///
    /// # Details
    /// The type of values are required to satisfy `isEq`.
    pub fn eq(x: anytype, y: @TypeOf(x)) bool {
        const T = @TypeOf(x);
        comptime assert(isEq(T));

        if (comptime !trait.isSingleItemPtr(T))
            return eq_impl(&x, &y);
        return eq_impl(x, y);
    }

    pub fn ne(x: anytype, y: @TypeOf(x)) bool {
        const T = @TypeOf(x);
        comptime assert(isEq(T));

        if (comptime !trait.isSingleItemPtr(T))
            return ne_impl(&x, &y);
        return ne_impl(x, y);
    }

    /// Acquiring a type has functions `eq` and `ne` specialized for `T`.
    ///
    /// # Details
    /// Acquiring a type has functions `eq` and `ne`.
    /// These functions are specialized `Eq.eq` and `Eq.ne` for type `T`.
    ///
    /// ```
    /// const eq_T: fn (T, T) bool = Eq.on(T).eq;
    /// const ne_T: fn (T, T) bool = Eq.on(T).ne;
    /// ```
    pub fn on(comptime T: type) type {
        return struct {
            fn eq(x: T, y: T) bool {
                return Eq.eq(x, y);
            }

            fn ne(x: T, y: T) bool {
                return Eq.ne(x, y);
            }
        };
    }
};

test "Eq" {
    {
        const x: u32 = 5;
        const y: u32 = 42;
        try testing.expect(!Eq.eq(x, y));
        try testing.expect(!Eq.eq(&x, &y));
        try testing.expect(Eq.ne(x, y));
        try testing.expect(Eq.ne(&x, &y));
    }
    {
        const x: u32 = 5;
        const y: u32 = 5;
        try testing.expect(Eq.eq(x, y));
        try testing.expect(Eq.eq(&x, &y));
        try testing.expect(!Eq.ne(x, y));
        try testing.expect(!Eq.ne(&x, &y));
    }
    {
        const x: u32 = 5;
        const y: u32 = 42;
        const xp: *const u32 = &x;
        const yp: *const u32 = &y;
        try testing.expect(Eq.eq(xp, xp));
        try testing.expect(!Eq.eq(xp, yp));
        try testing.expect(!Eq.ne(xp, xp));
        try testing.expect(Eq.ne(xp, yp));
    }
    {
        const arr1 = [_]u32{ 0, 1, 2 };
        const arr2 = [_]u32{ 0, 1, 2 };
        try testing.expect(Eq.eq(arr1, arr2));
        try testing.expect(!Eq.ne(arr1, arr2));
    }
    {
        const vec1 = std.meta.Vector(4, u32){ 0, 1, 2, 3 };
        const vec2 = std.meta.Vector(4, u32){ 0, 1, 2, 4 };
        try testing.expect(Eq.eq(&vec1, &vec1));
        try testing.expect(!Eq.eq(&vec1, &vec2));
        try testing.expect(!Eq.ne(&vec1, &vec1));
        try testing.expect(Eq.ne(&vec1, &vec2));
    }
    {
        const T = struct {
            val: u32,
        };
        const x = T{ .val = 5 };
        const y = T{ .val = 5 };
        try testing.expect(Eq.eq(x, y));
        try testing.expect(!Eq.ne(x, y));
        const arr1 = [_]T{x};
        const arr2 = [_]T{y};
        try testing.expect(Eq.eq(&arr1, &arr2));
        try testing.expect(!Eq.ne(&arr1, &arr2));
        const arr11 = [1]?[1]T{@as(?[1]T, [_]T{x})};
        const arr22 = [1]?[1]T{@as(?[1]T, [_]T{y})};
        try testing.expect(Eq.eq(&arr11, &arr22));
        try testing.expect(!Eq.ne(&arr11, &arr22));
    }
    {
        const T = struct {
            val: u32,
            // impl `eq` manually
            pub fn eq(self: *const @This(), other: *const @This()) bool {
                return self.val == other.val;
            }
        };
        const x = T{ .val = 5 };
        const y = T{ .val = 5 };
        try testing.expect(Eq.eq(x, y));
        try testing.expect(!Eq.ne(x, y));
        const arr1 = [_]T{x};
        const arr2 = [_]T{y};
        try testing.expect(Eq.eq(&arr1, &arr2));
        try testing.expect(!Eq.ne(&arr1, &arr2));
        const arr11 = [1]?[1]T{@as(?[1]T, [_]T{x})};
        const arr22 = [1]?[1]T{@as(?[1]T, [_]T{y})};
        try testing.expect(Eq.eq(&arr11, &arr22));
        try testing.expect(!Eq.ne(&arr11, &arr22));
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
            // impl `ne` too
            pub fn ne(self: *const @This(), other: *const @This()) bool {
                return !self.eq(other);
            }
        };
        const x = T.new(5);
        const y = T.new(5);
        try testing.expect(Eq.eq(x, y));
        try testing.expect(!Eq.ne(x, y));
        const arr1 = [_]T{x};
        const arr2 = [_]T{y};
        try testing.expect(Eq.eq(&arr1, &arr2));
        try testing.expect(!Eq.ne(&arr1, &arr2));
        const arr11 = [1]?[1]T{@as(?[1]T, [_]T{x})};
        const arr22 = [1]?[1]T{@as(?[1]T, [_]T{y})};
        try testing.expect(Eq.eq(&arr11, &arr22));
        try testing.expect(!Eq.ne(&arr11, &arr22));
    }
}

/// Derive `eq` and `ne` of `Eq` for the type `T`
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
///   pub usingnamespace DeriveEq(@This());
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
///     if (!Eq.eq(&self.val1, &other.val1))
///       return false;
///     if (!Eq.eq(&self.val2, &other.val2))
///       return false;
///     return true;
///   }
/// }
/// ```
///
pub fn DeriveEq(comptime T: type) type {
    comptime assert(isEq(T));
    comptime assert(trait.is(.Struct)(T) or trait.is(.Union)(T));
    comptime {
        // check pre-conditions of `T`
        for (std.meta.fields(T)) |field| {
            if (!isEq(field.field_type))
                @compileError("Cannot Derive Eq for " ++ @typeName(T) ++ "." ++ field.name ++ ":" ++ @typeName(field.field_type));
            if (trait.isSingleItemPtr(field.field_type))
                @compileError("Cannot Derive Eq for " ++ @typeName(T) ++ "." ++ field.name ++ ":" ++ @typeName(field.field_type));
        }
    }
    return struct {
        pub fn eq(self: *const T, other: *const T) bool {
            if (comptime trait.is(.Struct)(T)) {
                inline for (std.meta.fields(T)) |field| {
                    if (!Eq.eq(&@field(self, field.name), &@field(other, field.name)))
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
                        return Eq.eq(&@field(self, field.name), &@field(other, field.name));
                }
                return false;
            }
            @compileError("Cannot Derive Eq for type " ++ @typeName(T));
        }

        pub fn ne(self: *const T, other: *const T) bool {
            return !eq(self, other);
        }
    };
}

test "DeriveEq" {
    {
        const T = union(enum) {
            val: u32,
            // deriving `eq`
            pub usingnamespace DeriveEq(@This());
        };
        const x: T = T{ .val = 5 };
        const y: T = T{ .val = 5 };
        try testing.expect(Eq.eq(x, y));
        try testing.expect(!Eq.ne(x, y));
    }
    {
        // contains pointer
        const T = struct {
            val: *u32,
            fn new(val: *u32) @This() {
                return .{ .val = val };
            }
            // pub usingnamespace DeriveEq(@This());
            // impl `eq` manually.
            // It is not allowed for deriving because pointer is included.
            pub fn eq(self: *const @This(), other: *const @This()) bool {
                return self.val.* == other.val.*;
            }
            pub fn ne(self: *const @This(), other: *const @This()) bool {
                return self.val.* != other.val.*;
            }
        };
        var v0 = @as(u32, 5);
        var v1 = @as(u32, 5);
        const x = T.new(&v0);
        const y = T.new(&v1);
        try testing.expect(Eq.eq(x, y));
        try testing.expect(!Eq.ne(x, y));
    }
    {
        // tagged union
        const E = union(enum) {
            A,
            B,
            C,
            pub usingnamespace DeriveEq(@This());
        };
        // complex type
        const T = struct {
            val: ?(error{Err}![2]E),
            pub usingnamespace DeriveEq(@This());
        };
        try testing.expect(Eq.eq(T{ .val = null }, T{ .val = null }));
        try testing.expect(Eq.eq(T{ .val = error.Err }, T{ .val = error.Err }));
        try testing.expect(Eq.eq(T{ .val = [_]E{ .A, .B } }, T{ .val = [_]E{ .A, .B } }));
        try testing.expect(Eq.eq(&T{ .val = null }, &T{ .val = null }));
        try testing.expect(Eq.eq(&T{ .val = error.Err }, &T{ .val = error.Err }));
        try testing.expect(Eq.eq(&T{ .val = [_]E{ .A, .B } }, &T{ .val = [_]E{ .A, .B } }));
        try testing.expect(!Eq.eq(T{ .val = [_]E{ .A, .B } }, T{ .val = [_]E{ .A, .C } }));
        try testing.expect(!Eq.eq(T{ .val = [_]E{ .A, .B } }, T{ .val = error.Err }));

        // ne
        try testing.expect(!Eq.ne(T{ .val = null }, T{ .val = null }));
        try testing.expect(!Eq.ne(T{ .val = error.Err }, T{ .val = error.Err }));
        try testing.expect(!Eq.ne(T{ .val = [_]E{ .A, .B } }, T{ .val = [_]E{ .A, .B } }));
        try testing.expect(!Eq.ne(&T{ .val = null }, &T{ .val = null }));
        try testing.expect(!Eq.ne(&T{ .val = error.Err }, &T{ .val = error.Err }));
        try testing.expect(!Eq.ne(&T{ .val = [_]E{ .A, .B } }, &T{ .val = [_]E{ .A, .B } }));
        try testing.expect(Eq.ne(T{ .val = [_]E{ .A, .B } }, T{ .val = [_]E{ .A, .C } }));
        try testing.expect(Eq.ne(T{ .val = [_]E{ .A, .B } }, T{ .val = error.Err }));
    }
}