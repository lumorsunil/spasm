const Options = @import("options.zig").Options;
const ValidatedOptions = @import("options.zig").ValidatedOptions;
const Stdio = @import("stdio.zig").Stdio;

pub fn processOptions(options_result: Options.Result, stdio: *Stdio) !?ValidatedOptions {
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
