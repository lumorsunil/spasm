const std = @import("std");
const Allocator = std.mem.Allocator;

const TokenizeReader = struct {
    reader: *std.Io.Reader,
    cursor: Location = .{},
    marker: Location = .{},

    fn init(reader: *std.Io.Reader) @This() {
        return .{
            .reader = reader,
        };
    }

    fn mark(self: *@This()) void {
        const len = self.cursorLen();
        self.reader.toss(len);
        self.marker = self.cursor;
    }

    fn produce(self: *@This(), allocator: Allocator) Error!TokenizeReaderSlice {
        const start = self.marker;
        const end = self.cursor;
        const len = end.index - start.index;
        const text = try allocator.dupe(u8, try self.reader.take(len));

        self.marker = self.cursor;

        return .{
            .start = start,
            .end = end,
            .text = text,
        };
    }

    fn skipWhiteSpace(self: *@This()) Error!void {
        try self.takeWhile(std.ascii.isWhitespace);
    }

    fn consume(self: *@This(), n: u8) Error![]const u8 {
        const read_source = try self.peek(n);
        self.moveCursor(read_source);
        return read_source;
    }

    fn takeWhile(self: *@This(), predicate: *const fn (u8) bool) Error!void {
        while (predicate(try self.peekChar() orelse return)) {
            _ = try self.consume(1);
        }
    }

    fn takeWhileCtx(
        self: *@This(),
        ctx: anytype,
        predicate: *const fn (@TypeOf(ctx), u8) bool,
    ) Error!void {
        while (predicate(ctx, try self.peekChar() orelse return)) {
            _ = try self.consume(1);
        }
    }

    fn moveCursor(self: *@This(), source: []const u8) void {
        self.cursor.index += source.len;
        for (source) |c| switch (c) {
            '\n' => {
                self.cursor.line += 1;
                self.cursor.column = 1;
            },
            else => self.cursor.column += 1,
        };
    }

    fn peekChar(self: *@This()) Error!?u8 {
        const ps = self.peek(1) catch |err| switch (err) {
            std.Io.Reader.Error.EndOfStream => return null,
            else => return err,
        };
        return ps[0];
    }

    fn peek(self: *@This(), n: u8) Error![]const u8 {
        const start = self.cursorLen();
        return (try self.reader.peek(n + start))[start..];
    }

    fn cursorLen(self: @This()) u8 {
        const start = self.marker;
        const end = self.cursor;
        return @intCast(end.index - start.index);
    }

    pub const TokenizeReaderSlice = struct {
        start: Location,
        end: Location,
        text: []const u8,
    };

    pub const Error = std.Io.Reader.Error || Allocator.Error;
};

test "TokenizeReader peek empty" {
    const source = "";
    var reader = std.Io.Reader.fixed(source);
    var fixture: TokenizeReader = .init(&reader);
    const expected: TokenizeReader = .init(&reader);

    const actual = fixture.peek(1);

    try std.testing.expectError(TokenizeReader.Error.EndOfStream, actual);

    try std.testing.expectEqual(expected.marker, fixture.marker);
    try std.testing.expectEqual(expected.cursor, fixture.cursor);
}

test "TokenizeReader peek whitespace" {
    const source = " ";
    var reader = std.Io.Reader.fixed(source);
    var fixture: TokenizeReader = .init(&reader);
    const expected: TokenizeReader = .init(&reader);

    const actual = try fixture.peek(1);

    try std.testing.expectEqualStrings(" ", actual);
    try std.testing.expectError(TokenizeReader.Error.EndOfStream, fixture.peek(2));
    try std.testing.expectEqual(expected.marker, fixture.marker);
    try std.testing.expectEqual(expected.cursor, fixture.cursor);
}

test "TokenizeReader consume empty" {
    const source = "";
    var reader = std.Io.Reader.fixed(source);
    var fixture: TokenizeReader = .init(&reader);
    const expected: TokenizeReader = .init(&reader);

    const actual = fixture.consume(1);

    try std.testing.expectError(TokenizeReader.Error.EndOfStream, actual);
    try std.testing.expectEqual(expected.marker, fixture.marker);
    try std.testing.expectEqual(expected.cursor, fixture.cursor);
}

test "TokenizeReader consume whitespace" {
    const source = " ";
    var reader = std.Io.Reader.fixed(source);
    var fixture: TokenizeReader = .init(&reader);
    var expected: TokenizeReader = .init(&reader);

    const actual = try fixture.consume(1);
    expected.cursor.index = 1;
    expected.cursor.column = 2;

    try std.testing.expectEqualStrings(" ", actual);
    try std.testing.expectError(TokenizeReader.Error.EndOfStream, fixture.consume(1));
    try std.testing.expectEqual(expected.marker, fixture.marker);
    try std.testing.expectEqual(expected.cursor, fixture.cursor);
}

test "TokenizeReader produce whitespace" {
    const source = " ";
    var reader = std.Io.Reader.fixed(source);
    var fixture: TokenizeReader = .init(&reader);
    var expected: TokenizeReader = .init(&reader);

    _ = try fixture.consume(1);
    const actual = try fixture.produce(std.testing.allocator);
    defer std.testing.allocator.free(actual.text);
    expected.marker.index = 1;
    expected.marker.column = 2;
    expected.cursor = expected.marker;

    try std.testing.expectEqualStrings(" ", actual.text);
    try std.testing.expectEqualDeep(actual.start, Location{
        .index = 0,
        .line = 1,
        .column = 1,
    });
    try std.testing.expectEqualDeep(actual.end, Location{
        .index = 1,
        .line = 1,
        .column = 2,
    });
    try std.testing.expectError(TokenizeReader.Error.EndOfStream, fixture.consume(1));
    try std.testing.expectEqual(expected.marker, fixture.marker);
    try std.testing.expectEqual(expected.cursor, fixture.cursor);
}

test "TokenizeReader produce whitespace with lines" {
    const source = " \n\n ";
    var reader = std.Io.Reader.fixed(source);
    var fixture: TokenizeReader = .init(&reader);
    var expected: TokenizeReader = .init(&reader);

    _ = try fixture.consume(4);
    const actual = try fixture.produce(std.testing.allocator);
    defer std.testing.allocator.free(actual.text);
    expected.marker.index = 4;
    expected.marker.column = 2;
    expected.marker.line = 3;
    expected.cursor = expected.marker;

    try std.testing.expectEqualStrings(" \n\n ", actual.text);
    try std.testing.expectEqualDeep(actual.start, Location{
        .index = 0,
        .line = 1,
        .column = 1,
    });
    try std.testing.expectEqualDeep(actual.end, Location{
        .index = 4,
        .line = 3,
        .column = 2,
    });
    try std.testing.expectError(TokenizeReader.Error.EndOfStream, fixture.consume(1));
    try std.testing.expectEqual(expected.marker, fixture.marker);
    try std.testing.expectEqual(expected.cursor, fixture.cursor);
}

test "TokenizeReader produce multiple" {
    const source = " \n";
    var reader = std.Io.Reader.fixed(source);
    var fixture: TokenizeReader = .init(&reader);

    _ = try fixture.consume(1);
    const actual_first = try fixture.produce(std.testing.allocator);
    defer std.testing.allocator.free(actual_first.text);

    try std.testing.expectEqualStrings(" ", actual_first.text);
    try std.testing.expectEqualDeep(actual_first.start, Location{
        .index = 0,
        .line = 1,
        .column = 1,
    });
    try std.testing.expectEqualDeep(actual_first.end, Location{
        .index = 1,
        .line = 1,
        .column = 2,
    });

    _ = try fixture.consume(1);
    const actual_second = try fixture.produce(std.testing.allocator);
    defer std.testing.allocator.free(actual_second.text);

    try std.testing.expectEqualStrings("\n", actual_second.text);
    try std.testing.expectEqualDeep(actual_second.start, Location{
        .index = 1,
        .line = 1,
        .column = 2,
    });
    try std.testing.expectEqualDeep(actual_second.end, Location{
        .index = 2,
        .line = 2,
        .column = 1,
    });

    try std.testing.expectError(TokenizeReader.Error.EndOfStream, fixture.consume(1));
    try std.testing.expectEqual(Location{
        .index = 2,
        .line = 2,
        .column = 1,
    }, fixture.marker);
    try std.testing.expectEqual(fixture.marker, fixture.cursor);
}

test "TokenizeReader peekChar empty" {
    const source = "";
    var reader = std.Io.Reader.fixed(source);
    var fixture: TokenizeReader = .init(&reader);
    const expected: TokenizeReader = .init(&reader);

    const actual = fixture.peekChar();

    try std.testing.expectEqual(null, actual);

    try std.testing.expectEqual(expected.marker, fixture.marker);
    try std.testing.expectEqual(expected.cursor, fixture.cursor);
}

test "TokenizeReader skipWhiteSpace empty" {
    const source = "";
    var reader = std.Io.Reader.fixed(source);
    var fixture: TokenizeReader = .init(&reader);
    const expected: TokenizeReader = .init(&reader);

    try fixture.skipWhiteSpace();

    try std.testing.expectEqual(expected.marker, fixture.marker);
    try std.testing.expectEqual(expected.cursor, fixture.cursor);
}

test "TokenizeReader skipWhiteSpace, mark then peekChar" {
    const source = " \n  \n\n ";
    var reader = std.Io.Reader.fixed(source);
    var fixture: TokenizeReader = .init(&reader);

    try fixture.skipWhiteSpace();

    try std.testing.expectEqualDeep(Location{
        .index = 7,
        .line = 4,
        .column = 2,
    }, fixture.cursor);

    fixture.mark();
    try std.testing.expectEqualDeep(fixture.marker, fixture.cursor);

    const actual = try fixture.peekChar();

    try std.testing.expectFmt("null", "{?c}", .{actual});
}

pub const Tokenizer = struct {
    arena: std.heap.ArenaAllocator,
    reader: TokenizeReader,

    pub fn init(allocator: Allocator, reader: *std.Io.Reader) @This() {
        return .{
            .arena = .init(allocator),
            .reader = .init(reader),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }

    pub fn next(self: *@This()) Error!Token {
        try self.reader.skipWhiteSpace();

        self.reader.mark();

        const p = try self.reader.peekChar() orelse return self.mkToken(.eof);

        if (try self.tryIdentifier(p)) |identifier| return identifier;
        if (try self.tryString(p)) |string| return string;
        if (try self.tryNumber(p)) |number| return number;

        _ = try self.reader.consume(1);

        return switch (p) {
            '=' => self.mkToken(.equal),
            ':' => self.mkToken(.colon),
            '{' => self.mkToken(.open_brace),
            '}' => self.mkToken(.close_brace),
            '[' => self.mkToken(.open_bracket),
            ']' => self.mkToken(.close_bracket),
            else => Error.UnknownToken,
        };
    }

    fn tryIdentifier(self: *@This(), first: u8) Error!?Token {
        if (!isStartOfIdentifier(first)) return null;
        _ = try self.reader.consume(1);
        try self.reader.takeWhile(isIdentifierTail);
        return try self.mkToken(.identifier);
    }

    fn isStartOfIdentifier(c: u8) bool {
        return std.ascii.isAlphabetic(c);
    }

    fn isIdentifierTail(c: u8) bool {
        return std.ascii.isAlphanumeric(c);
    }

    fn tryString(self: *@This(), first: u8) Error!?Token {
        if (first != '"') return null;
        _ = try self.reader.consume(1);

        while (true) {
            const c = try self.reader.peekChar() orelse return Error.UnterminatedString;
            _ = try self.reader.consume(1);
            switch (c) {
                '\\' => {
                    _ = try self.reader.peekChar() orelse return Error.UnterminatedString;
                    _ = try self.reader.consume(1);
                },
                '"' => break,
                else => continue,
            }
        }

        return try self.mkToken(.string);
    }

    pub const NumberMode = enum {
        hexadecimal,
        octal,
        binary,
        decimal,

        pub fn fromSelector(c: u8) ?@This() {
            return switch (c) {
                'x' => .hexadecimal,
                'o' => .octal,
                'b' => .binary,
                else => if (std.ascii.isDigit(c)) .decimal else null,
            };
        }

        pub fn toBase(self: @This()) u5 {
            return switch (self) {
                .hexadecimal => 16,
                .octal => 8,
                .binary => 2,
                .decimal => 10,
            };
        }

        pub fn isDigit(self: @This(), c: u8) bool {
            return switch (self) {
                .hexadecimal => std.ascii.isHex(c),
                .octal => c >= '0' and c <= '7',
                .binary => c >= '0' and c <= '1',
                .decimal => std.ascii.isDigit(c),
            };
        }
    };

    fn tryNumber(self: *@This(), first: u8) Error!?Token {
        if (!isStartOfNumber(first)) return null;
        _ = try self.reader.consume(1);

        const second = try self.reader.peekChar() orelse {
            return try self.mkToken(.number);
        };
        const mode = NumberMode.fromSelector(second) orelse return try self.mkToken(.number);

        _ = try self.reader.consume(1);
        const third = try self.reader.peekChar() orelse {
            return Error.UnterminatedNumber;
        };
        _ = try self.reader.consume(1);
        if (!mode.isDigit(third)) return Error.UnterminatedNumber;

        try self.reader.takeWhileCtx(mode, NumberMode.isDigit);

        return try self.mkToken(.number);
    }

    fn isStartOfNumber(c: u8) bool {
        return std.ascii.isDigit(c);
    }

    fn mkToken(self: *@This(), tag: Token.Tag) Error!Token {
        const slice = try self.reader.produce(self.arena.allocator());

        return .{
            .tag = tag,
            .lexeme = slice.text,
            .start = slice.start,
            .end = slice.end,
        };
    }

    pub const Error = error{
        UnknownToken,
        UnterminatedString,
        UnterminatedNumber,
    } || Allocator.Error || TokenizeReader.Error;
};

pub const Location = struct {
    index: usize = 0,
    line: usize = 1,
    column: usize = 1,

    pub fn init(index: usize, line: usize, column: usize) @This() {
        return .{ .index = index, .line = line, .column = column };
    }
};

pub const Range = struct {
    start: Location,
    end: Location,

    pub fn init(start: Location, end: Location) @This() {
        return .{ .start = start, .end = end };
    }
};

pub const Token = struct {
    tag: Tag,
    lexeme: []const u8,
    start: Location,
    end: Location,

    pub fn range(self: @This()) Range {
        return .init(self.start, self.end);
    }

    pub const Tag = enum {
        identifier,
        equal,
        string,
        open_brace,
        close_brace,
        open_bracket,
        close_bracket,
        colon,
        number,
        dot,
        eof,
    };
};

test "empty" {
    const source = "";
    var reader = std.Io.Reader.fixed(source);
    var tokenizer: Tokenizer = .init(std.testing.allocator, &reader);
    defer tokenizer.deinit();

    const tok = try tokenizer.next();

    try std.testing.expectEqualStrings("", tok.lexeme);
    try std.testing.expectEqual(.eof, tok.tag);
}

test "empty with whitespace" {
    const source = "  \n\n  \n ";
    var reader = std.Io.Reader.fixed(source);
    var tokenizer: Tokenizer = .init(std.testing.allocator, &reader);
    defer tokenizer.deinit();

    const tok = try tokenizer.next();

    try std.testing.expectEqualStrings("", tok.lexeme);
    try std.testing.expectEqual(.eof, tok.tag);
}

test "identifier" {
    const source = "hello";
    var reader = std.Io.Reader.fixed(source);
    var tokenizer: Tokenizer = .init(std.testing.allocator, &reader);
    defer tokenizer.deinit();

    const tok = try tokenizer.next();

    try std.testing.expectEqualStrings("hello", tok.lexeme);
    try std.testing.expectEqual(.identifier, tok.tag);
    try std.testing.expectEqualDeep(Location{
        .index = 0,
        .line = 1,
        .column = 1,
    }, tok.start);
    try std.testing.expectEqualDeep(Location{
        .index = 5,
        .line = 1,
        .column = 6,
    }, tok.end);
}

test "identifier with whitespace around it" {
    const source = "   \n\n hello \n\n  ";
    var reader = std.Io.Reader.fixed(source);
    var tokenizer: Tokenizer = .init(std.testing.allocator, &reader);
    defer tokenizer.deinit();

    const tok = try tokenizer.next();
    const expected = Token{
        .start = .{
            .index = 6,
            .column = 2,
            .line = 3,
        },
        .end = .{
            .index = 11,
            .column = 7,
            .line = 3,
        },
        .tag = .identifier,
        .lexeme = "hello",
    };
    const eof = try tokenizer.next();

    try std.testing.expectEqualStrings(expected.lexeme, tok.lexeme);
    try std.testing.expectEqualDeep(expected, tok);
    try std.testing.expectEqual(.eof, eof.tag);
}

fn testNumber(
    tokenizer: *Tokenizer,
    lexeme: []const u8,
    start: Location,
    end: Location,
) !void {
    const tok = try tokenizer.next();
    const expected = Token{
        .start = start,
        .end = end,
        .tag = .number,
        .lexeme = lexeme,
    };
    try std.testing.expectEqualStrings(expected.lexeme, tok.lexeme);
    try std.testing.expectEqualDeep(expected, tok);
}

test "number" {
    const source = "0 3 6 0x5 0x1AFE 0b101 0o777";
    var reader = std.Io.Reader.fixed(source);
    var tokenizer: Tokenizer = .init(std.testing.allocator, &reader);
    defer tokenizer.deinit();

    try testNumber(&tokenizer, "0", .init(0, 1, 1), .init(1, 1, 2));
    try testNumber(&tokenizer, "3", .init(2, 1, 3), .init(3, 1, 4));
    try testNumber(&tokenizer, "6", .init(4, 1, 5), .init(5, 1, 6));
    try testNumber(&tokenizer, "0x5", .init(6, 1, 7), .init(9, 1, 10));
    try testNumber(&tokenizer, "0x1AFE", .init(10, 1, 11), .init(16, 1, 17));
    try testNumber(&tokenizer, "0b101", .init(17, 1, 18), .init(22, 1, 23));
    try testNumber(&tokenizer, "0o777", .init(23, 1, 24), .init(28, 1, 29));

    const eof = try tokenizer.next();
    try std.testing.expectEqual(.eof, eof.tag);
}

test "equal" {
    const source = " = ";
    var reader = std.Io.Reader.fixed(source);
    var tokenizer: Tokenizer = .init(std.testing.allocator, &reader);
    defer tokenizer.deinit();

    const tok = try tokenizer.next();
    const eof = try tokenizer.next();

    try std.testing.expectEqualDeep(Location{ .index = 1, .column = 2, .line = 1 }, tok.start);
    try std.testing.expectEqualDeep(Location{ .index = 2, .column = 3, .line = 1 }, tok.end);
    try std.testing.expectEqual(.eof, eof.tag);
}
