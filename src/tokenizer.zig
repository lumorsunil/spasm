const std = @import("std");
const Allocator = std.mem.Allocator;

const Tokenizer = struct {
    arena: std.heap.ArenaAllocator,
    reader: *std.Io.Reader,
    location: Location = .{},
    marker: Location = .{},
    read_buffer: [1024]u8 = undefined,
    peek_buffer: [256]u8 = undefined,
    peek_len: u8 = 0,

    pub fn init(allocator: Allocator, reader: *std.Io.Reader) @This() {
        return .{
            .arena = .init(allocator),
            .reader = reader,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }

    pub fn next(self: *@This()) !Token {}

    fn skipWhiteSpace(self: *@This()) !void {
        while (true) {
            const p = try self.peek(1);
            if (p.len == 0) return;
            if (!std.ascii.isWhitespace(p[0])) return;

            try self.consume(1);
        }
    }

    fn readSource(self: *@This(), n: usize) ![]const u8 {
        const peek_len = @min(self.peek_len, n);
        self.peek_len -= peek_len;
        var read_len = n - peek_len;

        @memcpy(self.read_buffer[0..peek_len], self.peek_buffer[0..peek_len]);
        read_len = try self.reader.readSliceShort(self.read_buffer[peek_len .. peek_len + read_len]);

        return self.read_buffer[0 .. peek_len + read_len];
    }

    fn peek(self: *@This(), n: usize) ![]const u8 {
        const peek_len = @min(self.peek_len, n);
        var read_len = n - peek_len;
        read_len = try self.reader.readSliceShort(self.peek_buffer[peek_len .. peek_len + read_len]);
        self.peek_len += read_len;
        return self.peek_buffer[0..self.peek_len];
    }

    fn consume(self: *@This(), n: usize) ![]const u8 {
        const read_source = try self.readSource(n);
        self.moveCursor(read_source);
        return read_source;
    }

    fn moveCursor(self: *@This(), source: []const u8) void {
        self.location.index += source.len;
        for (source) |c| switch (c) {
            '\n' => {
                self.location.line += 1;
                self.location.column = 1;
            },
            else => self.location.column += 1,
        };
    }

    fn mark(self: *@This()) void {
        self.marker = self.location;
    }

    fn mkToken(self: *@This(), tag: Token.Tag, len: usize) !Token {
        const lexeme = try self.arena.allocator().dupe(u8, self.read_buffer[0..len]);
        const start = self.marker;
        const end = self.marker;

        return .{
            .tag = tag,
            .lexeme = lexeme,
            .start = start,
            .end = end,
        };
    }
};

pub const Location = struct {
    index: usize = 0,
    line: usize = 1,
    column: usize = 1,
};

pub const Token = struct {
    tag: Tag,
    lexeme: []const u8,
    start: Location,
    end: Location,

    pub const Tag = enum { eof };
};
