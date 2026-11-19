const std = @import("std");
const Allocator = std.mem.Allocator;
const ast_mod = @import("ast.zig");
const Node = ast_mod.Node;

pub const PrintAST = struct {
    allocator: Allocator,
    writer: *std.Io.Writer,
    node: Node,
    depth: usize = 0,
    node_map: *std.AutoHashMapUnmanaged(Node.Id, Node),
    nodes_printed: *std.ArrayList(Node.Id),

    const indentation_width = 2;

    pub fn init(
        allocator: Allocator,
        writer: *std.Io.Writer,
        node: Node,
        node_map: *std.AutoHashMapUnmanaged(Node.Id, Node),
        nodes_printed: *std.ArrayList(Node.Id),
    ) @This() {
        return .{
            .allocator = allocator,
            .writer = writer,
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
};

pub fn printAST(ctx: PrintAST) (std.Io.Writer.Error || Allocator.Error)!void {
    try printNode(ctx);
}

fn printNode(ctx: PrintAST) (std.Io.Writer.Error || Allocator.Error)!void {
    try ctx.writer.print("id({}):", .{ctx.node.id});

    if (std.mem.containsAtLeast(Node.Id, ctx.nodes_printed.items, 1, &.{ctx.node.id})) {
        try ctx.writer.print("cyclic nodes detected: {}", .{ctx.node.id});
        return;
    }

    try ctx.nodes_printed.append(ctx.allocator, ctx.node.id);
    defer _ = ctx.nodes_printed.pop();

    try switch (ctx.node.type) {
        .block => |block| printNodeBlock(ctx, block),
        .binary => |binary| printNodeBinary(ctx, binary),
        .expr_u8 => |expr_u8| printNodeExprU8(ctx, expr_u8),
        .expr_u16 => |expr_u16| printNodeExprU16(ctx, expr_u16),
        .identifier => |ident| printNodeIdentifier(ctx, ident),
        .string => |string| printNodeString(ctx, string),
        .instruction => |instr| printNodeInstruction(ctx, instr),
        else => unreachable,
    };
}

fn printNodeBlock(ctx: PrintAST, block: Node.Block) (std.Io.Writer.Error || Allocator.Error)!void {
    try ctx.writer.writeByte('\n');
    try ctx.printIndentation();
    try ctx.writer.writeAll("{\n");
    for (block.children) |child_id| {
        var child_ctx = ctx.forNodeId(child_id);
        child_ctx.depth += 1;
        try child_ctx.printIndentation();
        try printNode(child_ctx);
        try ctx.writer.writeByte('\n');
    }
    try ctx.printIndentation();
    try ctx.writer.writeAll("}\n");
}

fn printNodeBinary(ctx: PrintAST, binary: Node.Binary) (std.Io.Writer.Error || Allocator.Error)!void {
    try ctx.writer.writeAll("bin ");
    try switch (binary.target) {
        .virtual => ctx.writer.writeAll("virtual "),
        .file => |file| ctx.writer.print("\"{s}\" ", .{file}),
    };
    try printNode(ctx.forNodeId(binary.base_address));
    try ctx.writer.writeByte(' ');
    try printNode(ctx.forNodeId(binary.node));
}

fn printNodeExprU8(ctx: PrintAST, expr_u8: Node.ExprU8) (std.Io.Writer.Error || Allocator.Error)!void {
    try switch (expr_u8) {
        .literal => |literal| ctx.writer.print("0x{x:02}", .{literal}),
    };
}

fn printNodeExprU16(ctx: PrintAST, expr_u16: Node.ExprU16) (std.Io.Writer.Error || Allocator.Error)!void {
    try switch (expr_u16) {
        .literal => |literal| ctx.writer.print("0x{x:04}", .{literal}),
    };
}

fn printNodeIdentifier(ctx: PrintAST, identifier: []const u8) (std.Io.Writer.Error || Allocator.Error)!void {
    try ctx.writer.writeAll(identifier);
}

fn printNodeString(ctx: PrintAST, string: []const u8) (std.Io.Writer.Error || Allocator.Error)!void {
    try ctx.writer.print("\"{s}\"", .{string});
}

fn printNodeInstruction(ctx: PrintAST, instr: Node.Instruction) (std.Io.Writer.Error || Allocator.Error)!void {
    switch (instr) {
        .lda_immediate => |s| {
            try ctx.writer.writeAll("a = ");
            try printNodeExprU8(ctx, s.value);
        },
    }
}
