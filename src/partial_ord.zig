const std = @import("std");

const meta = @import("./meta.zig");

const trait = std.meta.trait;
const testing = std.testing;

const assert = std.debug.assert;

fn implPartialOrd(comptime T: type) bool {
    comptime {
        if (trait.is(.Void)(T))
            return true;
        if (trait.is(.Bool)(T))
            return true;
        if (trait.is(.Null)(T))
            return true;
        if (trait.is(.Array)(T))
            return implPartialOrd(std.meta.Child(T));
        if (trait.is(.Optional)(T))
            return implPartialOrd(std.meta.Child(T));
        if (trait.is(.Enum)(T))
            return implPartialOrd(@typeInfo(T).Enum.tag_type);
        if (trait.is(.EnumLiteral)(T))
            return true;
        if (trait.is(.ErrorSet)(T))
            return true;
        if (trait.is(.ErrorUnion)(T))
            return implPartialOrd(@typeInfo(T).ErrorUnion.error_set) and implPartialOrd(@typeInfo(T).ErrorUnion.payload);
        if (trait.isNumber(T))
            return true;
        if (meta.have_fun(T, "partial_cmp")) |ty|
            return ty == fn (*const T, *const T) ?std.math.Order;
        if (trait.is(.Struct)(T) or trait.is(.Union)(T)) {
            if (meta.tag_of(T) catch null) |tag| {
                if (!implPartialOrd(tag))
                    return false;
            }
            // all type of fields are comparable
            return meta.all_field_types(T, implPartialOrd);
        }
        return false;
    }
}

pub fn isPartialOrd(comptime T: type) bool {
    comptime return meta.is_or_ptrto(implPartialOrd)(T);
}

comptime {
    assert(isPartialOrd(u32));
    assert(isPartialOrd(*const u64));
    assert(isPartialOrd(i64));
    assert(isPartialOrd(*const i64));
    assert(!isPartialOrd(*[]const i64));
    assert(isPartialOrd([8]u64));
    assert(isPartialOrd(f64));
    assert(!isPartialOrd(@Vector(4, u32)));

    const U = union(enum) { Tag1, Tag2, Tag3 };
    assert(isPartialOrd(U));
    assert(isPartialOrd(*U));
    assert(isPartialOrd(*const U));
    assert(!isPartialOrd(**const U));

    const OverflowError = error{Overflow};
    assert(isPartialOrd(@TypeOf(.Overflow))); // EnumLiteral
    assert(isPartialOrd(OverflowError)); // ErrorSet
    assert(isPartialOrd(OverflowError![2]U)); // ErrorUnion
    assert(isPartialOrd(?(error{Overflow}![2]U)));

    assert(isPartialOrd(struct { val: u32 }));
    const C = struct {
        pub fn partial_cmp(x: *const @This(), y: *const @This()) ?std.math.Order {
            _ = x;
            _ = y;
            return null;
        }
    };
    assert(isPartialOrd(C));
    assert(isPartialOrd(*C));
    const D = struct {
        val: u32, // isPartialOrd
        // signature of partial_cmp is not matches to
        // `fn (*const T, *const T) ?Order`.
        pub fn partial_cmp(x: @This(), y: @This()) ?std.math.Order {
            _ = x;
            _ = y;
            return null;
        }
    };
    assert(!isPartialOrd(D));
    assert(!isPartialOrd(*D));
}

pub const PartialOrd = struct {
    fn cmp_float(x: anytype, y: @TypeOf(x)) ?std.math.Order {
        comptime assert(trait.isFloat(@TypeOf(x)));
        if (std.math.isNan(x) or std.math.isNan(y))
            return null;
        return std.math.order(x, y);
    }

    fn cmp_bool(x: bool, y: bool) std.math.Order {
        if (x == y)
            return .eq;
        return if (y) .lt else .gt;
    }

    fn cmp_array(comptime T: type, x: T, y: T) ?std.math.Order {
        comptime assert(trait.isPtrTo(.Array)(T));
        for (x) |xv, i| {
            if (cmp_impl(&xv, &y[i])) |ord| {
                switch (ord) {
                    .lt, .gt => return ord,
                    .eq => {},
                }
            } else {
                return null;
            }
        }
        return .eq;
    }

    fn cmp_optional(comptime T: type, x: T, y: T) ?std.math.Order {
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

    pub fn cmp_impl(x: anytype, y: @TypeOf(x)) ?std.math.Order {
        const T = @TypeOf(x);
        comptime assert(trait.isSingleItemPtr(T));
        const E = std.meta.Child(T);
        comptime assert(implPartialOrd(E));

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
        if (comptime trait.isFloat(E))
            return cmp_float(x.*, y.*);
        if (comptime trait.isIntegral(E))
            return std.math.order(x.*, y.*);
        if (comptime meta.have_fun(T, "partial_cmp")) |_|
            return x.partial_cmp(y);

        @compileError("PartialOrd is undefined for type:" ++ @typeName(T));
    }

    pub fn partial_cmp(x: anytype, y: @TypeOf(x)) ?std.math.Order {
        const T = @TypeOf(x);
        comptime assert(isPartialOrd(T));

        if (comptime !trait.isSingleItemPtr(T))
            return cmp_impl(&x, &y);
        return cmp_impl(x, y);
    }

    /// Acquiring the 'partial_cmp' function specilized for type `T`.
    ///
    /// # Details
    /// The type of 'partial_cmp' is considered to be `fn (anytype,anytype) anytype`, and to acquire an implementation for a specific type you need to do the following:
    /// ```
    /// val specialized_to_T = struct {
    ///   fn cmp(x:T, y:T) ?Order {
    ///     return partial_cmp(x,y);
    ///   }
    /// }.cmp;
    /// ```
    /// 
    /// Using `on`, you can obtain such specialized versions on the fly.
    /// ```
    /// val specialized_to_T = PartialOrd.on(T);
    /// ```
    pub fn on(comptime T: type) fn (T, T) ?std.math.Order {
        return struct {
            fn call(x: T, y: T) ?std.math.Order {
                return partial_cmp(x, y);
            }
        }.call;
    }
};

comptime {
    const x = @as(f32, 0.5);
    var px = &x;
    const y = @as(f32, 1.1);
    var py = &y;
    assert(PartialOrd.on(f32)(x, y).? == .lt);
    assert(PartialOrd.on(*const f32)(px, py).? == .lt);
    assert(PartialOrd.on(f32)(x, std.math.nan(f32)) == null);
    assert(PartialOrd.on(*const f32)(px, &std.math.nan(f32)) == null);
}

test "PartialOrd" {
    const Order = std.math.Order;
    const opt = struct {
        fn f(x: Order) ?Order {
            return x;
        }
    }.f;

    // compares primitive type
    try testing.expectEqual(opt(Order.eq), PartialOrd.partial_cmp(null, null));

    const five: u32 = 5;
    const six: u32 = 6;
    try testing.expectEqual(opt(Order.lt), PartialOrd.partial_cmp(five, six));
    try testing.expectEqual(opt(Order.lt), PartialOrd.partial_cmp(&five, &six));

    const fiveh: f64 = 5.5;
    const sixh: f64 = 6.5;
    try testing.expectEqual(opt(Order.lt), PartialOrd.partial_cmp(fiveh, sixh));
    try testing.expectEqual(opt(Order.lt), PartialOrd.partial_cmp(&fiveh, &sixh));

    // compares sequence type
    const ax = [3]u32{ 0, 1, 2 };
    const bx = [3]u32{ 0, 1, 3 };
    try testing.expectEqual(opt(Order.lt), PartialOrd.partial_cmp(ax, bx));
    try testing.expectEqual(opt(Order.eq), PartialOrd.partial_cmp(ax, ax));

    // compares complex type
    const C = struct {
        x: u32,
        fn new(x: u32) @This() {
            return .{ .x = x };
        }
        fn partial_cmp(self: *const @This(), other: *const @This()) ?std.math.Order {
            return std.math.order(self.x, other.x);
        }
    };
    try testing.expectEqual(opt(Order.lt), C.new(5).partial_cmp(&C.new(6)));
    try testing.expectEqual(opt(Order.eq), C.new(6).partial_cmp(&C.new(6)));
    try testing.expectEqual(opt(Order.gt), C.new(6).partial_cmp(&C.new(5)));
}
