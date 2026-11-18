const std = @import("std");
const Allocator = std.mem.Allocator;
const ast_mod = @import("ast.zig");
const Node = ast_mod.Node;
const CompilationContext = ast_mod.CompilationContext;

pub fn astTest(io: std.Io, allocator: Allocator) !void {
    var node_map: std.AutoHashMapUnmanaged(Node.Id, Node) = .empty;
    var ctx: CompilationContext = .{
        .io = io,
        .allocator = allocator,
        .node_map = &node_map,
    };

    try ctx.node_map.put(allocator, 0, .{ .id = 0, .type = .{ .block = .{ .children = &.{2} } } });
    try ctx.node_map.put(allocator, 1, .{ .id = 1, .type = .{ .instruction = .{ .lda_immediate = .{ .value = .{ .literal = 5 } } } } });
    try ctx.node_map.put(allocator, 2, .{ .id = 2, .type = .{ .binary = .{ .target = .{ .file = "test.bin" }, .base_address = 0, .node = 1 } } });

    const root = 0;

    const precompile_result = try ast_mod.precompile(&ctx, root);
    try ast_mod.executeCompilerActions(&ctx, precompile_result);
}
