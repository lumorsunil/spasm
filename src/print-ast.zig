const std = @import("std");
const Allocator = std.mem.Allocator;
const ast_mod = @import("ast.zig");
const Node = ast_mod.Node;
const fmt = @import("color-formatter.zig");

const Self = @This();

const colors = .{
    .keyword = fmt.Color.magenta,
    .identifier = fmt.Color.yellow,
    .number = fmt.Color.green,
    .string = fmt.Color.bright_green,
};

fn rainbow(depth: usize) fmt.Color {
    const rainbow_colors: []const fmt.Color = &.{
        .yellow,
        .blue,
        .red,
        .green,
        .magenta,
        .cyan,
    };
    return rainbow_colors[depth % rainbow_colors.len];
}

pub const PrintAST = struct {
    allocator: Allocator,
    terminal: fmt.Terminal,
    writer: *std.Io.Writer,
    node: Node,
    depth: usize = 0,
    node_map: *std.AutoHashMapUnmanaged(Node.Id, Node),
    nodes_printed: *std.ArrayList(Node.Id),

    const indentation_width = 2;

    pub fn init(
        allocator: Allocator,
        terminal: fmt.Terminal,
        node: Node,
        node_map: *std.AutoHashMapUnmanaged(Node.Id, Node),
        nodes_printed: *std.ArrayList(Node.Id),
    ) @This() {
        return .{
            .allocator = allocator,
            .terminal = terminal,
            .writer = terminal.terminal.writer,
            .node = node,
            .node_map = node_map,
            .nodes_printed = nodes_printed,
        };
    }

    pub fn forNodeId(self: @This(), node_id: Node.Id) @This() {
        var copy = self;
        copy.node = self.node_map.get(node_id).?;
        return copy;
    }

    pub fn printIndentation(self: @This()) !void {
        _ = try self.writer.splatByte(' ', self.depth * indentation_width);
    }

    pub fn printColored(
        self: @This(),
        comptime fmt_: []const u8,
        args: anytype,
        color: fmt.Color,
    ) fmt.Terminal.Error!void {
        try self.terminal.printColored(fmt_, args, color);
    }
};

pub fn printAST(ctx: PrintAST) Error!void {
    try printNode(ctx);
    try ctx.writer.writeByte('\n');
}

fn printNode(ctx: PrintAST) Error!void {
    try ctx.writer.print("id({}):", .{ctx.node.id});

    if (std.mem.containsAtLeast(Node.Id, ctx.nodes_printed.items, 1, &.{ctx.node.id})) {
        try ctx.printColored("cyclic nodes detected: {}", .{ctx.node.id}, .red);
        return;
    }

    try ctx.nodes_printed.append(ctx.allocator, ctx.node.id);
    defer _ = ctx.nodes_printed.pop();

    try switch (ctx.node.type) {
        .block => |block| printNodeBlock(ctx, block),
        .binary_decl => |binary| printNodeBinary(ctx, binary),
        .binary_operation => |binary_op| printNodeBinaryOp(ctx, binary_op),
        .expr_u8 => |expr_u8| printNodeExprU8(ctx, expr_u8),
        .expr_u16 => |expr_u16| printNodeExprU16(ctx, expr_u16),
        .identifier => |ident| printNodeIdentifier(ctx, ident),
        .string => |string| printNodeString(ctx, string),
        .instruction => |instr| printNodeInstruction(ctx, instr),
        else => {
            try ctx.writer.print("<unsupported node type \"{t}\">", .{ctx.node.type});
        },
    };
}

fn printNodeBlock(ctx: PrintAST, block: Node.Block) Error!void {
    try ctx.printColored("{{\n", .{}, rainbow(ctx.depth));
    for (block.children) |child_id| {
        var child_ctx = ctx.forNodeId(child_id);
        child_ctx.depth += 1;
        try child_ctx.printIndentation();
        try printNode(child_ctx);
        try ctx.writer.writeByte('\n');
    }
    try ctx.printIndentation();
    try ctx.printColored("}}", .{}, rainbow(ctx.depth));
}

fn printNodeBinary(ctx: PrintAST, binary: Node.BinaryDecl) Error!void {
    try ctx.printColored("bin ", .{}, colors.keyword);
    try switch (binary.target) {
        .virtual => ctx.writer.writeAll("virtual "),
        .file => |file| {
            try printNode(ctx.forNodeId(file));
            try ctx.writer.writeByte(' ');
        },
    };
    try printNode(ctx.forNodeId(binary.base_address));
    try ctx.writer.writeByte(' ');
    try printNode(ctx.forNodeId(binary.node));
}

fn printNodeBinaryOp(ctx: PrintAST, binary_op: Node.BinaryOperation) Error!void {
    try ctx.printColored("(", .{}, rainbow(ctx.depth));
    try printNode(ctx.forNodeId(binary_op.lhs));
    try ctx.writer.print(" {f} ", .{binary_op.op});
    try printNode(ctx.forNodeId(binary_op.rhs));
    try ctx.printColored(")", .{}, rainbow(ctx.depth));
}

fn printNodeExprU8(ctx: PrintAST, expr_u8: Node.ExprU8) Error!void {
    try switch (expr_u8) {
        .literal => |literal| ctx.printColored("0x{x:02}", .{literal}, colors.number),
    };
}

fn printNodeExprU16(ctx: PrintAST, expr_u16: Node.ExprU16) Error!void {
    try switch (expr_u16) {
        .literal => |literal| ctx.printColored("0x{x:04}", .{literal}, colors.number),
    };
}

fn printNodeIdentifier(ctx: PrintAST, identifier: []const u8) Error!void {
    try ctx.printColored("{s}", .{identifier}, colors.identifier);
}

fn printNodeString(ctx: PrintAST, string: []const u8) Error!void {
    try ctx.printColored("\"{s}\"", .{string}, colors.string);
}

fn printNodeInstruction(ctx: PrintAST, instr: Node.Instruction) Error!void {
    switch (instr) {
        .lda_immediate => |s| {
            try ctx.printColored("a", .{}, colors.keyword);
            try ctx.writer.writeAll(" = ");
            try printNodeExprU8(ctx, s.value);
        },
    }
}

pub const Error = error{} || std.Io.Writer.Error || Allocator.Error || std.Io.Terminal.SetColorError;
