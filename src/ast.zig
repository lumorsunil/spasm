const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Node = struct {
    id: Id,
    type: Type,

    pub const Id = usize;

    pub const Type = union(enum) {
        instruction: Instruction,
        emit: Emit,
        block: Block,
        binary: Binary,
        identifier: []const u8,
        label: []const u8,
    };

    pub const Instruction = struct {};

    pub const Emit = struct {
        node: Id,
    };

    pub const Block = struct {
        children: []const Id,
    };

    pub const Binary = struct {
        target: Target,
        base_address: usize,
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
    allocator: Allocator,
};

pub const CompileAction = union(enum) {
    create_binary_file: Node.Id,
};

pub const CompilationResult = struct {
    actions: std.ArrayList(CompileAction),
    diagnostics: std.ArrayList(Diagnostic),

    pub fn init(
        allocator: Allocator,
        actions: []const CompileAction,
        diagnostics: []const Diagnostic,
    ) !@This() {
        return .{
            .actions = .fromOwnedSlice(try allocator.dupe(actions)),
            .diagnostics = .fromOwnedSlice(try allocator.dupe(diagnostics)),
        };
    }

    pub fn merge(
        self: *CompilationResult,
        allocator: Allocator,
        other: CompilationResult,
    ) !void {
        try self.actions.appendSlice(allocator, other.actions);
        try self.diagnostics.appendSlice(allocator, other.diagnostics);
    }
};

pub fn compile(
    ctx: *CompilationContext,
    node_id: Node.Id,
) CompileError!CompilationResult {
    const node = ctx.getNodeById(node_id) orelse return CompileError.NodeNotFound;

    return switch (node.type) {
        .binary => |binary| compileBinary(ctx, node, binary),
        .block => |block| compileBlock(ctx, node, block),
    };
}

pub fn compileBinary(
    ctx: *CompilationContext,
    node: Node,
    binary: Node.Binary,
) CompileError!CompilationResult {
    const result = try compile(ctx, binary.node);

    try result.actions.append(ctx.allocator, .{ .create_binary_file = node.id });
}

pub fn compileBlock(
    ctx: *CompilationContext,
    _: Node,
    block: Node.Block,
) CompileError!CompilationResult {
    var result = CompilationResult.init();

    for (block.children) |child| {
        try result.merge(try compile(ctx, child));
    }

    return result;
}

pub const CompileError = error{
    NodeNotFound,
};

pub const Diagnostic = struct {
    severity: Severity,
    message: []const u8,
    range: Range,

    pub const Severity = enum { debug, info, warn, err };
};

pub const Location = struct {
    uri: []const u8,
    index: usize,
    line: usize,
    column: usize,
};

pub const Range = struct {
    start: Location,
    end: Location,
};
