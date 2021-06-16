const std = @import("std");

const testing = std.testing;

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
