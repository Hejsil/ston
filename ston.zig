const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const io = std.io;
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;

const ston = @This();

const parse = @import("src/parse.zig");

pub const Parser = parse.Parser(.{});

pub usingnamespace @import("src/meta.zig");

/// The type ston understands to be an index and will therefor be serialized/deserialized as
/// such,
pub fn Index(comptime _IndexType: type, comptime _ValueType: type) type {
    return struct {
        pub const IndexType = _IndexType;
        pub const ValueType = _ValueType;

        index: IndexType,
        value: ValueType,
    };
}

pub fn index(i: anytype, value: anytype) Index(@TypeOf(i), @TypeOf(value)) {
    return .{ .index = i, .value = value };
}

/// The type ston understands to be a field and will therefor be serialized/deserialized as
/// such,
pub fn Field(comptime _ValueType: type) type {
    return struct {
        pub const ValueType = _ValueType;

        name: []const u8,
        value: ValueType,
    };
}

pub fn field(name: []const u8, value: anytype) Field(@TypeOf(value)) {
    return .{ .name = name, .value = value };
}

/// The type to use to specify that the underlying value is a string. All this type does is
/// force the `{s}` format specify in its own format function.
pub fn String(comptime T: type) type {
    return struct {
        value: T,

        pub fn format(
            self: @This(),
            comptime f: []const u8,
            opts: std.fmt.FormatOptions,
            writer: anytype,
        ) @TypeOf(writer).Error!void {
            _ = f;
            _ = opts;
            try writer.print("{s}", .{self.value});
        }
    };
}

pub fn string(value: anytype) String(@TypeOf(value)) {
    return .{ .value = value };
}

pub const DerserializeLineError = error{
    InvalidBoolValue,
    InvalidEnumValue,
    InvalidField,
    InvalidFloatValue,
    InvalidIndex,
    InvalidIntValue,
    InvalidValue,
};

const Bool = enum(u1) { @"false" = 0, @"true" = 1 };

/// Parses parserens into `T`, where `T` is a union of possible fields/indexs that are valid.
/// This only deserializes up to the next `Token.Tag.value` parseren and will then return a `T`
/// initialized based on what deserialized.
pub fn deserializeLine(comptime T: type, parser: *ston.Parser) DerserializeLineError!T {
    // const max = comptime deserializeMaxLenFinit(T);
    // if (parser.hasBytesLeft(max)) {
    //     return deserializeLineAssert(T, parser.assertBoundsCheck(true));
    // } else {
    return deserializeLineAssert(T, parser);
    // }
}

fn deserializeLineAssert(comptime T: type, parser: anytype) DerserializeLineError!T {
    if (comptime ston.isIndex(T)) {
        const i = try parser.index(T.IndexType);
        const value = try deserializeLineAssert(
            T.ValueType,
            parser.assertPrefixEaten(false),
        );
        return index(i, value);
    }
    if (comptime ston.isField(T)) {
        const name = try parser.anyField();
        const value = try deserializeLine(
            T.ValueType,
            parser.assert(.{}),
        );
        return field(name, value);
    }

    switch (T) {
        []const u8, [:'\n']const u8 => return try parser.value(),
        [*:'\n']const u8 => return (try parser.value()).ptr,
        else => {},
    }

    switch (@typeInfo(T)) {
        .Float => {
            const value = parser.value() catch return error.InvalidFloatValue;
            return fmt.parseFloat(T, value) catch return error.InvalidFloatValue;
        },
        .Int => return try parser.intValue(T),
        .Enum => return try parser.enumValue(T),
        .Bool => {
            const res = deserializeLineAssert(Bool, parser) catch return error.InvalidBoolValue;
            return res == .@"true";
        },
        .Union => |info| {
            inline for (info.fields) |f| {
                const first_child_char = comptime deserializeFirstChar(f.field_type);
                if (parser.field(f.name ++ [_]u8{first_child_char})) {
                    return @unionInit(T, f.name, try deserializeLineAssert(
                        f.field_type,
                        parser.assertPrefixEaten(true),
                    ));
                }
            }

            return error.InvalidField;
        },
        else => @compileError("'" ++ @typeName(T) ++ "' is not supported"),
    }
}

fn deserializeFirstChar(comptime T: type) u8 {
    if (comptime ston.isIndex(T))
        return '[';
    if (comptime ston.isField(T))
        return '.';
    switch (T) {
        []const u8,
        [:'\n']const u8,
        [*:'\n']const u8,
        => return '=',
        else => {},
    }

    switch (@typeInfo(T)) {
        .Enum, .Float, .Int, .Bool => return '=',
        .Union => return '.',
        else => @compileError("Type '" ++ @typeName(T) ++ "' not supported"),
    }
}

/// Figures out the maximum finit number of bytes required to deserialize a T. T requires an
/// infinit number of bytes maximum, the biggest finit value is returned.
pub fn deserializeMaxLenFinit(comptime T: type) usize {
    if (comptime ston.isIndex(T)) {
        const i = math.max(
            fmt.count("[{}]", .{math.minInt(T.IndexType)}),
            fmt.count("[{}]", .{math.maxInt(T.IndexType)}),
        );
        return i + deserializeMaxLenFinit(T.ValueType);
    }
    if (comptime ston.isField(T))
        return 1;
    switch (T) {
        []const u8,
        [:'\n']const u8,
        [*:'\n']const u8,
        => return 1,
        else => {},
    }

    switch (@typeInfo(T)) {
        .Int, .Float => return 1,
        .Bool => return deserializeMaxLenFinit(Bool),
        .Enum => |info| {
            var res: usize = 0;
            inline for (info.fields) |f|
                res = math.max(res, f.name.len);
            return res + 2;
        },
        .Union => |info| {
            var res: usize = 0;
            inline for (info.fields) |f|
                res = math.max(res, f.name.len + deserializeMaxLenFinit(f.field_type));
            return res + 1;
        },
        else => @compileError("Type '" ++ @typeName(T) ++ "' not supported"),
    }
}

/// A struct that provides an iterator like API over `deserializeLine`.
pub fn Deserializer(comptime T: type) type {
    return struct {
        parser: *ston.Parser,
        value: T = default(T),

        pub inline fn next(des: *@This()) DerserializeLineError!T {
            // const max = comptime deserializeMaxLenFinit(T);
            // if (des.parser.hasBytesLeft(max)) {
            //     try update(T, &des.value, des.parser.assertBoundsCheck(true));
            // } else {
            try update(T, &des.value, des.parser);
            // }
            return des.value;
        }

        inline fn update(comptime T2: type, ptr: *T2, parser: anytype) !void {
            if (comptime ston.isIndex(T2)) {
                ptr.index = try parser.index(T2.IndexType);
                return update(
                    T2.ValueType,
                    &ptr.value,
                    parser.assertPrefixEaten(false),
                );
            }

            // Sometimes we can avoid doing parsing work by just checking if the current thing we
            // are parsing is the same `field` as what we previously parsed.
            if (@typeInfo(T2) == .Union) {
                const info = @typeInfo(T2).Union;
                inline for (info.fields) |f| {
                    if (ptr.* == @field(info.tag_type.?, f.name)) {
                        const first_child_char = comptime deserializeFirstChar(f.field_type);
                        if (parser.field(f.name ++ [_]u8{first_child_char}))
                            return update(
                                f.field_type,
                                &@field(ptr, f.name),
                                parser.assertPrefixEaten(true),
                            );
                    }
                }
            }

            ptr.* = try deserializeLineAssert(T2, parser);
        }

        fn default(comptime T2: type) T2 {
            switch (@typeInfo(T2)) {
                .Int, .Float => return @as(T2, 0),
                .Enum => |info| return @field(T2, info.fields[0].name),
                .Void => return {},
                .Bool => return false,
                .Optional, .Null => return null,
                .Struct => |struct_info| {
                    var res: T = undefined;
                    inline for (struct_info.fields) |f|
                        @field(res, f.name) = default(@TypeOf(@field(res, f.name)));
                    return res;
                },
                .Pointer => |ptr_info| {
                    switch (ptr_info.size) {
                        .Slice => return &[_]ptr_info.child{},
                        .C => return null,
                        .One, .Many => @compileError("Can't set a non nullable pointer to zero."),
                    }
                },
                .Array => |info| {
                    if (info.sentinel) |sentinel| {
                        return [_:sentinel]info.child{default(info.child)} ** info.len;
                    }
                    return [_]info.child{default(info.child)} ** info.len;
                },
                .Vector => |info| {
                    return @splat(info.len, default(info.child));
                },
                .Union => |info| {
                    const field_0 = info.fields[0];
                    return @unionInit(T2, field_0.name, default(field_0.field_type));
                },
                else => @compileError("Can't set a " ++ @typeName(T) ++ " to zero."),
            }
        }
    };
}

pub fn deserialize(comptime T: type, parser: *ston.Parser) Deserializer(T) {
    return .{ .parser = parser };
}

fn expectDerserializeLine(str: [:0]const u8, comptime T: type, err_expect: DerserializeLineError!T) !void {
    var parser = ston.Parser{ .str = str };
    var des_parser = ston.Parser{ .str = str };
    var des = deserialize(T, &des_parser);
    const expect = err_expect catch |err| {
        try testing.expectError(err, deserializeLine(T, &parser));
        try testing.expectError(err, des.next());
        des_parser = ston.Parser{ .str = str };
        try testing.expectError(err, des.next());
        return;
    };

    try testing.expectEqual(expect, deserializeLine(T, &parser) catch {
        try testing.expect(false);
        unreachable;
    });

    try testing.expectEqual(expect, des.next() catch {
        try testing.expect(false);
        unreachable;
    });

    des_parser = ston.Parser{ .str = str };
    try testing.expectEqual(expect, des.next() catch {
        try testing.expect(false);
        unreachable;
    });
}

test "deserializeLine" {
    const T = union(enum) {
        int: u8,
        float: f32,
        bol: bool,
        enu: enum { a, b },
        string: []const u8,
        index: Index(u8, u8),
    };
    try expectDerserializeLine(".int=2\n", T, T{ .int = 2 });
    try expectDerserializeLine(".float=2\n", T, T{ .float = 2 });
    try expectDerserializeLine(".bol=true\n", T, T{ .bol = true });
    try expectDerserializeLine(".enu=a\n", T, T{ .enu = .a });

    const input = ".string=string\n";
    try expectDerserializeLine(input, T, T{ .string = input[8 .. input.len - 1] });

    try expectDerserializeLine(".index[2]=4\n", T, T{ .index = .{ .index = 2, .value = 4 } });
    try expectDerserializeLine("[1]\n", T, error.InvalidField);
    try expectDerserializeLine(".int.a=1\n", T, error.InvalidField);
    try expectDerserializeLine(".index.a=1\n", T, error.InvalidField);
    try expectDerserializeLine(".int=q\n", T, error.InvalidIntValue);
    try expectDerserializeLine(".bol=q\n", T, error.InvalidBoolValue);
    try expectDerserializeLine(".enu=q\n", T, error.InvalidEnumValue);
    try expectDerserializeLine(".index[q]=q\n", T, error.InvalidIndex);
    try expectDerserializeLine(".q=q\n", T, error.InvalidField);
}

pub fn serialize(writer: anytype, value: anytype) !void {
    // TODO: Calculate upper bound for `prefix` from the type of `value`
    var buf: [mem.page_size]u8 = undefined;
    var prefix = io.fixedBufferStream(&buf);
    return serializeHelper(writer, &prefix, value);
}

fn serializeHelper(writer: anytype, prefix: *io.FixedBufferStream([]u8), value: anytype) !void {
    const T = @TypeOf(value);
    if (comptime ston.isIndex(T)) {
        var copy = prefix.*;
        copy.writer().writeAll("[") catch unreachable;
        fmt.formatInt(value.index, 10, .lower, .{}, copy.writer()) catch unreachable;
        copy.writer().writeAll("]") catch unreachable;
        try serializeHelper(writer, &copy, value.value);
        return;
    }
    if (comptime ston.isIntMap(T)) {
        var it = value.iterator();
        while (it.next()) |entry| {
            var copy = prefix.*;
            copy.writer().writeAll("[") catch unreachable;
            fmt.formatInt(entry.key_ptr.*, 10, .lower, .{}, copy.writer()) catch unreachable;
            copy.writer().writeAll("]") catch unreachable;
            try serializeHelper(writer, &copy, entry.value_ptr.*);
        }
        return;
    }
    if (comptime ston.isArrayList(T)) {
        return serializeHelper(writer, prefix, value.items);
    }
    if (comptime ston.isField(T)) {
        var copy = prefix.*;
        copy.writer().writeAll(".") catch unreachable;
        copy.writer().writeAll(value.name) catch unreachable;
        try serializeHelper(writer, &copy, value.value);
        return;
    }

    switch (@typeInfo(T)) {
        .Void, .Null => {},
        .Bool => {
            try writer.writeAll(prefix.getWritten());
            try writer.writeAll("=");
            try writer.writeAll(if (value) "true" else "false");
            try writer.writeAll("\n");
        },
        .Int, .ComptimeInt => {
            try writer.writeAll(prefix.getWritten());
            try writer.writeAll("=");
            try fmt.formatInt(value, 10, .lower, .{}, writer);
            try writer.writeAll("\n");
        },
        .Float, .ComptimeFloat => {
            try writer.writeAll(prefix.getWritten());
            try writer.writeAll("=");
            try fmt.formatFloatDecimal(value, .{}, writer);
            try writer.writeAll("\n");
        },
        .Optional => if (value) |v| {
            try serializeHelper(writer, prefix, v);
        } else {},
        .Pointer => |info| switch (info.size) {
            .One => try serializeHelper(writer, prefix, value.*),
            .Slice => for (value) |v, i| {
                var copy = prefix.*;
                copy.writer().writeAll("[") catch unreachable;
                fmt.formatInt(i, 10, .lower, .{}, copy.writer()) catch unreachable;
                copy.writer().writeAll("]") catch unreachable;
                try serializeHelper(writer, &copy, v);
            },
            else => @compileError("Type '" ++ @typeName(T) ++ "' not supported"),
        },
        .Array => |info| {
            var l: usize = info.len;
            try serializeHelper(writer, prefix, value[0..l]);
        },
        .Enum => {
            try writer.writeAll(prefix.getWritten());
            try writer.writeAll("=");
            if (@hasDecl(T, "format")) {
                try value.format("", .{}, writer);
            } else {
                try writer.writeAll(@tagName(value));
            }
            try writer.writeAll("\n");
        },
        .Union => |info| {
            const Tag = meta.Tag(T);
            if (@hasDecl(T, "format")) {
                try writer.writeAll(prefix.getWritten());
                try writer.writeAll("=");
                try value.format("", .{}, writer);
                try writer.writeAll("\n");
            } else inline for (info.fields) |f| {
                if (@field(Tag, f.name) == value) {
                    var copy = prefix.*;
                    copy.writer().writeAll("." ++ f.name) catch unreachable;
                    try serializeHelper(writer, &copy, @field(value, f.name));
                    return;
                }
            }
            unreachable;
        },
        .Struct => |info| if (@hasDecl(T, "format")) {
            try writer.writeAll(prefix.getWritten());
            try writer.writeAll("=");
            try value.format("", .{}, writer);
            try writer.writeAll("\n");
        } else inline for (info.fields) |f| {
            var copy = prefix.*;
            copy.writer().writeAll("." ++ f.name) catch unreachable;
            try serializeHelper(writer, &copy, @field(value, f.name));
        },
        else => @compileError("Type '" ++ @typeName(T) ++ "' not supported"),
    }
}

fn expectSerialized(str: []const u8, value: anytype) !void {
    var buf: [mem.page_size]u8 = undefined;
    var fbs = io.fixedBufferStream(&buf);
    try serialize(fbs.writer(), value);
    try testing.expectEqualStrings(str, fbs.getWritten());
}

test "serialize - struct" {
    const S = struct {
        a: u8 = 1,
        b: enum { a, b } = .a,
        c: bool = false,
        d: String(*const [4:0]u8) = string("abcd"),
        e: Index(u8, u8) = .{ .index = 2, .value = 3 },
        f: union(enum) { a: u8, b: bool } = .{ .a = 2 },
        g: f32 = 1.5,
        h: void = {},
        i: Field(u8) = .{ .name = "a", .value = 2 },
    };
    try expectSerialized(
        \\.a=1
        \\.b=a
        \\.c=false
        \\.d=abcd
        \\.e[2]=3
        \\.f.a=2
        \\.g=1.5
        \\.i.a=2
        \\
    , S{});
    try expectSerialized(
        \\[0].a=1
        \\[0].b=a
        \\[0].c=false
        \\[0].d=abcd
        \\[0].e[2]=3
        \\[0].f.a=2
        \\[0].g=1.5
        \\[0].i.a=2
        \\[1].a=1
        \\[1].b=a
        \\[1].c=false
        \\[1].d=abcd
        \\[1].e[2]=3
        \\[1].f.a=2
        \\[1].g=1.5
        \\[1].i.a=2
        \\
    , [_]S{.{}} ** 2);

    try expectSerialized(
        \\[0][0].a=1
        \\[0][0].b=a
        \\[0][0].c=false
        \\[0][0].d=abcd
        \\[0][0].e[2]=3
        \\[0][0].f.a=2
        \\[0][0].g=1.5
        \\[0][0].i.a=2
        \\[0][1].a=1
        \\[0][1].b=a
        \\[0][1].c=false
        \\[0][1].d=abcd
        \\[0][1].e[2]=3
        \\[0][1].f.a=2
        \\[0][1].g=1.5
        \\[0][1].i.a=2
        \\[1][0].a=1
        \\[1][0].b=a
        \\[1][0].c=false
        \\[1][0].d=abcd
        \\[1][0].e[2]=3
        \\[1][0].f.a=2
        \\[1][0].g=1.5
        \\[1][0].i.a=2
        \\[1][1].a=1
        \\[1][1].b=a
        \\[1][1].c=false
        \\[1][1].d=abcd
        \\[1][1].e[2]=3
        \\[1][1].f.a=2
        \\[1][1].g=1.5
        \\[1][1].i.a=2
        \\
    , [_][2]S{[_]S{.{}} ** 2} ** 2);
}

test "serialize - HashMap" {
    var hm = std.AutoHashMap(u8, u8).init(testing.allocator);
    defer hm.deinit();

    try hm.putNoClobber(2, 3);
    try hm.putNoClobber(4, 8);
    try hm.putNoClobber(10, 20);

    try expectSerialized(
        \\[4]=8
        \\[10]=20
        \\[2]=3
        \\
    , hm);
}

test "serialize - ArrayHashMap" {
    var hm = std.AutoArrayHashMap(u8, u8).init(testing.allocator);
    defer hm.deinit();

    try hm.putNoClobber(2, 3);
    try hm.putNoClobber(4, 8);
    try hm.putNoClobber(10, 20);

    try expectSerialized(
        \\[2]=3
        \\[4]=8
        \\[10]=20
        \\
    , hm);
}

test "serialize - ArrayList" {
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);

    try expectSerialized(
        \\[0]=1
        \\[1]=2
        \\[2]=3
        \\
    , list);
}
