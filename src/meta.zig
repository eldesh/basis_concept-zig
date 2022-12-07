const std = @import("std");
const builtin = @import("builtin");

const trait = std.meta.trait;
const assert = std.debug.assert;
const SemVer = std.SemanticVersion;

pub const TypeKindError = error{
    NotEnumOrUnionError,
};

// pub usingnamespace basis;
/// workaround criteria
pub const zig091 = SemVer.parse("0.9.1") catch unreachable;
/// *this* is older than or equals to zig-0.9.1 (<= 0.9.1).
pub const older_zig091: bool = builtin.zig_version.order(zig091).compare(.lte);
/// *this* is newer than zig-0.9.1 (> 0.9.1)
pub const newer_zig091: bool = builtin.zig_version.order(zig091).compare(.gt);

pub fn tag_of(comptime T: type) TypeKindError!?type {
    comptime {
        return switch (@typeInfo(T)) {
            .Enum => |info| info.tag_type,
            .Union => |info| info.tag_type,
            else => TypeKindError.NotEnumOrUnionError,
        };
    }
}

pub fn have_type(comptime T: type, comptime name: []const u8) ?type {
    comptime {
        if (!trait.isContainer(T))
            return null;
        if (!@hasDecl(T, name))
            return null;

        const field = @field(T, name);
        if (@typeInfo(@TypeOf(field)) == .Type) {
            return field;
        }
        return null;
    }
}

comptime {
    const E = struct {};
    const C = struct {
        pub const Self = @This();
    };
    assert(have_type(E, "Self") == null);
    assert(have_type(C, "Self") != null);
    assert(have_type(u32, "cmp") == null);
}

// On zig-0.10.0, `@hasDecl` crashes.
fn hasDecl(comptime T: type, comptime name: []const u8) bool {
    comptime {
        switch (@typeInfo(T)) {
            .Struct, .Union, .Enum, .Opaque => {
                for (std.meta.declarations(T)) |decl| {
                    if (decl.is_pub) {
                        if (std.mem.eql(u8, decl.name, name))
                            return true;
                    }
                }
                return false;
            },
            else => return false,
        }
    }
}

pub fn have_fun(comptime T: type, comptime name: []const u8) ?type {
    comptime {
        if (newer_zig091) {
            if (!std.meta.trait.isContainer(T))
                return null;
            if (!@hasDecl(T, name))
                return null;
            return @as(?type, @TypeOf(@field(T, name)));
        } else {
            switch (@typeInfo(T)) {
                .Struct => |Struct| {
                    for (Struct.decls) |decl| {
                        if (std.mem.eql(u8, decl.name, name))
                            return @TypeOf(@field(T, name));
                    }
                },
                .Union => |Union| {
                    for (Union.decls) |decl| {
                        if (std.mem.eql(u8, decl.name, name))
                            return @TypeOf(@field(T, name));
                    }
                },
                .Enum => |Enum| {
                    for (Enum.decls) |decl| {
                        if (std.mem.eql(u8, decl.name, name))
                            return @TypeOf(@field(T, name));
                    }
                },
                .Opaque => |Opaque| {
                    for (Opaque.decls) |decl| {
                        if (std.mem.eql(u8, decl.name, name))
                            return @TypeOf(@field(T, name));
                    }
                },
                else => {},
            }
            return null;
        }
    }
}

pub fn have_fun_sig(comptime T: type, comptime name: []const u8, comptime Sig: type) bool {
    comptime {
        if (!std.meta.trait.isContainer(T))
            return false;
        if (!@hasDecl(T, name))
            return false;
        return @TypeOf(@field(T, name)) == Sig;
    }
}

pub fn deref_type(comptime T: type) type {
    comptime {
        if (trait.isSingleItemPtr(T)) {
            return std.meta.Child(T);
        } else {
            return T;
        }
    }
}

comptime {
    assert(deref_type(u32) == u32);
    assert(deref_type(*u32) == u32);
    assert(deref_type(**u32) == *u32);
    assert(deref_type([]u8) == []u8);
    const U = union(enum) { Tag1, Tag2 };
    assert(deref_type(U) == U);
    assert(deref_type(*U) == U);
}

/// F(T) or F(T.*)
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

/// forall field:std.meta.fields(T), P(field.field_type).
pub fn all_field_types(comptime T: type, comptime P: fn (type) bool) bool {
    comptime {
        for (std.meta.fields(T)) |field| {
            if (!P(field.field_type))
                return false;
        }
        return true;
    }
}
