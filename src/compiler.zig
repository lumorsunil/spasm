const std = @import("std");
const Allocator = std.mem.Allocator;
const Stdio = @import("stdio.zig").Stdio;
const ast_mod = @import("ast.zig");
const Node = ast_mod.Node;
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const Range = @import("tokenizer.zig").Range;

pub fn UriMap(comptime T: type) type {
    return std.StringHashMapUnmanaged(T);
}

pub fn NodeMap(comptime T: type) type {
    return std.AutoHashMapUnmanaged(Node.Id, T);
}

pub fn Scope(comptime T: type) type {
    return struct {
        map: std.StringHashMapUnmanaged(T) = .empty,

        pub const empty = @This(){};
    };
}

pub const CompilationContext = struct {
    io: std.Io,
    allocator: Allocator,
    stdio: *Stdio,
    node_map: *NodeMap(Node),
    binary_file_map: UriMap(BinaryOutput) = .empty,
    label_map: NodeMap(usize) = .empty,
    scope_map: UriMap(Scope(Node.Id)) = .empty,
    output_file: ?[]const u8 = null,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    uri: []const u8,

    fn reportDiagnostic(
        self: *@This(),
        severity: Diagnostic.Severity,
        node: Node,
        comptime fmt: []const u8,
        args: anytype,
    ) Allocator.Error!void {
        try self.diagnostics.append(self.allocator, .{
            .uri = node.uri,
            .message = try std.fmt.allocPrint(self.allocator, fmt, args),
            .severity = severity,
            .range = node.range(),
        });
    }

    pub fn getNodeById(self: *@This(), id: Node.Id) ?Node {
        return self.node_map.get(id);
    }

    pub fn scope(self: *@This()) ?*Scope(Node.Id) {
        return self.scope_map.getPtr(self.uri);
    }

    pub fn expectIdentifier(self: *@This(), id: Node.Id) CompileError!?Node.Identifier {
        const node = self.getNodeById(id) orelse return CompileError.NodeNotFound;
        return switch (node.type) {
            .identifier => |ident| ident,
            else => null,
        };
    }

    pub fn appendBinaryOutput(self: *@This(), output_node: BinaryOutput.OutputNode) !void {
        const output_file = self.output_file orelse return CompileError.EmitWhileNoOutputFile;
        const binary_file_output = self.binary_file_map.getPtr(output_file) orelse return CompileError.BinaryOutputFileNotFound;
        try binary_file_output.nodes.append(self.allocator, output_node);
    }

    pub const BinaryOutput = struct {
        nodes: std.ArrayList(OutputNode) = .empty,

        pub const empty = @This(){};

        pub const OutputNode = union(enum) {
            instruction: Node.Instruction,
            bytes: []const u8,
        };
    };
};

pub const CompileAction = union(enum) {
    virtual: Virtual,
    create_binary_file: CreateBinaryFile,

    pub const Virtual = struct {
        node: Node.Id,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("bin virtual id:{}", .{self.node});
        }
    };

    pub const CreateBinaryFile = struct {
        node: Node.Id,
        file_path: []const u8,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("bin {s} id:{}", .{ self.file_path, self.node });
        }
    };

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            inline else => |s| try writer.print("{f}", .{s}),
        }
    }
};

pub const CompilationResult = struct {
    actions: std.ArrayList(CompileAction) = .empty,

    pub const empty = @This(){};

    pub fn init(
        allocator: Allocator,
        actions: []const CompileAction,
    ) !@This() {
        return .{
            .actions = .fromOwnedSlice(try allocator.dupe(CompileAction, actions)),
        };
    }

    pub fn merge(
        self: *CompilationResult,
        allocator: Allocator,
        other: CompilationResult,
    ) !void {
        try self.actions.appendSlice(allocator, other.actions.items);
    }
};

pub fn precompile(
    ctx: *CompilationContext,
    node_id: Node.Id,
) CompileError!CompilationResult {
    const node = ctx.getNodeById(node_id) orelse return CompileError.NodeNotFound;

    return switch (node.type) {
        .binary_decl => |binary| precompileBinary(ctx, node, binary),
        .block => |block| precompileBlock(ctx, node, block),
        .binary_operation => |binary_op| precompileBinaryOp(ctx, node, binary_op),
        .instruction,
        .identifier,
        .emit,
        .label,
        .expr_u8,
        .expr_u16,
        .string,
        .declaration,
        => .empty,
    };
}

pub fn precompileBlock(
    ctx: *CompilationContext,
    _: Node,
    block: Node.Block,
) CompileError!CompilationResult {
    var result: CompilationResult = .empty;

    for (block.children) |child| {
        try result.merge(ctx.allocator, try precompile(ctx, child));
    }

    return result;
}

pub fn precompileBinary(
    ctx: *CompilationContext,
    node: Node,
    binary: Node.BinaryDecl,
) CompileError!CompilationResult {
    return switch (binary.target) {
        .virtual => try .init(
            ctx.allocator,
            &.{.{ .virtual = .{ .node = node.id } }},
        ),
        .file => |file_path| try .init(
            ctx.allocator,
            &.{.{ .create_binary_file = .{ .node = node.id, .file_path = ctx.getNodeById(file_path).?.type.string } }},
        ),
    };
}

pub fn precompileBinaryOp(
    ctx: *CompilationContext,
    node: Node,
    binary_op: Node.BinaryOperation,
) CompileError!CompilationResult {
    const identifier = try ctx.expectIdentifier(binary_op.lhs) orelse return .empty;
    const root_scope = (try ctx.scope_map.getOrPutValue(ctx.allocator, ctx.uri, .empty)).value_ptr;

    if (root_scope.map.contains(identifier)) {
        try ctx.reportDiagnostic(.err, node, "duplicate binding of identifier \"{s}\"", .{identifier});
        return CompileError.DuplicateBinding;
    }

    try root_scope.map.put(ctx.allocator, identifier, binary_op.rhs);

    return .empty;
}

pub fn compile(
    ctx: *CompilationContext,
    node_id: Node.Id,
) CompileError!CompilationResult {
    const node = ctx.getNodeById(node_id) orelse return CompileError.NodeNotFound;

    return switch (node.type) {
        .binary_decl => |binary| compileBinary(ctx, node, binary),
        .block => |block| compileBlock(ctx, node, block),
        .instruction => |instr| compileInstruction(ctx, node, instr),
        .expr_u8 => |expr_u8| compileExtrU8(ctx, node, expr_u8),
        .expr_u16 => |expr_u16| compileExtrU16(ctx, node, expr_u16),
        .identifier => |ident| compileIdentifier(ctx, node, ident),
        .emit, .label, .declaration, .binary_operation => {
            try ctx.reportDiagnostic(.err, node, "node type {t} not yet implemented", .{node.type});
            return CompileError.NotYetImplemented;
        },
        .string => CompileError.ComptimeEncountered,
    };
}

pub fn compileBinary(
    ctx: *CompilationContext,
    _: Node,
    binary: Node.BinaryDecl,
) CompileError!CompilationResult {
    // TODO: take base address into account?
    return try compile(ctx, binary.node);
}

pub fn compileBlock(
    ctx: *CompilationContext,
    _: Node,
    block: Node.Block,
) CompileError!CompilationResult {
    var result: CompilationResult = .empty;

    for (block.children) |child| {
        try result.merge(ctx.allocator, try compile(ctx, child));
    }

    return result;
}

pub fn compileInstruction(
    ctx: *CompilationContext,
    _: Node,
    instr: Node.Instruction,
) CompileError!CompilationResult {
    // TODO: convert this error to diagnostic
    try ctx.appendBinaryOutput(.{ .instruction = instr });
    return .empty;
}

pub fn compileExtrU8(
    ctx: *CompilationContext,
    _: Node,
    expr_u8: Node.ExprU8,
) CompileError!CompilationResult {
    const bytes = try ctx.allocator.alignedAlloc(u8, null, 1);
    switch (expr_u8) {
        .literal => |literal| bytes[0] = literal,
    }
    try ctx.appendBinaryOutput(.{ .bytes = bytes });
    return .empty;
}

pub fn compileExtrU16(
    ctx: *CompilationContext,
    _: Node,
    expr_u16: Node.ExprU16,
) CompileError!CompilationResult {
    const bytes = try ctx.allocator.alignedAlloc(u8, null, 2);
    switch (expr_u16) {
        .literal => |literal| {
            bytes[0] = @intCast(literal & 0x00FF);
            bytes[1] = @intCast((literal & 0xFF00) >> 8);
        },
    }
    try ctx.appendBinaryOutput(.{ .bytes = bytes });
    return .empty;
}

pub fn compileIdentifier(
    ctx: *CompilationContext,
    node: Node,
    ident: Node.Identifier,
) CompileError!CompilationResult {
    const scope = ctx.scope() orelse return CompileError.ScopeNotFound;
    const binding = scope.map.get(ident) orelse {
        try ctx.reportDiagnostic(.err, node, "undefined identifier \"{s}\" in scope", .{ident});
        return CompileError.UndefinedIdentifier;
    };

    return compile(ctx, binding);
}

pub const CompileError = error{
    BinaryOutputFileNotFound,
    ComptimeEncountered,
    DuplicateBinding,
    EmitWhileNoOutputFile,
    NodeNotFound,
    NotYetImplemented,
    ScopeNotFound,
    UndefinedIdentifier,
} || std.mem.Allocator.Error;

pub fn writeBinaryOutput(
    ctx: *CompilationContext,
    binary_output: *CompilationContext.BinaryOutput,
    writer: *std.Io.Writer,
) !void {
    for (binary_output.nodes.items) |output_node| {
        switch (output_node) {
            .bytes => |bytes| try writer.writeAll(bytes),
            .instruction => |instr| {
                switch (instr) {
                    .lda_immediate => |lda_immediate| {
                        try writer.writeByte(@TypeOf(lda_immediate).opcode);
                        try writer.writeByte(try lda_immediate.value.evaluate(ctx));
                    },
                }
            },
        }

        try writer.flush();
    }
}

pub fn executeCompilerActions(
    ctx: *CompilationContext,
    result: CompilationResult,
) ExecuteError!void {
    for (result.actions.items) |action| {
        if (action != .virtual) continue;
        try executeVirtual(ctx, action.virtual);
    }

    for (result.actions.items) |action| {
        if (action != .create_binary_file) continue;
        try executeCreateBinaryFile(ctx, action.create_binary_file);
    }
}

pub fn executeVirtual(
    ctx: *CompilationContext,
    action: CompileAction.Virtual,
) ExecuteError!void {
    ctx.output_file = null;
    _ = try compile(ctx, action.node);
}

pub fn executeCreateBinaryFile(
    ctx: *CompilationContext,
    action: CompileAction.CreateBinaryFile,
) ExecuteError!void {
    try ctx.stdio.stderr().print("creating binary file: {s}\n", .{action.file_path});

    if (ctx.binary_file_map.contains(action.file_path)) {
        return ExecuteError.DuplicateOutputFile;
    }

    try ctx.binary_file_map.put(ctx.allocator, action.file_path, .empty);
    ctx.output_file = action.file_path;

    try ctx.scope_map.put(ctx.allocator, action.file_path, .empty);

    _ = try compile(ctx, action.node);

    const file = try std.Io.Dir.cwd().createFile(ctx.io, action.file_path, .{});
    defer file.close(ctx.io);

    var write_buffer: [8]u8 = undefined;
    var file_writer = file.writer(ctx.io, &write_buffer);
    const writer = &file_writer.interface;

    const binary_file_output = ctx.binary_file_map.getPtr(action.file_path).?;
    try writeBinaryOutput(ctx, binary_file_output, writer);
}

pub const ExecuteError = error{
    NodeNotFound,
    DuplicateOutputFile,
    DuplicateVirtualNode,
} || CompileError || std.Io.File.OpenError || std.Io.Writer.Error;
