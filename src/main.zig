const std = @import("std");
const Allocator = std.mem.Allocator;
const ast_mod = @import("ast.zig");
const CompilationContext = ast_mod.CompilationContext;
const Node = ast_mod.Node;
const Options = @import("options.zig").Options;
const ValidatedOptions = @import("options.zig").ValidatedOptions;
const Stdio = @import("stdio.zig").Stdio;

fn processOptions(options_result: Options.Result, stdio: *Stdio) !?ValidatedOptions {
    return switch (options_result) {
        .err => |options_err| {
            const err = options_err.err orelse error.UnknownError;

            if (options_err.errors.items.len == 0) {
                try stdio.stderr().print("Error validating options: {}\n", .{err});
            } else if (options_err.errors.items.len == 1) {
                try stdio.stderr().print("Error validating options: {s}\n", .{options_err.errors.items[0]});
            } else {
                try stdio.stderr().writeAll("Error validating options:\n");
                for (options_err.errors.items) |msg| {
                    try stdio.stderr().print("{s}\n", .{msg});
                }
            }

            return null;
        },
        .success => |validated_options| validated_options,
    };
}

fn astTest(io: std.Io, allocator: Allocator) !void {
    var ctx: CompilationContext = .{
        .io = io,
        .allocator = allocator,
    };

    try ctx.node_map.put(allocator, 0, .{ .id = 0, .type = .{ .block = .{ .children = &.{2} } } });
    try ctx.node_map.put(allocator, 1, .{ .id = 1, .type = .{ .instruction = .{ .lda_immediate = .{ .value = .{ .literal = 5 } } } } });
    try ctx.node_map.put(allocator, 2, .{ .id = 2, .type = .{ .binary = .{ .target = .{ .file = "test.bin" }, .base_address = 0, .node = 1 } } });

    const root = 0;

    const precompile_result = try ast_mod.precompile(&ctx, root);
    try ast_mod.executeCompilerActions(&ctx, precompile_result);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    var stdio: Stdio = .uninitialized;
    stdio.init(init.io);

    const options = try processOptions(
        Options.fromArgs(init.arena.allocator(), init.minimal.args),
        &stdio,
    ) orelse std.process.exit(1);

    try switch (options.command) {
        .build => |build| runBuild(io, allocator, build),
        .ast_test => astTest(io, allocator),
    };
}

fn runBuild(
    io: std.Io,
    allocator: Allocator,
    build_options: Options.Command.Build,
) RunError!void {
    _ = io;
    _ = allocator;
    _ = build_options;
    return RunError.NotYetImplemented;
}

pub const RunError = error{NotYetImplemented};

test "root" {
    std.testing.refAllDecls(@This());
}
