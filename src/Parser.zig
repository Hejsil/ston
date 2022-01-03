const std = @import("std");

const math = std.math;
const mem = std.mem;

const Parser = @This();

str: []const u8,
i: usize = 0,

pub fn index(parser: *Parser, comptime T: type) !T {
    if (!parser.eatChar('['))
        return error.InvalidIndex;

    const res = parser.intWithSign(usize, .pos, ']') catch return error.InvalidIndex;
    return math.cast(T, res) catch return error.InvalidIndex;
}

pub fn field(parser: *Parser, comptime name: []const u8) !void {
    const str = parser.rest();

    comptime std.debug.assert(name.len != 0);
    if (!startsWith(str, "." ++ name ++ "[") and
        !startsWith(str, "." ++ name ++ ".") and
        !startsWith(str, "." ++ name ++ "="))
        return error.InvalidField;

    parser.i += name.len + 1;
}

pub fn anyField(parser: *Parser) ![]const u8 {
    const start = parser.i;
    const end = mem.indexOfScalarPos(u8, parser.str, parser.i + 1, "[.=") orelse
        return error.InvalidField;
    if (parser.str[start] != '.')
        return error.InvalidValue;

    parser.i = end;
    return parser.str[start + 1 .. end];
}

pub fn value(parser: *Parser) ![:'\n']const u8 {
    const start = parser.i;
    const end = mem.indexOfScalarPos(u8, parser.str, parser.i, '\n') orelse
        return error.InvalidValue;
    if (parser.str[start] != '=')
        return error.InvalidValue;

    parser.i = end + 1;
    return parser.str[start + 1 .. end :'\n'];
}

pub fn enumValue(parser: *Parser, comptime T: type) !T {
    inline for (@typeInfo(T).Enum.fields) |f| {
        if (parser.eatString("=" ++ f.name ++ "\n"))
            return @field(T, f.name);
    }

    return error.InvalidEnumValue;
}

pub fn intValue(parser: *Parser, comptime T: type) !T {
    if (!parser.eatChar('='))
        return error.InvalidIntValue;

    if (@typeInfo(T).Int.signedness == .signed and parser.eatChar('-'))
        return parser.intWithSign(T, .neg, '\n') catch return error.InvalidIntValue;
    return parser.intWithSign(T, .pos, '\n') catch return error.InvalidIntValue;
}

const Sign = enum { pos, neg };
fn intWithSign(parser: *Parser, comptime T: type, comptime sign: Sign, comptime term: u8) !T {
    const add = switch (sign) {
        .pos => math.add,
        .neg => math.sub,
    };

    const first = parser.eatRange('0', '9') orelse return error.InvalidInt;
    var res = try math.cast(T, first - '0');

    for (parser.rest()) |c, i| switch (c) {
        '0'...'9' => {
            const digit = try math.cast(T, c - '0');
            const base = try math.cast(T, @as(u8, 10));
            res = try math.mul(T, res, base);
            res = try add(T, res, digit);
        },
        term => {
            parser.i += i + 1;
            return res;
        },
        else => return error.InvalidInt,
    };

    return error.InvalidInt;
}

pub fn eat(parser: *Parser) ?u8 {
    defer parser.i += 1;
    return parser.peek();
}

pub fn eatChar(parser: *Parser, char: u8) bool {
    const first = parser.peek() orelse return false;
    if (first != char)
        return false;

    parser.i += 1;
    return true;
}

pub fn eatRange(parser: *Parser, start: u8, end: u8) ?u8 {
    const char = parser.peek() orelse return null;
    if (char < start or end < char)
        return null;

    parser.i += 1;
    return char;
}

pub fn eatString(parser: *Parser, comptime str: []const u8) bool {
    if (startsWith(parser.rest(), str)) {
        parser.i += str.len;
        return true;
    }

    return false;
}

fn startsWith(str: []const u8, comptime prefix: []const u8) bool {
    if (str.len < prefix.len)
        return false;

    comptime var i = 0;
    comptime var blk = 8;
    inline while (blk != 0) : (blk /= 2) {
        inline while (i + blk <= prefix.len) : (i += blk) {
            const Int = std.meta.Int(.unsigned, blk * 8);
            if (@bitCast(Int, str[i..][0..blk].*) != @bitCast(Int, prefix[i..][0..blk].*))
                return false;
        }
    }

    return true;
}

pub fn peek(parser: *Parser) ?u8 {
    if (parser.str.len <= parser.i)
        return null;

    return parser.str[parser.i];
}

pub fn rest(parser: Parser) []const u8 {
    return parser.str[parser.i..];
}
