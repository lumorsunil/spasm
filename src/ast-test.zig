const std = @import("std");
const Allocator = std.mem.Allocator;
const Node = @import("ast.zig").Node;
const CompilationContext = @import("compiler.zig").CompilationContext;
const precompile = @import("compiler.zig").precompile;
const executeCompilerActions = @import("compiler.zig").executeCompilerActions;
const Stdio = @import("stdio.zig").Stdio;

pub fn astTest(io: std.Io, allocator: Allocator, env: *std.process.Environ.Map) !void {
    var stdio: Stdio = .uninitialized;
    try stdio.init(io, env);

    var node_map: std.AutoHashMapUnmanaged(Node.Id, Node) = .empty;
    var ctx: CompilationContext = .{
        .io = io,
        .allocator = allocator,
        .stdio = &stdio,
        .node_map = &node_map,
        .uri = "source",
    };

    try ctx.node_map.put(allocator, 0, .{
        .uri = "source",
        .id = 0,
        .type = .{ .block = .{ .children = &.{2} } },
        .start = undefined,
        .end = undefined,
    });
    try ctx.node_map.put(allocator, 1, .{
        .uri = "source",
        .id = 1,
        .type = .{ .instruction = .{ .lda_immediate = .{ .value = .{ .literal = 5 } } } },
        .start = undefined,
        .end = undefined,
    });
    try ctx.node_map.put(allocator, 2, .{
        .uri = "source",
        .id = 2,
        .type = .{ .binary_decl = .{ .target = .{ .file = 3 }, .base_address = 0, .node = 1 } },
        .start = undefined,
        .end = undefined,
    });
    try ctx.node_map.put(allocator, 3, .{
        .uri = "source",
        .id = 3,
        .type = .{ .string = "test.bin" },
        .start = undefined,
        .end = undefined,
    });

    const root = 0;

    const precompile_result = try precompile(&ctx, root);
    try executeCompilerActions(&ctx, precompile_result);
}
