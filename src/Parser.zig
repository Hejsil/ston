const std = @import("std");

const math = std.math;
const mem = std.mem;

const Parser = @This();

str: [:0]const u8,
i: usize = 0,

pub fn index(parser: *Parser, comptime T: type) !T {
    if (!parser.eatChar('['))
        return error.InvalidIndex;

    const res = parser.intWithSign(usize, .pos, ']') catch return error.InvalidIndex;
    return math.cast(T, res) catch return error.InvalidIndex;
}

pub fn field(parser: *Parser, comptime name: []const u8) !void {
    return parser.fieldDedupe(name[0..name.len].*);
}

fn fieldDedupe(parser: *Parser, comptime name: anytype) !void {
    comptime std.debug.assert(name.len != 0);
    if (!parser.startsWith(("." ++ name ++ "[").*) and
        !parser.startsWith(("." ++ name ++ ".").*) and
        !parser.startsWith(("." ++ name ++ "=").*))
        return error.InvalidField;

    parser.i += name.len + 1;
}

pub fn anyField(parser: *Parser) ![]const u8 {
    if (parser.eat() != '.')
        return error.InvalidValue;

    const start = parser.i;
    while (true) switch (parser.peek()) {
        '[', '.', '=' => break,
        0 => return error.InvalidValue,
        else => parser.i += 1,
    };

    return parser.str[start..parser.i];
}

pub fn value(parser: *Parser) ![:'\n']const u8 {
    if (parser.eat() != '=')
        return error.InvalidValue;

    const start = parser.i;
    while (true) switch (parser.eat()) {
        '\n' => break,
        0 => return error.InvalidValue,
        else => {},
    };

    return parser.str[start .. parser.i - 1 :'\n'];
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

    while (true) {
        const c = parser.eat();
        switch (c) {
            '0'...'9' => {
                const digit = try math.cast(T, c - '0');
                const base = try math.cast(T, @as(u8, 10));
                res = try math.mul(T, res, base);
                res = try add(T, res, digit);
            },
            term => return res,
            else => return error.InvalidInt,
        }
    }
}

fn eat(parser: *Parser) u8 {
    defer parser.i += 1;
    return parser.peek();
}

fn eatChar(parser: *Parser, char: u8) bool {
    if (parser.peek() != char)
        return false;

    parser.i += 1;
    return true;
}

fn eatRange(parser: *Parser, start: u8, end: u8) ?u8 {
    const char = parser.peek();
    if (char < start or end < char)
        return null;

    parser.i += 1;
    return char;
}

fn eatString(parser: *Parser, comptime str: []const u8) bool {
    if (parser.startsWith(str[0..str.len].*)) {
        parser.i += str.len;
        return true;
    }

    return false;
}

fn startsWith(parser: Parser, comptime prefix: anytype) bool {
    if (parser.str.len - parser.i < prefix.len)
        return false;

    comptime var i = 0;
    comptime var blk = 16;
    inline while (blk != 0) : (blk /= 2) {
        inline while (i + blk <= prefix.len) : (i += blk) {
            const Int = std.meta.Int(.unsigned, blk * 8);
            if (@bitCast(Int, parser.str[parser.i + i ..][0..blk].*) !=
                @bitCast(Int, @as([blk]u8, prefix[i..][0..blk].*)))
                return false;
        }
    }

    return true;
}

fn peek(parser: *Parser) u8 {
    return parser.str[parser.i];
}

pub fn rest(parser: Parser) [:0]const u8 {
    return parser.str[parser.i..];
}
