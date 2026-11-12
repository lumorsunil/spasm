const std = @import("std");
const Stdio = @import("stdio.zig").Stdio;
const processOptions = @import("process-options.zig").processOptions;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    var stdio: Stdio = .uninitialized;
    stdio.init(init.io);

    const options = try processOptions(
        .fromArgs(init.arena.allocator(), init.minimal.args),
        &stdio,
    ) orelse std.process.exit(1);

    try switch (options.command) {
        .build => |build| @import("run-build.zig").runBuild(io, allocator, build),
        .ast_test => @import("ast-test.zig").astTest(io, allocator),
    };
}

test "root" {
    std.testing.refAllDecls(@This());
}
