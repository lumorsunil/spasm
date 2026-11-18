const std = @import("std");
const Allocator = std.mem.Allocator;
const Diagnostic = @import("diagnostic.zig").Diagnostic;

pub const Node = struct {
    id: Id,
    type: Type,

    pub const Id = usize;

    pub const Type = union(enum) {
        expr_u8: ExprU8,
        expr_u16: ExprU16,
        instruction: Instruction,
        emit: Emit,
        block: Block,
        binary: Binary,
        string: []const u8,
        identifier: []const u8,
        label: []const u8,
        declaration: Declaration,
    };

    pub const Instruction = union(enum) {
        lda_immediate: struct {
            value: ExprU8,
            pub const mnemonic = "lda";
            pub const opcode = 0xA9;
        },
    };

    pub const ExprU8 = union(enum) {
        literal: u8,

        pub fn evaluate(self: @This(), ctx: *CompilationContext) !u8 {
            _ = ctx;
            return switch (self) {
                .literal => |s| s,
            };
        }
    };

    pub const ExprU16 = union(enum) {
        literal: u16,

        pub fn evaluate(self: @This(), ctx: *CompilationContext) !u16 {
            _ = ctx;
            return switch (self) {
                .literal => |s| s,
            };
        }
    };

    pub const Emit = struct {
        node: Id,
    };

    pub const Block = struct {
        children: []const Id,
    };

    pub const Binary = struct {
        target: Target,
        base_address: Id,
        node: Id,

        pub const Target = union(enum) {
            virtual,
            file: []const u8,
        };
    };

    pub const Declaration = struct {
        identifier: []const u8,
        type_expr: Id,
        initializer: Id,
    };
};

pub const CompilationContext = struct {
    io: std.Io,
    allocator: Allocator,
    node_map: *std.AutoHashMapUnmanaged(Node.Id, Node),
    binary_file_map: std.StringHashMapUnmanaged(BinaryOutput) = .empty,
    label_map: std.AutoHashMapUnmanaged(Node.Id, usize) = .empty,
    output_file: ?[]const u8 = null,

    pub fn getNodeById(self: *@This(), id: Node.Id) ?Node {
        return self.node_map.get(id);
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
    diagnostics: std.ArrayList(Diagnostic) = .empty,

    pub const empty = @This(){};

    pub fn init(
        allocator: Allocator,
        actions: []const CompileAction,
        diagnostics: []const Diagnostic,
    ) !@This() {
        return .{
            .actions = .fromOwnedSlice(try allocator.dupe(CompileAction, actions)),
            .diagnostics = .fromOwnedSlice(try allocator.dupe(Diagnostic, diagnostics)),
        };
    }

    pub fn merge(
        self: *CompilationResult,
        allocator: Allocator,
        other: CompilationResult,
    ) !void {
        try self.actions.appendSlice(allocator, other.actions.items);
        try self.diagnostics.appendSlice(allocator, other.diagnostics.items);
    }
};

pub fn precompile(
    ctx: *CompilationContext,
    node_id: Node.Id,
) CompileError!CompilationResult {
    const node = ctx.getNodeById(node_id) orelse return CompileError.NodeNotFound;

    return switch (node.type) {
        .binary => |binary| precompileBinary(ctx, node, binary),
        .block => |block| precompileBlock(ctx, node, block),
        .instruction, .identifier, .emit, .label, .expr_u8, .expr_u16, .string, .declaration => .empty,
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
    binary: Node.Binary,
) CompileError!CompilationResult {
    return switch (binary.target) {
        .virtual => try .init(
            ctx.allocator,
            &.{.{ .virtual = .{ .node = node.id } }},
            &.{},
        ),
        .file => |file_path| try .init(
            ctx.allocator,
            &.{.{ .create_binary_file = .{ .node = node.id, .file_path = file_path } }},
            &.{},
        ),
    };
}

pub fn compile(
    ctx: *CompilationContext,
    node_id: Node.Id,
) CompileError!CompilationResult {
    const node = ctx.getNodeById(node_id) orelse return CompileError.NodeNotFound;

    return switch (node.type) {
        .binary => |binary| compileBinary(ctx, node, binary),
        .block => |block| compileBlock(ctx, node, block),
        .instruction => |instr| compileInstruction(ctx, node, instr),
        .expr_u8 => |expr_u8| compileExtrU8(ctx, node, expr_u8),
        .expr_u16 => |expr_u16| compileExtrU16(ctx, node, expr_u16),
        .emit, .identifier, .label, .declaration => CompileError.NotYetImplemented,
        .string => CompileError.ComptimeEncountered,
    };
}

pub fn compileBinary(
    ctx: *CompilationContext,
    _: Node,
    binary: Node.Binary,
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

pub const CompileError = error{
    NodeNotFound,
    NotYetImplemented,
    EmitWhileNoOutputFile,
    BinaryOutputFileNotFound,
    ComptimeEncountered,
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
    // TODO: check diagnostics of result
    _ = try compile(ctx, action.node);
}

pub fn executeCreateBinaryFile(
    ctx: *CompilationContext,
    action: CompileAction.CreateBinaryFile,
) ExecuteError!void {
    if (ctx.binary_file_map.contains(action.file_path)) {
        return ExecuteError.DuplicateOutputFile;
    }

    try ctx.binary_file_map.put(ctx.allocator, action.file_path, .empty);
    ctx.output_file = action.file_path;

    // TODO: check diagnostics of result
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
