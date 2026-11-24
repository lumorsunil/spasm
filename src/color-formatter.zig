const std = @import("std");
const std_Terminal = std.Io.Terminal;

pub const Color = std_Terminal.Color;

pub const Terminal = struct {
    terminal: std_Terminal,

    pub fn print(
        self: @This(),
        comptime fmt_: []const u8,
        args: anytype,
    ) !void {
        try self.terminal.writer.print(fmt_, args);
    }

    pub fn printColored(
        self: @This(),
        comptime fmt_: []const u8,
        args: anytype,
        color: Color,
    ) !void {
        try self.terminal.setColor(color);
        try self.terminal.writer.print(fmt_, args);
        try self.terminal.setColor(.reset);
    }

    pub fn fmt(
        self: @This(),
        data: anytype,
    ) ColorFormatter(@TypeOf(data)) {
        return .init(data, self.terminal);
    }

    pub fn fmtWith(
        self: @This(),
        comptime fmt_: []const u8,
        args: anytype,
        color: Color,
    ) ColorFormatter(PrintFormatter(fmt_, @TypeOf(args))) {
        return .init(.{ .args = args, .color = color }, self.terminal);
    }

    pub const Error = std_Terminal.SetColorError;
};

fn PrintFormatter(comptime fmt_: []const u8, comptime T: type) type {
    return struct {
        args: T,
        color: Color,

        pub fn formatTerminal(
            self: @This(),
            terminal: Terminal,
        ) Terminal.Error!void {
            try terminal.printColored(fmt_, self.args, self.color);
        }
    };
}

pub fn ColorFormatter(comptime T: type) type {
    return struct {
        terminal: Terminal,
        data: T,

        pub fn init(data: T, terminal: std_Terminal) @This() {
            return .{ .data = data, .terminal = .{ .terminal = terminal } };
        }

        pub fn format(
            self: @This(),
            _: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            if (comptime std.meta.hasMethod(T, "formatTerminal")) {
                self.data.formatTerminal(self.terminal) catch |err| switch (err) {
                    std.Io.Writer.Error.WriteFailed => return std.Io.Writer.Error.WriteFailed,
                    std.Io.Terminal.SetColorError.Unexpected, std.Io.Terminal.SetColorError.Canceled => return std.Io.Writer.Error.WriteFailed,
                };
            } else {
                @compileError("missing formatTerminal method on type " ++ @typeName(T));
            }
        }
    };
}
