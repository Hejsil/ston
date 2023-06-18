const std = @import("std");

const debug = std.debug;
const math = std.math;
const mem = std.mem;

const Parser = @This();

str: [:0]const u8,
i: usize = 0,

pub fn handle(parser: *Parser) Handle(.{}) {
    return .{ .parser = parser };
}

pub fn eatChar(parser: *Parser, char: u8) bool {
    if (parser.peek() != char)
        return false;

    parser.advance(1);
    return true;
}

pub fn eat(parser: *Parser) u8 {
    defer parser.advance(1);
    return parser.peek();
}

pub fn peek(parser: Parser) u8 {
    return parser.str[parser.i];
}

pub fn advance(parser: *Parser, num: usize) void {
    parser.i += num;
}

const Sign = enum { pos, neg };
fn intWithSign(parser: *Parser, comptime T: type, comptime sign: Sign, term: u8) !T {
    const add = switch (sign) {
        .pos => math.add,
        .neg => math.sub,
    };
    const max_digits = comptime switch (sign) {
        .pos => std.fmt.count("{}", .{math.maxInt(T)}),
        .neg => std.fmt.count("{}", .{math.minInt(T)}) - 1,
    };
    const base: T = switch (max_digits) {
        0, 1 => math.maxInt(T),
        else => 10,
    };

    const first = parser.eat() -% '0';
    if (first > 9)
        return error.InvalidInt;

    var res: T = math.cast(T, first) orelse return error.InvalidInt;
    comptime var i = 1;
    inline while (i < comptime @min(4, max_digits) - 1) : (i += 1) {
        const c = parser.eat();
        if (c == term)
            return res;

        const digit = math.cast(T, c -% '0') orelse return error.InvalidInt;
        if (digit > 9) return error.InvalidInt;
        res *= base;
        res = add(T, res, digit) catch unreachable;
    }

    while (true) {
        const c = parser.eat();
        if (c == term)
            return res;

        const digit = math.cast(T, c -% '0') orelse return error.InvalidInt;
        if (digit > 9) return error.InvalidInt;
        res = try math.mul(T, res, base);
        res = try add(T, res, digit);
    }
}

pub fn hasBytesLeft(parser: Parser, bytes: usize) bool {
    return parser.i + bytes <= parser.str.len;
}

pub const Assetions = struct {
    prefix_has_been_eaten: bool = false,
    bounds_checked: bool = false,
};

pub fn Handle(comptime assertions: Assetions) type {
    return struct {
        parser: *Parser,

        pub fn assert(h: @This(), comptime new: Assetions) Handle(new) {
            return .{ .parser = h.parser };
        }

        pub fn assertPrefixEaten(h: @This(), comptime new: bool) Handle(.{
            .prefix_has_been_eaten = new,
            .bounds_checked = assertions
                .bounds_checked,
        }) {
            return h.assert(.{
                .prefix_has_been_eaten = new,
                .bounds_checked = assertions
                    .bounds_checked,
            });
        }

        pub fn assertBoundsChecked(h: @This(), comptime new: bool) Handle(.{
            .prefix_has_been_eaten = assertions.prefix_has_been_eaten,
            .bounds_checked = new,
        }) {
            return h.assert(.{
                .prefix_has_been_eaten = assertions.prefix_has_been_eaten,
                .bounds_checked = new,
            });
        }

        pub fn index(h: @This(), comptime T: type) !T {
            if (!h.eatPrefix('['))
                return error.InvalidIndex;
            const res = h.parser.intWithSign(usize, .pos, ']') catch return error.InvalidIndex;
            return math.cast(T, res) orelse return error.InvalidIndex;
        }

        pub fn field(h: @This(), comptime name: []const u8) bool {
            return h.fieldDedupe(name.len, name[0..name.len].*);
        }

        fn fieldDedupe(h: @This(), comptime len: usize, comptime name: [len]u8) bool {
            h.assertPrefix('.');
            if (assertions.prefix_has_been_eaten) {
                if (!h.startsWith(len, &name))
                    return false;

                h.parser.advance(len);
            } else {
                if (!h.startsWith(len + 1, "." ++ name))
                    return false;

                h.parser.advance(len + 1);
            }

            return true;
        }

        pub fn enumValue(h: @This(), comptime T: type) !T {
            h.assertPrefix('=');
            if (assertions.prefix_has_been_eaten) {
                inline for (@typeInfo(T).Enum.fields) |f| {
                    if (h.eatString(f.name.len + 1, f.name ++ "\n"))
                        return @field(T, f.name);
                }
            } else {
                inline for (@typeInfo(T).Enum.fields) |f| {
                    if (h.eatString(f.name.len + 2, "=" ++ f.name ++ "\n"))
                        return @field(T, f.name);
                }
            }

            return error.InvalidEnumValue;
        }

        pub fn intValue(h: @This(), comptime T: type) !T {
            if (!h.eatPrefix('='))
                return error.InvalidIntValue;

            if (@typeInfo(T).Int.signedness == .signed and h.eatChar('-'))
                return h.parser.intWithSign(T, .neg, '\n') catch return error.InvalidIntValue;
            return h.parser.intWithSign(T, .pos, '\n') catch return error.InvalidIntValue;
        }

        pub fn value(h: @This()) ![:'\n']const u8 {
            if (!h.eatPrefix('='))
                return error.InvalidValue;

            const start = h.parser.i;
            const nl = mem.indexOfScalarPos(u8, h.parser.str, h.parser.i, '\n') orelse
                return error.InvalidValue;

            h.parser.i = nl + 1;
            return h.parser.str[start..nl :'\n'];
        }

        fn eatPrefix(h: @This(), prefix: u8) bool {
            if (assertions.prefix_has_been_eaten) {
                h.assertPrefix(prefix);
                return true;
            } else {
                return h.parser.eatChar(prefix);
            }
        }

        fn assertPrefix(h: @This(), prefix: u8) void {
            if (assertions.prefix_has_been_eaten)
                debug.assert(h.parser.str[h.parser.i - 1] == prefix);
        }

        fn eatString(h: @This(), comptime len: usize, str: *const [len]u8) bool {
            if (h.startsWith(len, str)) {
                h.parser.advance(len);
                return true;
            }

            return false;
        }

        fn startsWith(h: @This(), comptime len: usize, prefix: *const [len]u8) bool {
            if (!h.hasBytesLeft(len))
                return false;

            return fastEql(len, h.parser.str[h.parser.i..][0..len], prefix);
        }

        pub fn hasBytesLeft(h: @This(), bytes: usize) bool {
            if (assertions.bounds_checked) {
                debug.assert(h.parser.hasBytesLeft(bytes));
                return true;
            } else {
                return h.parser.hasBytesLeft(bytes);
            }
        }
    };
}

fn fastEql(comptime len: usize, a: *const [len]u8, b: *const [len]u8) bool {
    if (len == 0)
        return true;

    comptime var i = 1;
    inline while (i <= len and i <= 64) : (i *= 2) {
        if (i == len) {
            const Int = std.meta.Int(.unsigned, i * 8);
            const a_int = @bitCast(Int, @as([i]u8, a[0..i].*));
            const b_int = @bitCast(Int, @as([i]u8, b[0..i].*));
            return a_int == b_int;
        }
    }

    const len_lower = comptime blk: {
        var res: usize = 1;
        while (res < len) : (res *= 2) {}
        break :blk res / 2;
    };

    return fastEql(len_lower, a[0..len_lower], b[0..len_lower]) and fastEql(
        len - len_lower,
        a[len_lower..],
        b[len_lower..],
    );
}
