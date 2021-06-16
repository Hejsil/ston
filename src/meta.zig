const std = @import("std");
const ston = @import("../ston.zig");

const debug = std.debug;
const fmt = std.fmt;
const io = std.io;
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;

/// Given a type `T`, figure out wether or not it is an `Index(G, K)`.
pub fn isIndex(comptime T: type) bool {
    if (@typeInfo(T) != .Struct)
        return false;
    if (!@hasDecl(T, "IndexType") or !@hasDecl(T, "ValueType"))
        return false;
    if (@TypeOf(T.IndexType) != type or @TypeOf(T.ValueType) != type)
        return false;
    return T == ston.Index(T.IndexType, T.ValueType);
}

comptime {
    debug.assert(!isIndex(u8));
    debug.assert(isIndex(ston.Index(u8, u8)));
    debug.assert(isIndex(ston.Index(u16, u16)));

    debug.assert(!isIndex(struct {
        pub const IndexType = u8;
        pub const ValueType = u8;

        index: IndexType,
        value: ValueType,
    }));
}

/// Given a type `T`, figure out wether or not it is an `Field(K)`.
pub fn isField(comptime T: type) bool {
    if (@typeInfo(T) != .Struct)
        return false;
    if (!@hasDecl(T, "ValueType"))
        return false;
    if (@TypeOf(T.ValueType) != type)
        return false;
    return T == ston.Field(T.ValueType);
}

comptime {
    debug.assert(!isField(u8));
    debug.assert(isField(ston.Field(u8)));
    debug.assert(isField(ston.Field(u16)));

    debug.assert(!isField(struct {
        pub const ValueType = u8;

        name: []const u8,
        value: ValueType,
    }));
}

const HashMapParams = struct {
    K: type,
    V: type,
    Context: type,
    Hash: type,
};

fn hashMapParams(comptime T: type) ?HashMapParams {
    if (!@hasDecl(T, "KV") or !@hasField(T, "ctx"))
        return null;
    if (@typeInfo(T.KV) != .Struct)
        return null;
    if (!@hasField(T.KV, "key") or !@hasField(T.KV, "value"))
        return null;

    const Context = std.meta.fieldInfo(T, .ctx).field_type;
    if (!@hasDecl(Context, "hash"))
        return null;

    const HashFn = @TypeOf(Context.hash);
    const Hash = switch (@typeInfo(HashFn)) {
        .Fn => |info| info.return_type orelse return null,
        else => return null,
    };

    return HashMapParams{
        .K = std.meta.fieldInfo(T.KV, .key).field_type,
        .V = std.meta.fieldInfo(T.KV, .value).field_type,
        .Context = Context,
        .Hash = Hash,
    };
}

/// Given a type `T`, figure out wether it is a `std.HashMap`
pub fn isHashMap(comptime T: type) bool {
    if (@typeInfo(T) != .Struct)
        return false;
    if (@hasDecl(T, "Managed"))
        return isHashMap(T.Managed);

    const Params = hashMapParams(T) orelse return false;
    if (Params.Hash != u64)
        return false;

    for ([_]void{{}} ** 100) |_, i| {
        if (T == std.HashMap(Params.K, Params.V, Params.Context, i + 1))
            return true;
    }

    return false;
}

comptime {
    debug.assert(!isHashMap(u8));
    debug.assert(isHashMap(std.AutoHashMap(u8, u8)));
    debug.assert(!isHashMap(std.AutoArrayHashMap(u8, u8)));
}

/// Given a type `T`, figure out wether it is a `std.ArrayHashMap`
pub fn isArrayHashMap(comptime T: type) bool {
    if (@typeInfo(T) != .Struct)
        return false;
    if (@hasDecl(T, "Managed"))
        return isArrayHashMap(T.Managed);

    const Params = hashMapParams(T) orelse return false;
    if (Params.Hash != u32)
        return false;

    return T == std.ArrayHashMap(Params.K, Params.V, Params.Context, false) or
        T == std.ArrayHashMap(Params.K, Params.V, Params.Context, true);
}

comptime {
    debug.assert(!isArrayHashMap(u8));
    debug.assert(!isArrayHashMap(std.AutoHashMap(u8, u8)));
    debug.assert(isArrayHashMap(std.AutoArrayHashMap(u8, u8)));
}

pub fn isMap(comptime T: type) bool {
    return isArrayHashMap(T) or isHashMap(T);
}

comptime {
    debug.assert(!isMap(u8));
    debug.assert(isMap(std.AutoHashMap(u8, u8)));
    debug.assert(isMap(std.AutoArrayHashMap(u8, u8)));
}

pub fn isIntMap(comptime T: type) bool {
    if (!isMap(T))
        return false;

    const Params = hashMapParams(T).?;
    return @typeInfo(Params.K) == .Int;
}

comptime {
    debug.assert(!isIntMap(u8));
    debug.assert(isIntMap(std.AutoHashMap(u8, u8)));
    debug.assert(isIntMap(std.AutoArrayHashMap(u8, u8)));
    debug.assert(!isIntMap(std.AutoHashMap([2]u8, u8)));
    debug.assert(!isIntMap(std.AutoArrayHashMap([2]u8, u8)));
}

pub fn isArrayList(comptime T: type) bool {
    if (@typeInfo(T) != .Struct or !@hasDecl(T, "Slice"))
        return false;

    const Slice = T.Slice;
    const ptr_info = switch (@typeInfo(Slice)) {
        .Pointer => |info| info,
        else => return false,
    };

    return T == std.ArrayListAligned(ptr_info.child, null) or
        T == std.ArrayListAligned(ptr_info.child, ptr_info.alignment) or
        T == std.ArrayListAlignedUnmanaged(ptr_info.child, null) or
        T == std.ArrayListAlignedUnmanaged(ptr_info.child, ptr_info.alignment);
}

comptime {
    debug.assert(!isArrayList(u8));
    debug.assert(isArrayList(std.ArrayList(u8)));
    debug.assert(isArrayList(std.ArrayListUnmanaged(u8)));
}
