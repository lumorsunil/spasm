const std = @import("std");
const Range = @import("tokenizer.zig").Range;
const ReaderContainer = @import("parser.zig").ReaderContainer;

pub const Diagnostic = struct {
    uri: []const u8,
    severity: Severity,
    message: []const u8,
    range: Range,

    pub const Severity = enum { debug, info, warn, err };

    const Formatter = struct {
        reader_container: *ReaderContainer,
        diagnostic: Diagnostic,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("{f}", .{self.diagnostic});

            ({
                const reader = try self.reader_container.request(self.diagnostic.uri);
                try reader.seekTo(self.diagnostic.range.start.index);
            }) catch |err| {
                try writer.print("Error reading {s}: {}", .{ self.diagnostic.uri, err });
                return;
            };
        }
    };

    pub fn formatWithSource(
        self: @This(),
        reader_container: *ReaderContainer,
    ) Formatter {
        return .{
            .reader_container = reader_container,
            .diagnostic = self,
        };
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("[{t}]: {s}:{},{}: {s}", .{
            self.severity,
            self.uri,
            self.range.start.line,
            self.range.start.column,
            self.message,
        });
    }
};
