const std = @import("std");

const meta = @import("./meta.zig");
const partial_ord = @import("./partial_ord.zig");

const trait = std.meta.trait;
const testing = std.testing;

const assert = std.debug.assert;

fn implOrd(comptime T: type) bool {
    comptime {
        return switch (@typeInfo(T)) {
            .Void, .Bool, .Null, .EnumLiteral, .ErrorSet, .Int, .ComptimeInt => true,
            .Float, .ComptimeFloat => false,
            .Array, .Optional => implOrd(std.meta.Child(T)),
            .Enum => |Enum| implOrd(Enum.tag_type),
            .ErrorUnion => |ErrorUnion| implOrd(ErrorUnion.error_set) and implOrd(ErrorUnion.payload),
            .Struct => {
                if (meta.have_fun(T, "cmp")) |cmp|
                    return cmp == fn (*const T, *const T) std.math.Order;
                return meta.all_field_types(T, implOrd);
            },
            .Union => |Union| {
                if (meta.have_fun(T, "cmp")) |cmp|
                    return cmp == fn (*const T, *const T) std.math.Order;
                if (Union.tag_type) |tag| {
                    if (!implOrd(tag))
                        return false;
                }
                return meta.all_field_types(T, implOrd);
            },
            else => false,
        };
    }
}

pub fn isOrd(comptime T: type) bool {
    comptime return meta.is_or_ptrto(implOrd)(T);
}

comptime {
    assert(isOrd(u32));
    assert(isOrd(*u32));
    assert(!isOrd([]u32));
    assert(!isOrd([*]u32));
    assert(isOrd(i64));
    assert(isOrd(*const i64));
    assert(!isOrd(*[]const i64));
    assert(isOrd([8]u64));
    assert(!isOrd(f64));
    assert(!isOrd(f32));
    assert(!isOrd(@Vector(4, u32)));
    assert(!isOrd(@Vector(4, f64)));
    const unit = struct {};
    assert(isOrd(unit));
    assert(isOrd(*unit));
    assert(isOrd(*const unit));
    const C = struct {
        val: u32,
        pub fn partial_cmp(x: *const @This(), y: *const @This()) ?std.math.Order {
            _ = x;
            _ = y;
            return null;
        }
        pub fn cmp(x: *const @This(), y: *const @This()) std.math.Order {
            _ = x;
            _ = y;
            return .lt;
        }
    };
    assert(isOrd(C));
    assert(isOrd(*C));
    const D = struct {
        val: u32,
        // signature of `cmp` is not matches to
        // `fn (*const T, *const T) Order`.
        pub fn cmp(x: @This(), y: @This()) std.math.Order {
            _ = x;
            _ = y;
            return .lt;
        }
    };
    assert(!isOrd(D)); // `cmp` is not implemented
    assert(!isOrd(*D));
}

pub const Ord = struct {
    fn cmp_bool(x: bool, y: bool) std.math.Order {
        if (x == y)
            return .eq;
        return if (y) .lt else .gt;
    }

    fn cmp_array(comptime T: type, x: T, y: T) std.math.Order {
        comptime assert(trait.isPtrTo(.Array)(T));
        for (x) |xv, i| {
            switch (cmp_impl(&xv, &y[i])) {
                .lt, .gt => |ord| return ord,
                .eq => {},
            }
        }
        return .eq;
    }

    fn cmp_optional(comptime T: type, x: T, y: T) std.math.Order {
        comptime assert(trait.isPtrTo(.Optional)(T));
        if (x.*) |xv| {
            return if (y.*) |yv| cmp_impl(&xv, &yv) else .gt;
        } else {
            return if (y.*) |_| .lt else .eq;
        }
    }

    fn cmp_enum(comptime T: type, x: T, y: T) std.math.Order {
        comptime assert(trait.isPtrTo(.Enum)(T));
        return std.math.order(@enumToInt(x.*), @enumToInt(y.*));
    }

    fn cmp_struct(comptime T: type, x: T, y: T) std.math.Order {
        comptime assert(trait.isPtrTo(.Struct)(T));
        inline for (comptime std.meta.fields(std.meta.Child(T))) |field| {
            const o = cmp_impl(&@field(x, field.name), &@field(y, field.name));
            if (o.compare(.ne))
                return o;
        }
        return std.math.Order.eq;
    }

    fn cmp_impl(x: anytype, y: @TypeOf(x)) std.math.Order {
        const T = @TypeOf(x);
        comptime assert(trait.isSingleItemPtr(T));
        const E = std.meta.Child(T);
        comptime assert(implOrd(E));

        if (comptime trait.is(.Void)(E))
            return .eq;
        if (comptime trait.is(.Bool)(E))
            return cmp_bool(x.*, y.*);
        if (comptime trait.is(.Null)(E))
            return .eq;
        if (comptime trait.is(.Array)(E))
            return cmp_array(T, x, y);
        if (comptime trait.is(.Optional)(E))
            return cmp_optional(T, x, y);
        if (comptime trait.is(.Enum)(E))
            return cmp_enum(T, x, y);
        if (comptime trait.isIntegral(E))
            return std.math.order(x.*, y.*);
        if (comptime meta.have_fun(T, "cmp")) |_|
            return x.cmp(y);
        if (comptime trait.is(.Struct)(E))
            return cmp_struct(T, x, y);

        @compileError("Ord is undefined for type:" ++ @typeName(T) ++ ":" ++ @typeInfo(T));
    }

    /// General comparing function on a type returns true for `isOrd`.
    ///
    /// # Details
    /// Compares values satisfies the `isOrd` predicate.
    pub fn cmp(x: anytype, y: @TypeOf(x)) std.math.Order {
        const T = @TypeOf(x);
        comptime assert(isOrd(T));

        if (comptime !trait.isSingleItemPtr(T))
            return cmp_impl(&x, &y);
        return cmp_impl(x, y);
    }

    /// Acquiring the 'cmp' function specilized for type `T`.
    ///
    /// # Details
    /// The type of 'cmp' is considered to be `fn (anytype,anytype) anytype`, and to acquire an implementation for a specific type you need to do the following:
    /// ```
    /// val specialized_to_T = struct {
    ///   fn order(x:T, y:T) Order {
    ///     return cmp(x,y);
    ///   }
    /// }.order;
    /// ```
    /// 
    /// Using `on`, you can obtain such specialized versions on the fly.
    /// ```
    /// val specialized_to_T = Ord.on(T);
    /// ```
    pub fn on(comptime T: type) fn (T, T) std.math.Order {
        return struct {
            fn call(x: T, y: T) std.math.Order {
                return cmp(x, y);
            }
        }.call;
    }
};

comptime {
    const zero = @as(u32, 0);
    var pzero = &zero;
    const one = @as(u32, 1);
    var pone = &one;
    assert(Ord.on(u32)(0, 1) == .lt);
    assert(Ord.on(*const u32)(pzero, pone) == .lt);
}

test "Ord" {
    const Order = std.math.Order;
    // compares primitive type
    try testing.expectEqual(Order.eq, Ord.cmp(null, null));

    const five: u32 = 5;
    const six: u32 = 6;
    try testing.expectEqual(Order.lt, Ord.cmp(five, six));
    try testing.expectEqual(Order.lt, Ord.cmp(&five, &six));

    // compares sequence type
    const ax = [3]u32{ 0, 1, 2 };
    const bx = [3]u32{ 0, 1, 3 };
    try testing.expectEqual(Order.lt, Ord.cmp(ax, bx));
    try testing.expectEqual(Order.eq, Ord.cmp(ax, ax));

    const Unit = struct {};
    const @"u1": Unit = Unit{};
    const @"u2": Unit = Unit{};
    assert(isOrd(Unit));
    assert(isOrd(*Unit));
    assert(isOrd(*const Unit));
    try testing.expect(Ord.cmp(&@"u1", &@"u1").compare(.eq));
    try testing.expect(Ord.cmp(&@"u1", &@"u2").compare(.eq));

    // compares complex type
    const C = struct {
        x: u32,
        fn new(x: u32) @This() {
            return .{ .x = x };
        }
        fn cmp(self: *const @This(), other: *const @This()) std.math.Order {
            return std.math.order(self.x, other.x);
        }
    };
    try testing.expectEqual(Order.lt, C.new(5).cmp(&C.new(6)));
    try testing.expectEqual(Order.eq, C.new(6).cmp(&C.new(6)));
    try testing.expectEqual(Order.gt, C.new(6).cmp(&C.new(5)));
}
