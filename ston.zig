const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const io = std.io;
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;

pub usingnamespace @import("src/meta.zig");

pub const Token = struct {
    tag: Tag,
    value: []const u8,

    pub fn field(v: []const u8) Token {
        return .{ .tag = .field, .value = v };
    }

    pub fn index(v: []const u8) Token {
        return .{ .tag = .index, .value = v };
    }

    pub fn value(v: []const u8) Token {
        return .{ .tag = .value, .value = v };
    }

    pub fn invalid(v: []const u8) Token {
        return .{ .tag = .invalid, .value = v };
    }

    pub const end = Token{ .tag = .end, .value = "" };

    pub const Tag = enum {
        field,
        index,
        value,
        invalid,
        end,
    };
};

pub const Tokenizer = struct {
    str: []const u8,
    start: usize = 0,
    i: usize = 0,
    state: enum {
        start,
        field,
        index,
        value,
        invalid,
    } = .start,

    pub fn next(tok: *Tokenizer) Token {
        while (tok.i < tok.str.len) {
            defer tok.i += 1;
            switch (tok.state) {
                .start => switch (tok.str[tok.i]) {
                    '.' => tok.state = .field,
                    '[' => tok.state = .index,
                    '=' => tok.state = .value,
                    '\n' => {
                        tok.state = .start;
                        return Token.invalid(tok.str[tok.start .. tok.i + 1]);
                    },
                    else => tok.state = .invalid,
                },
                .field => switch (tok.str[tok.i]) {
                    '.' => {
                        const res = Token.field(tok.str[tok.start + 1 .. tok.i]);
                        tok.start = tok.i;
                        return res;
                    },
                    '[' => {
                        const res = Token.field(tok.str[tok.start + 1 .. tok.i]);
                        tok.start = tok.i;
                        tok.state = .index;
                        return res;
                    },
                    '=' => {
                        const res = Token.field(tok.str[tok.start + 1 .. tok.i]);
                        tok.start = tok.i;
                        tok.state = .value;
                        return res;
                    },
                    '\n' => {
                        const res = Token.invalid(tok.str[tok.start .. tok.i + 1]);
                        tok.start = tok.i + 1;
                        tok.state = .start;
                        return res;
                    },
                    else => {},
                },
                .index => switch (tok.str[tok.i]) {
                    ']' => {
                        const res = Token.index(tok.str[tok.start + 1 .. tok.i]);
                        tok.start = tok.i + 1;
                        tok.state = .start;
                        return res;
                    },
                    '\n' => {
                        const res = Token.invalid(tok.str[tok.start .. tok.i + 1]);
                        tok.start = tok.i + 1;
                        tok.state = .start;
                        return res;
                    },
                    else => {},
                },
                .value => switch (tok.str[tok.i]) {
                    '\n' => {
                        const res = Token.value(tok.str[tok.start + 1 .. tok.i]);
                        tok.start = tok.i + 1;
                        tok.state = .start;
                        return res;
                    },
                    else => {},
                },
                .invalid => switch (tok.str[tok.i]) {
                    '\n' => {
                        const res = Token.invalid(tok.str[tok.start .. tok.i + 1]);
                        tok.start = tok.i + 1;
                        tok.state = .start;
                        return res;
                    },
                    else => {},
                },
            }
        }

        switch (tok.state) {
            .start => return Token.end,
            else => {
                const res = Token.invalid(tok.str[tok.start..]);
                tok.state = .start;
                tok.start = tok.str.len;
                tok.i = tok.str.len;
                return res;
            },
        }
    }
};

pub fn tokenize(str: []const u8) Tokenizer {
    return .{ .str = str };
}

fn expectTokens(str: []const u8, results: []const Token) !void {
    var tok = tokenize(str);
    for (results) |expect| {
        const actual = tok.next();
        try testing.expectEqual(expect.tag, actual.tag);
        try testing.expectEqualStrings(expect.value, actual.value);
    }
}

test "TokenStream" {
    try expectTokens(".=\n", &.{
        Token.field(""),
        Token.value(""),
        Token.end,
    });
    try expectTokens(".a=\n", &.{
        Token.field("a"),
        Token.value(""),
        Token.end,
    });
    try expectTokens("[]=\n", &.{
        Token.index(""),
        Token.value(""),
        Token.end,
    });
    try expectTokens("[1]=\n", &.{
        Token.index("1"),
        Token.value(""),
        Token.end,
    });
    try expectTokens("=\n", &.{
        Token.value(""),
        Token.end,
    });
    try expectTokens("=a\n", &.{
        Token.value("a"),
        Token.end,
    });
    try expectTokens(".a.b=c\n", &.{
        Token.field("a"),
        Token.field("b"),
        Token.value("c"),
        Token.end,
    });
    try expectTokens(".a[1]=c\n", &.{
        Token.field("a"),
        Token.index("1"),
        Token.value("c"),
        Token.end,
    });
    try expectTokens(".a.b=c\n.d.e[1]=f\n", &.{
        Token.field("a"),
        Token.field("b"),
        Token.value("c"),
        Token.field("d"),
        Token.field("e"),
        Token.index("1"),
        Token.value("f"),
        Token.end,
    });
    try expectTokens("a", &.{
        Token.invalid("a"),
        Token.end,
    });
    try expectTokens("[1]a", &.{
        Token.index("1"),
        Token.invalid("a"),
        Token.end,
    });
    try expectTokens("[1]a\n.q=2\n", &.{
        Token.index("1"),
        Token.invalid("a\n"),
        Token.field("q"),
        Token.value("2"),
        Token.end,
    });
    try expectTokens(".a=0\n[1]a", &.{
        Token.field("a"),
        Token.value("0"),
        Token.index("1"),
        Token.invalid("a"),
        Token.end,
    });
}

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

pub fn initIndex(index: anytype, value: anytype) Index(@TypeOf(index), @TypeOf(value)) {
    return .{ .index = index, .value = value };
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

pub fn initField(name: []const u8, value: anytype) Field(@TypeOf(value)) {
    return .{ .name = name, .value = value };
}

/// The type to use if a slice of bytes should be serialized as a string by serialize.
pub const String = struct {
    bytes: []const u8,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        __: std.fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        try writer.writeAll(self.bytes);
    }
};

pub fn string(str: []const u8) String {
    return .{ .bytes = str };
}

const Bool = enum { @"false", @"true" };

pub const ExpectError = error{
    ExpectedField,
    ExpectedIndex,
    ExpectedValue,
};

fn expectToken(tok: *Tokenizer, tag: Token.Tag) ExpectError!Token {
    var copy = tok.*;
    const token = copy.next();
    switch (tag) {
        .field => switch (token.tag) {
            .field => {},
            else => return error.ExpectedField,
        },
        .index => switch (token.tag) {
            .index => {},
            else => return error.ExpectedIndex,
        },
        .value => switch (token.tag) {
            .value => {},
            else => return error.ExpectedValue,
        },
        .invalid, .end => unreachable,
    }

    tok.* = copy;
    return token;
}

pub const DerserializeLineError = error{
    InvalidBoolValue,
    InvalidEnumValue,
    InvalidField,
    InvalidFloatValue,
    InvalidIndex,
    InvalidIntValue,
} || ExpectError;

/// Parses tokens into `T`, where `T` is a union of possible fields/indexs that are valid.
/// This only deserializes up to the next `Token.Tag.value` token and will then return a `T`
/// initialized based on what deserialized.
pub fn deserializeLine(comptime T: type, tok: *Tokenizer) DerserializeLineError!T {
    if (comptime isIndex(T)) {
        const token = try expectToken(tok, .index);
        const index = fmt.parseInt(T.IndexType, token.value, 0) catch return error.InvalidIndex;
        const value = try deserializeLine(T.ValueType, tok);
        return initIndex(index, value);
    }
    if (comptime isField(T)) {
        const token = try expectToken(tok, .field);
        const value = try deserializeLine(T.ValueType, tok);
        return initField(token.value, value);
    }

    switch (T) {
        []const u8 => return (try expectToken(tok, .value)).value,
        else => {},
    }

    switch (@typeInfo(T)) {
        .Float => {
            const token = try expectToken(tok, .value);
            return fmt.parseFloat(T, token.value) catch return error.InvalidFloatValue;
        },
        .Int => {
            const token = try expectToken(tok, .value);
            return fmt.parseInt(T, token.value, 0) catch return error.InvalidIntValue;
        },
        .Enum => {
            const token = try expectToken(tok, .value);
            return meta.stringToEnum(T, token.value) orelse return error.InvalidEnumValue;
        },
        .Bool => {
            const res = deserializeLine(Bool, tok) catch return error.InvalidBoolValue;
            return res == .@"true";
        },
        .Union => |info| {
            const token = try expectToken(tok, .field);
            inline for (info.fields) |field| {
                if (mem.eql(u8, field.name, token.value))
                    return @unionInit(T, field.name, try deserializeLine(field.field_type, tok));
            }

            return error.InvalidField;
        },
        else => @compileError("'" ++ @typeName(T) ++ "' is not supported"),
    }
}

fn expectDerserializeLine(str: []const u8, comptime T: type, err_expect: DerserializeLineError!T) !void {
    var tok = tokenize(str);
    const expect = err_expect catch |err| {
        try testing.expectError(err, deserializeLine(T, &tok));
        return;
    };
    const actual = deserializeLine(T, &tok) catch |err| {
        try testing.expect(false);
        unreachable;
    };

    try testing.expectEqual(expect, actual);
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
    // try expectDerserializeLine(".string=string\n", T, T{ .string = "string" });
    try expectDerserializeLine(".index[2]=4\n", T, T{ .index = .{ .index = 2, .value = 4 } });
    try expectDerserializeLine("[1]\n", T, error.ExpectedField);
    try expectDerserializeLine(".int.a=1\n", T, error.ExpectedValue);
    try expectDerserializeLine(".index.a=1\n", T, error.ExpectedIndex);
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
    if (comptime isIndex(T)) {
        var copy = prefix.*;
        copy.writer().print("[{}]", .{value.index}) catch unreachable;
        try serializeHelper(writer, &copy, value.value);
        return;
    }
    if (comptime isIntMap(T)) {
        var it = value.iterator();
        while (it.next()) |entry| {
            var copy = prefix.*;
            copy.writer().print("[{}]", .{entry.key_ptr.*}) catch unreachable;
            try serializeHelper(writer, &copy, entry.value_ptr.*);
        }
        return;
    }
    if (comptime isArrayList(T)) {
        return serializeHelper(writer, prefix, value.items);
    }
    if (comptime isField(T)) {
        var copy = prefix.*;
        copy.writer().print(".{s}", .{value.name}) catch unreachable;
        try serializeHelper(writer, &copy, value.value);
        return;
    }

    switch (@typeInfo(T)) {
        .Void, .Null => {},
        .Bool => try serializeHelper(writer, prefix, string(if (value) "true" else "false")),
        .Int,
        .Float,
        .ComptimeInt,
        .ComptimeFloat,
        => try writer.print("{s}={d}\n", .{ prefix.getWritten(), value }),
        .Optional => if (value) |v| {
            try serializeHelper(writer, prefix, v);
        } else {},
        .Pointer => |info| switch (info.size) {
            .One => try serializeHelper(writer, prefix, value.*),
            .Slice => for (value) |v, i| {
                var copy = prefix.*;
                copy.writer().print("[{}]", .{i}) catch unreachable;
                try serializeHelper(writer, &copy, v);
            },
            else => @compileError("Type '" ++ @typeName(T) ++ "' not supported"),
        },
        .Array => |info| {
            var l: usize = info.len;
            try serializeHelper(writer, prefix, value[0..l]);
        },
        .Enum => if (@hasDecl(T, "format")) {
            try writer.print("{s}={}\n", .{ prefix.getWritten(), value });
        } else {
            try serializeHelper(writer, prefix, string(@tagName(value)));
        },
        .Union => |info| {
            const Tag = meta.TagType(T);
            if (@hasDecl(T, "format")) {
                try writer.print("{s}={}\n", .{ prefix.getWritten(), value });
            } else inline for (info.fields) |field| {
                if (@field(Tag, field.name) == value) {
                    var copy = prefix.*;
                    copy.writer().print(".{s}", .{field.name}) catch unreachable;
                    try serializeHelper(writer, &copy, @field(value, field.name));
                    return;
                }
            }
            unreachable;
        },
        .Struct => |info| if (@hasDecl(T, "format")) {
            try writer.print("{s}={}\n", .{ prefix.getWritten(), value });
        } else inline for (info.fields) |field| {
            var copy = prefix.*;
            copy.writer().print(".{s}", .{field.name}) catch unreachable;
            try serializeHelper(writer, &copy, @field(value, field.name));
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
        d: String = string("abcd"),
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
