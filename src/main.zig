const std = @import("std");
const ast_mod = @import("ast.zig");
const CompilationContext = ast_mod.CompilationContext;
const Node = ast_mod.Node;

pub fn main(init: std.process.Init) !void {
    var ctx: CompilationContext = .{
        .io = init.io,
        .allocator = init.arena.allocator(),
    };

    try ctx.node_map.put(ctx.allocator, 0, .{ .id = 0, .type = .{ .block = .{ .children = &.{2} } } });
    try ctx.node_map.put(ctx.allocator, 1, .{ .id = 1, .type = .{ .instruction = .{ .lda_immediate = .{ .value = .{ .literal = 5 } } } } });
    try ctx.node_map.put(ctx.allocator, 2, .{ .id = 2, .type = .{ .binary = .{ .target = .{ .file = "test.bin" }, .base_address = 0, .node = 1 } } });

    const root = 0;

    const precompile_result = try ast_mod.precompile(&ctx, root);
    try ast_mod.executeCompilerActions(&ctx, precompile_result);
}

test "root" {
    std.testing.refAllDecls(@This());
}
