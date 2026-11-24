const std = @import("std");
const fmt = @import("color-formatter.zig");

pub const Stdio = struct {
    stdin_buffer: [1024]u8 = undefined,
    stdin_file_reader: std.Io.File.Reader = undefined,
    stdout_file_writer: std.Io.File.Writer = undefined,
    stderr_file_writer: std.Io.File.Writer = undefined,
    stdout_terminal: fmt.Terminal = undefined,
    stderr_terminal: fmt.Terminal = undefined,

    pub const uninitialized = @This(){};

    pub fn init(self: *@This(), io: std.Io, env: *std.process.Environ.Map) !void {
        const stdin_file = std.Io.File.stdin();
        const stdout_file = std.Io.File.stdout();
        const stderr_file = std.Io.File.stderr();

        self.stdin_file_reader = stdin_file.reader(io, &self.stdin_buffer);
        self.stdout_file_writer = stdout_file.writer(io, &.{});
        self.stderr_file_writer = stderr_file.writer(io, &.{});

        const NO_COLOR = env.contains("NO_COLOR");
        const CLICOLOR_FORCE = env.contains("CLICOLOR_FORCE");

        self.stdout_terminal = .{ .terminal = .{ .writer = self.stdout(), .mode = try .detect(io, stdout_file, NO_COLOR, CLICOLOR_FORCE) } };
        self.stderr_terminal = .{ .terminal = .{ .writer = self.stderr(), .mode = try .detect(io, stderr_file, NO_COLOR, CLICOLOR_FORCE) } };
    }

    pub fn stdin(self: *@This()) *std.Io.Reader {
        return &self.stdin_file_reader.interface;
    }

    pub fn stdout(self: *@This()) *std.Io.Writer {
        return &self.stdout_file_writer.interface;
    }

    pub fn stderr(self: *@This()) *std.Io.Writer {
        return &self.stderr_file_writer.interface;
    }
};
