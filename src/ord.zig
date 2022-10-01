const std = @import("std");

const meta = @import("./meta.zig");
const partial_ord = @import("./partial_ord.zig");

const trait = std.meta.trait;
const testing = std.testing;

const assert = std.debug.assert;
const have_fun = meta.have_fun;
const is_or_ptrto = meta.is_or_ptrto;
const implPartialOrd = partial_ord.implPartialOrd;
const isPartialOrd = partial_ord.isPartialOrd;
const PartialOrd = partial_ord.PartialOrd;

pub fn implOrd(comptime T: type) bool {
    comptime {
        if (!implPartialOrd(T))
            return false;

        if (trait.is(.Void)(T))
            return true;
        if (trait.is(.Bool)(T))
            return true;
        if (trait.is(.Null)(T))
            return true;
        if (trait.is(.Array)(T))
            return implOrd(std.meta.Child(T));
        if (trait.is(.Optional)(T))
            return implOrd(std.meta.Child(T));
        if (trait.is(.Enum)(T))
            return implOrd(@typeInfo(T).Enum.tag_type);
        if (trait.is(.EnumLiteral)(T))
            return true;
        if (trait.is(.ErrorSet)(T))
            return true;
        if (trait.is(.ErrorUnion)(T))
            return implOrd(@typeInfo(T).ErrorUnion.error_set) and implOrd(@typeInfo(T).ErrorUnion.payload);
        if (trait.isIntegral(T))
            return true;
        if (have_fun(T, "cmp")) |ty|
            return ty == fn (*const T, *const T) std.math.Order;
        if (trait.is(.Union)(T)) {
            if (@typeInfo(T).Union.tag_type) |tag| {
                if (!implOrd(tag))
                    return false;
            }
            inline for (std.meta.fields(T)) |field| {
                if (!implOrd(field.field_type))
                    return false;
            }
            // all type of fields are comparable
            return true;
        }
        if (trait.is(.Struct)(T)) {
            inline for (std.meta.fields(T)) |field| {
                if (!implOrd(field.field_type))
                    return false;
            }
            // all type of fields are comparable
            return true;
        }
        return false;
    }
}

pub fn isOrd(comptime T: type) bool {
    comptime return is_or_ptrto(implOrd)(T);
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
    fn cmp_bool(x: *const bool, y: *const bool) std.math.Order {
        if (x.* == y.*)
            return .eq;
        return if (y.*) .lt else .gt;
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

    pub fn cmp_impl(x: anytype, y: @TypeOf(x)) std.math.Order {
        const T = @TypeOf(x);
        comptime assert(trait.isSingleItemPtr(T));
        const E = std.meta.Child(T);
        comptime assert(implPartialOrd(E));

        if (comptime trait.is(.Void)(E))
            return .eq;
        if (comptime trait.is(.Bool)(E))
            return cmp_bool(x, y);
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
        if (comptime have_fun(T, "cmp")) |_|
            return x.cmp(y);

        @compileError("Ord is undefined for type:" ++ @typeName(T));
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
    // compares primitive type
    try testing.expectEqual(Ord.cmp(null, null), .eq);

    const five: u32 = 5;
    const six: u32 = 6;
    try testing.expectEqual(Ord.cmp(five, six), .lt);
    try testing.expectEqual(Ord.cmp(&five, &six), .lt);

    // compares sequence type
    const ax = [3]u32{ 0, 1, 2 };
    const bx = [3]u32{ 0, 1, 3 };
    try testing.expectEqual(Ord.cmp(ax, bx), .lt);
    try testing.expectEqual(Ord.cmp(ax, ax), .eq);

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
    try testing.expectEqual(C.new(5).cmp(&C.new(6)), .lt);
    try testing.expectEqual(C.new(6).cmp(&C.new(6)), .eq);
    try testing.expectEqual(C.new(6).cmp(&C.new(5)), .gt);
}
