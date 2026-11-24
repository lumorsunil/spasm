const std = @import("std");
const Allocator = std.mem.Allocator;
const Options = @import("options.zig").Options;
const ReaderContainer = @import("reader-container.zig").ReaderContainer;
const Parser = @import("parser.zig").Parser;
const CompilationContext = @import("compiler.zig").CompilationContext;
const precompile = @import("compiler.zig").precompile;
const executeCompilerActions = @import("compiler.zig").executeCompilerActions;
const Stdio = @import("stdio.zig").Stdio;
const Node = @import("ast.zig").Node;
const printAST = @import("print-ast.zig").printAST;
const Diagnostic = @import("diagnostic.zig").Diagnostic;

pub fn runBuild(
    io: std.Io,
    allocator: Allocator,
    stdio: *Stdio,
    build_options: Options.Command.Build,
) !void {
    var reader_container = ReaderContainer.init(io, allocator);
    var parser = Parser.init(allocator, &reader_container);

    const root = parser.parse(build_options.entry_file_path) catch |err| {
        return handleStepError(stdio, "Parse", err, parser.diagnostics.items);
    };

    for (parser.breadcrumbs.items) |crumb| {
        try stdio.stderr().print("{f}\n", .{crumb});
    }

    var nodes_printed = std.ArrayList(Node.Id).empty;
    try printAST(.init(
        allocator,
        stdio.stderr_terminal,
        root,
        &parser.node_map,
        &nodes_printed,
    ));
    nodes_printed.clearRetainingCapacity();

    var ctx: CompilationContext = .{
        .io = io,
        .allocator = allocator,
        .stdio = stdio,
        .node_map = &parser.node_map,
        .uri = parser.uri,
    };

    const precompile_result = precompile(&ctx, root.id) catch |err| {
        return handleStepError(stdio, "Compiler", err, ctx.diagnostics.items);
    };

    for (precompile_result.actions.items) |action| {
        try stdio.stderr().print("compiler action: {f}\n", .{action});
    }

    var scope_it = ctx.scope_map.iterator();
    while (scope_it.next()) |entry| {
        try stdio.stderr().print("{s}: {{\n", .{entry.key_ptr.*});

        var binding_it = entry.value_ptr.map.iterator();
        while (binding_it.next()) |b_entry| {
            try stdio.stderr().print("    {s} = ", .{b_entry.key_ptr.*});
            if (ctx.getNodeById(b_entry.value_ptr.*)) |node| {
                try printAST(.init(
                    allocator,
                    stdio.stderr_terminal,
                    node,
                    &parser.node_map,
                    &nodes_printed,
                ));
            } else {
                try stdio.stderr().writeAll("null\n");
            }
        }

        try stdio.stderr().writeAll("}\n");
    }

    executeCompilerActions(&ctx, precompile_result) catch |err| {
        return handleStepError(stdio, "Compiler", err, ctx.diagnostics.items);
    };
}

fn handleStepError(
    stdio: *Stdio,
    comptime label: []const u8,
    err: anyerror,
    diagnostics: []const Diagnostic,
) !void {
    try stdio.stderr_terminal.printColored(label ++ " error: {}\n", .{err}, .bright_red);
    for (diagnostics) |diagnostic| {
        try stdio.stderr().print("{f}\n", .{stdio.stderr_terminal.fmt(diagnostic)});
    }
    if (diagnostics.len > 0) {
        return;
    } else {
        return err;
    }
}
