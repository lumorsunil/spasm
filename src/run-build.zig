const std = @import("std");
const Allocator = std.mem.Allocator;
const Options = @import("options.zig").Options;

pub fn runBuild(
    io: std.Io,
    allocator: Allocator,
    build_options: Options.Command.Build,
) !void {
    _ = io;
    _ = allocator;
    _ = build_options;
    return error.NotYetImplemented;
}
