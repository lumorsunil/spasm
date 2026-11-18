const std = @import("std");
const Allocator = std.mem.Allocator;
const ast_mod = @import("ast.zig");
const Node = ast_mod.Node;
const Range = @import("tokenizer.zig").Range;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const Location = @import("tokenizer.zig").Location;

pub const ReaderContainer = struct {
    io: std.Io,
    allocator: Allocator,
    reader_map: std.StringHashMapUnmanaged(std.Io.File.Reader) = .empty,

    pub fn init(io: std.Io, allocator: Allocator) @This() {
        return .{ .io = io, .allocator = allocator };
    }

    pub fn request(self: *@This(), uri: []const u8) Error!*std.Io.File.Reader {
        if (self.reader_map.getPtr(uri)) |cached| return cached;

        const file = try std.Io.Dir.cwd().openFile(self.io, uri, .{});
        errdefer file.close(self.io);

        const file_reader = file.reader(self.io, try self.allocator.alloc(u8, 4096));
        try self.reader_map.put(self.allocator, uri, file_reader);
        return self.reader_map.getPtr(uri).?;
    }

    pub fn dispose(self: *@This(), uri: []const u8) void {
        const entry = self.reader_map.fetchRemove(uri) orelse return;
        entry.value.file.close(self.io);
    }

    pub const Error = error{} || std.Io.File.OpenError || Allocator.Error;
};

pub const Parser = struct {
    allocator: Allocator,
    reader_container: *ReaderContainer,
    breadcrumbs: std.ArrayList(Breadcrumb) = .empty,
    breadcrumb_depth: usize = 0,
    uri: []const u8 = undefined,

    // Snapshottables
    node_id: Node.Id = 0,
    node_map: std.AutoHashMapUnmanaged(Node.Id, Node) = .empty,
    tokenizer: Tokenizer = undefined,
    peek_buffer: std.ArrayList(Token) = .empty,
    diagnostics: std.ArrayList(Diagnostic) = .empty,

    pub fn init(
        allocator: Allocator,
        reader_container: *ReaderContainer,
    ) @This() {
        return .{
            .allocator = allocator,
            .reader_container = reader_container,
        };
    }

    fn nextToken(self: *@This()) Error!Token {
        if (self.peek_buffer.items.len > 0) {
            return self.peek_buffer.orderedRemove(0);
        }

        return try self.tokenizer.next();
    }

    fn peekToken(self: *@This()) Error!Token {
        if (self.peek_buffer.items.len > 0) {
            return self.peek_buffer.items[0];
        }

        const tok = try self.tokenizer.next();
        try self.peek_buffer.append(self.allocator, tok);

        return tok;
    }

    fn reportDiagnostic(
        self: *@This(),
        severity: Diagnostic.Severity,
        range: Range,
        comptime fmt: []const u8,
        args: anytype,
    ) Allocator.Error!void {
        try self.diagnostics.append(self.allocator, .{
            .uri = self.uri,
            .message = try std.fmt.allocPrint(self.allocator, fmt, args),
            .severity = severity,
            .range = range,
        });
    }

    fn crumble(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
        try self.breadcrumbs.append(self.allocator, .{
            .label = try std.fmt.allocPrint(self.allocator, fmt, args),
            .depth = self.breadcrumb_depth,
        });
    }

    fn incBreadcrumbDepth(self: *@This()) void {
        self.breadcrumb_depth += 1;
    }

    fn decBreadcrumbDepth(self: *@This()) void {
        self.breadcrumb_depth -= 1;
    }

    pub fn parse(
        self: *@This(),
        entry_uri: []const u8,
    ) Error!Node {
        try self.crumble("{s}", .{@src().fn_name});
        self.incBreadcrumbDepth();
        defer self.decBreadcrumbDepth();

        self.uri = entry_uri;
        const entry = try self.reader_container.request(entry_uri);
        errdefer self.reader_container.dispose(entry_uri);

        self.tokenizer = Tokenizer.init(self.allocator, &entry.interface);

        const nodes = try self.parseNodes();
        const node_ids = try self.allocator.alloc(Node.Id, nodes.len);
        for (node_ids, nodes) |*node_id, node| node_id.* = node.id;

        return try self.mkNode(.{ .block = .{ .children = node_ids } });
    }

    fn parseNode(self: *@This()) Error!?Node {
        try self.crumble("{s}", .{@src().fn_name});
        self.incBreadcrumbDepth();
        defer self.decBreadcrumbDepth();

        if (try self.tryParse(parseInstruction)) |node| return node;

        const tok = try self.peekToken();
        if (tok.tag == .eof) return null;

        return switch (tok.tag) {
            .identifier => try self.parseIdentifierNode(),
            .number => try self.parseNumberNode(),
            .string => try self.parseStringNode(),
            else => {
                try self.reportDiagnostic(.err, tok.range(), "expected expression, found: {t}", .{tok.tag});
                return Error.UnexpectedToken;
                // try self.skipToNextLine(tok.end.line);
                // return self.parseNode();
            },
        };
    }

    fn skipToNextLine(self: *@This(), cur_line: usize) Error!void {
        try self.crumble("{s}", .{@src().fn_name});

        while (true) {
            const tok = try self.peekToken();
            if (tok.tag == .eof) return;
            if (tok.start.line > cur_line) {
                return;
            }
            _ = try self.nextToken();
        }
    }

    fn tryParse(self: *@This(), f: anytype) !?brk: {
        const ErrorUnion = (@typeInfo(@TypeOf(f)).@"fn".return_type orelse void);
        break :brk @typeInfo(ErrorUnion).error_union.payload;
    } {
        const snapshot = try self.mkSnapshot();

        if (f(self)) |success| {
            return success;
        } else |_| {
            try snapshot.restore(self);
            return null;
        }
    }

    fn parseInstruction(self: *@This()) Error!Node {
        try self.crumble("{s}", .{@src().fn_name});
        self.incBreadcrumbDepth();
        defer self.decBreadcrumbDepth();

        const tok = try self.peekToken();
        if (tok.tag == .eof) {
            try self.reportDiagnostic(.err, tok.range(), "expected instruction, found eof", .{});
            return Error.ExpectedMore;
        }

        return switch (tok.tag) {
            .identifier => {
                _ = try self.nextToken();
                if (std.mem.eql(u8, tok.lexeme, "a")) {
                    _ = try self.expectTag(.equal);
                    const value = try self.parseNode() orelse return Error.ExpectedMore;
                    return try self.mkNode(.{ .instruction = .{
                        .lda_immediate = .{ .value = value.type.expr_u8 },
                    } });
                } else return Error.UnexpectedToken;
            },
            else => Error.UnexpectedToken,
        };
    }

    fn parseIdentifierNode(self: *@This()) Error!Node {
        try self.crumble("{s}", .{@src().fn_name});
        self.incBreadcrumbDepth();
        defer self.decBreadcrumbDepth();

        const identifier = try self.expectIdentifier();

        if (std.mem.eql(u8, identifier.lexeme, "bin")) {
            return self.parseBinaryNode();
        }

        return Error.UnexpectedToken;
    }

    fn parseNumberNode(self: *@This()) Error!Node {
        try self.crumble("{s}", .{@src().fn_name});
        self.incBreadcrumbDepth();
        defer self.decBreadcrumbDepth();

        const number = try self.expectNumber();

        return switch (number.size()) {
            1 => self.mkNode(.{ .expr_u8 = .{ .literal = @intCast(number.value) } }),
            2 => self.mkNode(.{ .expr_u16 = .{ .literal = @intCast(number.value) } }),
            else => {
                std.log.err("Invalid number size; Expected 1 or 2 bytes, found: {} in number {}", .{ number.size(), number.value });
                return Error.InvalidNumber;
            },
        };
    }

    fn parseStringNode(self: *@This()) Error!Node {
        try self.crumble("{s}", .{@src().fn_name});
        self.incBreadcrumbDepth();
        defer self.decBreadcrumbDepth();

        const string = try self.expectString();
        return self.mkNode(.{ .string = string });
    }

    fn parseBinaryNode(self: *@This()) Error!Node {
        try self.crumble("{s}", .{@src().fn_name});

        const tok = try self.nextToken();

        const target: Node.Binary.Target = if (tok.tag == .string) .{ .file = tok.lexeme } else if (tok.tag == .identifier and std.mem.eql(u8, "virtual", tok.lexeme)) .virtual else return Error.UnexpectedToken;

        self.incBreadcrumbDepth();
        const base_addr = try self.parseNode() orelse return Error.ExpectedMore;
        const inner = try self.parseNode() orelse return Error.ExpectedMore;
        self.decBreadcrumbDepth();

        return self.mkNode(.{ .binary = .{ .target = target, .base_address = base_addr.id, .node = inner.id } });
    }

    fn parseNodes(self: *@This()) Error![]Node {
        try self.crumble("{s}", .{@src().fn_name});
        self.incBreadcrumbDepth();
        defer self.decBreadcrumbDepth();

        var nodes: std.ArrayList(Node) = .empty;

        while (try self.parseNode()) |node| {
            try nodes.append(self.allocator, node);
        }

        return nodes.toOwnedSlice(self.allocator);
    }

    fn expectTag(self: *@This(), tag: Token.Tag) Error!Token {
        try self.crumble("{s}", .{@src().fn_name});

        const tok = try self.nextToken();
        if (tok.tag != tag) return Error.UnexpectedToken;
        return tok;
    }

    fn expectIdentifier(self: *@This()) Error!Token {
        try self.crumble("{s}", .{@src().fn_name});

        return self.expectTag(.identifier);
    }

    fn expectNumber(self: *@This()) Error!Number {
        try self.crumble("{s}", .{@src().fn_name});

        const tok = try self.expectTag(.number);

        if (tok.lexeme.len == 1) return .{
            .tok = tok,
            .base = 10,
            .value = tok.lexeme[0] - '0',
        };

        const mode = Tokenizer.NumberMode.fromSelector(tok.lexeme[1]).?;
        const base = mode.toBase();
        const value = try std.fmt.parseInt(usize, tok.lexeme, base);

        return .{ .tok = tok, .base = base, .value = value };
    }

    fn expectString(self: *@This()) Error![]const u8 {
        try self.crumble("{s}", .{@src().fn_name});

        const string = try self.expectTag(.string);
        return string.lexeme[1 .. string.lexeme.len - 1];
    }

    const Number = struct {
        tok: Token,
        base: u5,
        value: usize,

        pub fn size(self: @This()) usize {
            if (self.value == 0) return 1;
            const f: f32 = @floatFromInt(self.value);
            return @ceil(@log2(f + 1) / 8.0);
        }
    };

    fn mkNode(self: *@This(), node_type: Node.Type) Error!Node {
        try self.crumble("{s}", .{@src().fn_name});

        const node = Node{
            .id = self.node_id,
            .type = node_type,
        };

        self.node_id += 1;

        try self.node_map.put(self.allocator, node.id, node);

        return node;
    }

    pub fn mkSnapshot(self: *Parser) !Snapshot {
        try self.crumble("snapshot taken", .{});
        return .init(self.allocator, self);
    }

    pub const Snapshot = struct {
        node_id: Node.Id,
        reader_offset: u64,
        tokenizer_marker: Location,
        tokenizer_cursor: Location,
        peek_buffer: []const Token,
        diagnostics_len: usize,

        pub fn init(allocator: Allocator, target: *Parser) !@This() {
            const file_reader = try target.reader_container.request(target.uri);

            return .{
                .node_id = target.node_id,
                .reader_offset = file_reader.logicalPos(),
                .tokenizer_marker = target.tokenizer.reader.marker,
                .tokenizer_cursor = target.tokenizer.reader.cursor,
                .peek_buffer = try allocator.dupe(Token, target.peek_buffer.items),
                .diagnostics_len = target.diagnostics.items.len,
            };
        }

        pub fn restore(self: @This(), target: *Parser) !void {
            try target.crumble("restore snapshot", .{});

            if (target.node_id > self.node_id) {
                for (self.node_id + 1..target.node_id) |node_id| {
                    _ = target.node_map.remove(node_id);
                }
                target.node_id = self.node_id;
            }
            target.diagnostics.shrinkRetainingCapacity(self.diagnostics_len);
            target.peek_buffer.clearRetainingCapacity();
            for (self.peek_buffer) |peek| target.peek_buffer.appendAssumeCapacity(peek);
            const file_reader = try target.reader_container.request(target.uri);
            try file_reader.seekTo(self.reader_offset);
            target.tokenizer.reader.marker = self.tokenizer_marker;
            target.tokenizer.reader.cursor = self.tokenizer_cursor;
        }
    };

    pub const Error = error{
        UnexpectedToken,
        ExpectedMore,
        InvalidNumber,
    } || Allocator.Error || Tokenizer.Error || std.fmt.ParseIntError || ReaderContainer.Error || std.Io.File.SeekError;
};

pub const Breadcrumb = struct {
    label: []const u8,
    depth: usize,

    const indentation_width = 2;

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.splatByteAll(' ', self.depth * indentation_width);
        try writer.print("{s}", .{self.label});
    }
};
