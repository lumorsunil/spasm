const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Options = struct {
    command: ?Command = null,
    errors: std.ArrayList([]const u8) = .empty,
    err: ?Error = null,

    pub const Result = union(enum) {
        err: Options,
        success: ValidatedOptions,

        pub fn fromArgs(allocator: Allocator, args: std.process.Args) @This() {
            var options: Options = .{};

            var it = try args.iterateAllocator(allocator);
            _ = it.next();
            const ctx: ParseContext = .{
                .allocator = allocator,
                .args = &it,
            };
            options.parseArgs(ctx) catch |err| {
                options.err = err;
                return .{ .err = options };
            };

            const validated_options = options.validate(allocator) catch |err| {
                options.err = err;
                return .{ .err = options };
            };

            return .{ .success = validated_options };
        }
    };

    fn parseArgs(self: *@This(), ctx: ParseContext) Error!void {
        while (ctx.args.next()) |arg| try self.parseArg(ctx, arg);
    }

    fn validate(self: *@This(), allocator: Allocator) Error!ValidatedOptions {
        const command = self.command orelse return self.reportError(
            allocator,
            Error.RequiresCommand,
            "specify a command",
            .{},
        );

        return .{
            .command = command,
        };
    }

    fn reportError(
        self: *@This(),
        allocator: Allocator,
        err: Error,
        comptime fmt: []const u8,
        args: anytype,
    ) Error {
        try self.errors.append(allocator, try std.fmt.allocPrint(allocator, fmt, args));
        return err;
    }

    pub fn parseArg(
        self: *@This(),
        ctx: ParseContext,
        arg: []const u8,
    ) Error!void {
        inline for (std.meta.tags(CommandTag)) |command_tag| {
            if (std.mem.eql(u8, arg, command_tag.commandString())) {
                return command_tag.commandFn()(self, ctx);
            }
        }

        return self.reportError(ctx.allocator, Error.InvalidArgs, "unknown arg \"{s}\"", .{arg});
    }

    fn parseBuildCommand(
        self: *@This(),
        ctx: ParseContext,
    ) Error!void {
        const entry_file_path = ctx.args.next() orelse return self.reportError(
            ctx.allocator,
            Error.InvalidArgs,
            "build command requires an entry file path",
            .{},
        );
        try self.setCommand(ctx.allocator, .{ .build = .{ .entry_file_path = entry_file_path } });
    }

    fn parseAstTest(
        self: *@This(),
        ctx: ParseContext,
    ) Error!void {
        try self.setCommand(ctx.allocator, .ast_test);
    }

    pub fn setCommand(
        self: *@This(),
        allocator: Allocator,
        command: Command,
    ) Error!void {
        try self.validateSetCommand(allocator, command);
        self.command = command;
    }

    fn validateSetCommand(
        self: *@This(),
        allocator: Allocator,
        command: Command,
    ) Error!void {
        if (self.command) |prev_command| return self.reportError(
            allocator,
            Error.CommandAlreadySet,
            "invalid command arg \"{s}\": command already set to \"{s}\"",
            .{
                std.meta.activeTag(command).commandString(),
                std.meta.activeTag(prev_command).commandString(),
            },
        );
    }

    pub const CommandTag = enum {
        build,
        ast_test,

        pub fn commandString(self: @This()) []const u8 {
            return switch (self) {
                .build => "build",
                .ast_test => "ast-test",
            };
        }

        pub fn commandFn(self: @This()) *const fn (*Options, ParseContext) Error!void {
            return switch (self) {
                .build => parseBuildCommand,
                .ast_test => parseAstTest,
            };
        }
    };

    pub const Command = union(CommandTag) {
        build: Build,
        ast_test,

        pub const Build = struct {
            entry_file_path: []const u8,
        };
    };

    const ParseContext = struct {
        allocator: Allocator,
        args: *std.process.Args.Iterator,
    };

    pub const Error = error{
        CommandAlreadySet,
        InvalidArgs,
        RequiresCommand,
    } || Allocator.Error;
};

pub const ValidatedOptions = struct {
    command: Options.Command,
};
