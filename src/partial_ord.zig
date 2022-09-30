const std = @import("std");

const meta = @import("./meta.zig");

const trait = std.meta.trait;
const testing = std.testing;

const math = std.math;
const assert = std.debug.assert;
const is_or_ptrto = meta.is_or_ptrto;
const have_type = meta.have_type;
const have_fun = meta.have_fun;

pub fn implPartialOrd(comptime T: type) bool {
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
        // primitive type
        if (trait.isNumber(T))
            return true;
        if (trait.is(.Union)(T)) {
            // impl 'partial_cmp' method
            if (have_fun(T, "partial_cmp")) |ty| {
                if (ty == fn (*const T, *const T) ?std.math.Order)
                    return true;
            }
            if (@typeInfo(T).Union.tag_type) |tag| {
                if (!implPartialOrd(tag))
                    return false;
            }
            inline for (std.meta.fields(T)) |field| {
                if (!implPartialOrd(field.field_type))
                    return false;
            }
            // all type of fields are comparable
            return true;
        }
        if (trait.is(.Struct)(T)) {
            if (have_fun(T, "partial_cmp")) |ty| {
                if (ty == fn (*const T, *const T) ?std.math.Order)
                    return true;
            }
            inline for (std.meta.fields(T)) |field| {
                if (!implPartialOrd(field.field_type))
                    return false;
            }
            // all type of fields are comparable
            return true;
        }
        return false;
    }
}

pub fn isPartialOrd(comptime T: type) bool {
    comptime return is_or_ptrto(implPartialOrd)(T);
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
    assert(isPartialOrd(D));
    assert(isPartialOrd(*D));
}

pub const PartialOrd = struct {
    fn partial_cmp_float(x: anytype, y: @TypeOf(x)) ?math.Order {
        comptime assert(trait.isFloat(@TypeOf(x)));
        if (math.isNan(x) or math.isNan(y))
            return null;
        return std.math.order(x, y);
    }

    pub fn partial_cmp(x: anytype, y: @TypeOf(x)) ?std.math.Order {
        const T = @TypeOf(x);
        comptime assert(isPartialOrd(T));

        // primitive types
        if (comptime trait.isFloat(T))
            return partial_cmp_float(x, y);
        if (comptime trait.isNumber(T))
            return math.order(x, y);

        // pointer that points to
        if (comptime trait.isSingleItemPtr(T)) {
            const E = std.meta.Child(T);
            comptime assert(implPartialOrd(E));
            // primitive types
            if (comptime trait.isFloat(E))
                return partial_cmp_float(x.*, y.*);
            if (comptime trait.isNumber(E))
                return math.order(x.*, y.*);
        }
        // - composed type implements 'partial_cmp' or
        // - pointer that points to 'partial_cmp'able type
        return x.partial_cmp(y);
    }

    /// Acquire the specilized 'partial_cmp' function with 'T'.
    ///
    /// # Details
    /// The type of 'partial_cmp' is evaluated as `fn (anytype,anytype) anytype` by default.
    /// To using the function specialized to a type, pass the function like `with(T)`.
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
    assert(PartialOrd.on(f32)(x, math.nan(f32)) == null);
    assert(PartialOrd.on(*const f32)(px, &math.nan(f32)) == null);
}

test "PartialOrd" {
    const five: u32 = 5;
    const six: u32 = 6;
    try testing.expectEqual(PartialOrd.partial_cmp(five, six), math.Order.lt);
    try testing.expectEqual(PartialOrd.partial_cmp(&five, &six), math.Order.lt);
    const C = struct {
        x: u32,
        fn new(x: u32) @This() {
            return .{ .x = x };
        }
        fn partial_cmp(self: *const @This(), other: *const @This()) ?math.Order {
            return std.math.order(self.x, other.x);
        }
    };
    try testing.expectEqual(C.new(5).partial_cmp(&C.new(6)), math.Order.lt);
    try testing.expectEqual(C.new(6).partial_cmp(&C.new(6)), math.Order.eq);
    try testing.expectEqual(C.new(6).partial_cmp(&C.new(5)), math.Order.gt);
}
