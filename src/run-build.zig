const std = @import("std");
const Allocator = std.mem.Allocator;
const Options = @import("options.zig").Options;
const ReaderContainer = @import("parser.zig").ReaderContainer;
const Parser = @import("parser.zig").Parser;
const ast_mod = @import("ast.zig");
const CompilationContext = ast_mod.CompilationContext;
const Stdio = @import("stdio.zig").Stdio;
const Node = ast_mod.Node;
const printAST = @import("print-ast.zig").printAST;

pub fn runBuild(
    io: std.Io,
    allocator: Allocator,
    stdio: *Stdio,
    build_options: Options.Command.Build,
) !void {
    var reader_container = ReaderContainer.init(io, allocator);
    var parser = Parser.init(allocator, &reader_container);
    const root = parser.parse(build_options.entry_file_path) catch |err| {
        try stdio.stderr().print("Parse error: {}\n", .{err});
        for (parser.diagnostics.items) |diagnostic| {
            try stdio.stderr().print("{f}\n", .{diagnostic});
        }
        return err;
    };

    for (parser.breadcrumbs.items) |crumb| {
        try stdio.stderr().print("{f}\n", .{crumb});
    }

    var nodes_printed = std.ArrayList(Node.Id).empty;
    try printAST(.init(allocator, stdio.stderr(), root, &parser.node_map, &nodes_printed));

    var ctx: CompilationContext = .{
        .io = io,
        .allocator = allocator,
        .node_map = &parser.node_map,
    };

    const precompile_result = try ast_mod.precompile(&ctx, root.id);
    for (precompile_result.actions.items) |action| {
        try stdio.stderr().print("{f}", .{action});
    }
    try ast_mod.executeCompilerActions(&ctx, precompile_result);
}
