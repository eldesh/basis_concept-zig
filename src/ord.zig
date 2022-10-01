const std = @import("std");

const meta = @import("./meta.zig");
const partial_ord = @import("./partial_ord.zig");

const trait = std.meta.trait;

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
        // primitive type
        if (trait.isIntegral(T))
            return true;
        // complex type impl 'cmp' method
        if (have_fun(T, "cmp")) |ty| {
            if (ty == fn (*const T, *const T) std.math.Order)
                return true;
        }
        return false;
    }
}

// TODO: to be comparable tuple
// TODO: to be comparable optional
pub fn isOrd(comptime T: type) bool {
    comptime {
        return is_or_ptrto(implOrd)(T);
    }
}

comptime {
    assert(isOrd(u32));
    assert(isOrd(*u32));
    assert(!isOrd([]u32));
    assert(!isOrd([*]u32));
    assert(isOrd(i64));
    assert(isOrd(*const i64));
    assert(!isOrd(*[]const i64));
    assert(!isOrd([8]u64));
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
        pub fn cmp(x: @This(), y: @This()) std.math.Order {
            _ = x;
            _ = y;
            return .lt;
        }
    };
    assert(!isOrd(D)); // partial_cmp is not implemented
    assert(!isOrd(*D));
}

pub const Ord = struct {
    /// General comparing function
    ///
    /// # Details
    /// Compares `Ord` values.
    /// If the type of `x` is a primitive type, `cmp` would be used like `cmp(5, 6)`.
    /// And for others, like `cmp(&x, &y)` where the typeof x is comparable.
    pub fn cmp(x: anytype, y: @TypeOf(x)) std.math.Order {
        const T = @TypeOf(x);
        comptime assert(isOrd(T));

        // primitive types
        if (comptime trait.isIntegral(T) or trait.is(.Vector)(T))
            return std.math.order(x, y);
        // pointer that points to
        if (comptime trait.isSingleItemPtr(T)) {
            const E = std.meta.Child(T);
            // primitive types
            if (comptime trait.isIntegral(E) or trait.is(.Vector)(E))
                return std.math.order(x.*, y.*);
        }
        // - composed type implements 'cmp' or
        // - pointer that points to 'cmp'able type
        return x.cmp(y);
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
