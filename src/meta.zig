const std = @import("std");

const trait = std.meta.trait;
const assert = std.debug.assert;

pub fn is_or_ptrto(comptime F: fn (type) bool) fn (type) bool {
    comptime {
        return struct {
            fn pred(comptime U: type) bool {
                if (F(U))
                    return true;
                return trait.isSingleItemPtr(U) and F(std.meta.Child(U));
            }
        }.pred;
    }
}
