const std = @import("std");

const debug = std.debug;
const math = std.math;

pub const Assetions = struct {
    prefix_has_been_eaten: bool = false,
    bounds_check_have_been_performed: bool = false,
};

pub fn Parser(comptime assertions: Assetions) type {
    return struct {
        str: [:0]const u8,
        i: usize = 0,

        pub fn assert(parser: *@This(), comptime new: Assetions) *Parser(new) {
            return @ptrCast(*Parser(new), parser);
        }

        pub fn assertPrefixEaten(parser: *@This(), comptime new: bool) *Parser(.{
            .prefix_has_been_eaten = new,
            .bounds_check_have_been_performed = assertions
                .bounds_check_have_been_performed,
        }) {
            return parser.assert(.{
                .prefix_has_been_eaten = new,
                .bounds_check_have_been_performed = assertions
                    .bounds_check_have_been_performed,
            });
        }

        pub fn assertBoundsCheck(parser: *@This(), comptime new: bool) *Parser(.{
            .prefix_has_been_eaten = assertions.prefix_has_been_eaten,
            .bounds_check_have_been_performed = new,
        }) {
            return parser.assert(.{
                .prefix_has_been_eaten = assertions.prefix_has_been_eaten,
                .bounds_check_have_been_performed = new,
            });
        }

        pub fn index(parser: *@This(), comptime T: type) !T {
            if (!parser.eatPrefix('['))
                return error.InvalidIndex;

            const res = parser.intWithSign(usize, .pos, ']') catch
                return error.InvalidIndex;
            return math.cast(T, res) catch return error.InvalidIndex;
        }

        pub fn field(parser: *@This(), comptime name: []const u8) bool {
            return parser.fieldDedupe(name[0..name.len].*);
        }

        fn fieldDedupe(parser: *@This(), comptime name: anytype) bool {
            parser.assertPrefix('.');
            if (assertions.prefix_has_been_eaten) {
                if (!parser.startsWith(name))
                    return false;

                parser.i += name.len;
            } else {
                if (!parser.startsWith(("." ++ name).*))
                    return false;

                parser.i += name.len + 1;
            }

            return true;
        }

        pub fn enumValue(parser: *@This(), comptime T: type) !T {
            parser.assertPrefix('=');
            if (assertions.prefix_has_been_eaten) {
                inline for (@typeInfo(T).Enum.fields) |f| {
                    if (parser.eatString(f.name ++ "\n"))
                        return @field(T, f.name);
                }
            } else {
                inline for (@typeInfo(T).Enum.fields) |f| {
                    if (parser.eatString("=" ++ f.name ++ "\n"))
                        return @field(T, f.name);
                }
            }

            return error.InvalidEnumValue;
        }

        pub fn intValue(parser: *@This(), comptime T: type) !T {
            if (!parser.eatPrefix('='))
                return error.InvalidIntValue;

            if (@typeInfo(T).Int.signedness == .signed and parser.eatChar('-'))
                return parser.intWithSign(T, .neg, '\n') catch return error.InvalidIntValue;
            return parser.intWithSign(T, .pos, '\n') catch return error.InvalidIntValue;
        }

        pub fn value(parser: *@This()) ![:'\n']const u8 {
            if (!parser.eatPrefix('='))
                return error.InvalidValue;

            const start = parser.i;
            while (true) switch (parser.eat()) {
                '\n' => break,
                0 => return error.InvalidValue,
                else => {},
            };

            return parser.str[start .. parser.i - 1 :'\n'];
        }

        const Sign = enum { pos, neg };
        pub fn intWithSign(parser: *@This(), comptime T: type, comptime sign: Sign, comptime term: u8) !T {
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

        fn eatPrefix(parser: *@This(), prefix: u8) bool {
            if (assertions.prefix_has_been_eaten) {
                parser.assertPrefix(prefix);
                return true;
            } else {
                return parser.eatChar(prefix);
            }
        }

        fn assertPrefix(parser: @This(), prefix: u8) void {
            if (assertions.prefix_has_been_eaten)
                debug.assert(parser.str[parser.i - 1] == prefix);
        }

        fn eatString(parser: *@This(), comptime str: []const u8) bool {
            if (parser.startsWith(str[0..str.len].*)) {
                parser.i += str.len;
                return true;
            }

            return false;
        }

        fn eatRange(parser: *@This(), start: u8, end: u8) ?u8 {
            const char = parser.peek();
            if (char < start or end < char)
                return null;

            parser.i += 1;
            return char;
        }

        fn eatChar(parser: *@This(), char: u8) bool {
            if (parser.peek() != char)
                return false;

            parser.i += 1;
            return true;
        }

        fn eat(parser: *@This()) u8 {
            defer parser.i += 1;
            return parser.peek();
        }

        fn peek(parser: *@This()) u8 {
            return parser.str[parser.i];
        }

        fn startsWith(parser: @This(), comptime prefix: anytype) bool {
            if (!parser.hasBytesLeft(prefix.len))
                return false;

            return startsWithStr(parser.str, parser.i, prefix);
        }

        pub fn hasBytesLeft(parser: @This(), bytes: usize) bool {
            if (assertions.bounds_check_have_been_performed) {
                debug.assert(parser.i + bytes <= parser.str.len);
                return true;
            } else {
                return parser.i + bytes <= parser.str.len;
            }
        }
    };
}

fn startsWithStr(str: []const u8, off: usize, comptime prefix: anytype) bool {
    if (prefix.len == 0)
        return true;

    comptime var i = 1;
    inline while (i <= prefix.len and i <= 64) : (i *= 2) {
        if (i == prefix.len) {
            const Int = std.meta.Int(.unsigned, i * 8);
            const a = @bitCast(Int, @as([i]u8, str[off..][0..i].*));
            const b = @bitCast(Int, @as([i]u8, prefix[0..i].*));
            return a == b;
        }
    }

    const len_lower = comptime blk: {
        var res: usize = 1;
        while (res < prefix.len) : (res *= 2) {}
        break :blk res / 2;
    };
    const len_upper = comptime blk: {
        var res: usize = 1;
        while (len_lower + res < prefix.len) : (res *= 2) {}
        break :blk res;
    };

    return startsWithStr(str, off, prefix[0..len_lower].*) and startsWithStr(
        str,
        off + (prefix.len - len_upper),
        prefix[prefix.len - len_upper .. prefix.len].*,
    );
}
