const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ReaderContainer = struct {
    io: std.Io,
    allocator: Allocator,
    reader_map: std.StringHashMapUnmanaged(std.Io.File.Reader) = .empty,

    pub fn init(io: std.Io, allocator: Allocator) @This() {
        return .{ .io = io, .allocator = allocator };
    }

    pub fn request(self: *@This(), uri: []const u8) Error!*std.Io.File.Reader {
        if (self.reader_map.getPtr(uri)) |cached| return cached;

        const file = try std.Io.Dir.cwd().openFile(self.io, uri, .{});
        errdefer file.close(self.io);

        const file_reader = file.reader(self.io, try self.allocator.alloc(u8, 4096));
        try self.reader_map.put(self.allocator, uri, file_reader);
        return self.reader_map.getPtr(uri).?;
    }

    pub fn dispose(self: *@This(), uri: []const u8) void {
        const entry = self.reader_map.fetchRemove(uri) orelse return;
        entry.value.file.close(self.io);
    }

    pub const Error = error{} || std.Io.File.OpenError || Allocator.Error;
};
