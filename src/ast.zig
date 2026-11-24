const std = @import("std");
const CompilationContext = @import("compiler.zig").CompilationContext;
const Token = @import("tokenizer.zig").Token;
const Range = @import("tokenizer.zig").Range;

pub const Node = struct {
    uri: []const u8,
    id: Id,
    type: Type,
    start: Token,
    end: Token,

    pub fn range(self: @This()) Range {
        return .init(self.start.start, self.end.end);
    }

    pub const Id = usize;

    pub const Type = union(enum) {
        expr_u8: ExprU8,
        expr_u16: ExprU16,
        instruction: Instruction,
        emit: Emit,
        block: Block,
        binary_decl: BinaryDecl,
        binary_operation: BinaryOperation,
        string: []const u8,
        identifier: Identifier,
        label: []const u8,
        declaration: Declaration,
    };

    pub const Instruction = union(enum) {
        lda_immediate: struct {
            value: ExprU8,
            pub const mnemonic = "lda";
            pub const opcode = 0xA9;
        },
    };

    pub const ExprU8 = union(enum) {
        literal: u8,

        pub fn evaluate(self: @This(), ctx: *CompilationContext) !u8 {
            _ = ctx;
            return switch (self) {
                .literal => |s| s,
            };
        }
    };

    pub const ExprU16 = union(enum) {
        literal: u16,

        pub fn evaluate(self: @This(), ctx: *CompilationContext) !u16 {
            _ = ctx;
            return switch (self) {
                .literal => |s| s,
            };
        }
    };

    pub const Identifier = []const u8;

    pub const Emit = struct {
        node: Id,
    };

    pub const Block = struct {
        children: []const Id,
    };

    pub const BinaryDecl = struct {
        target: Target,
        base_address: Id,
        node: Id,

        pub const Target = union(enum) {
            virtual,
            file: Id,
        };
    };

    pub const BinaryOperation = struct {
        op: BinaryOp,
        lhs: Id,
        rhs: Id,

        pub const BinaryOp = enum {
            assign,
            add,
            subtract,
            multiply,
            divide,

            pub fn format(
                self: @This(),
                writer: *std.Io.Writer,
            ) std.Io.Writer.Error!void {
                const s = switch (self) {
                    .assign => "=",
                    .add => "+",
                    .subtract => "-",
                    .multiply => "*",
                    .divide => "/",
                };

                try writer.writeAll(s);
            }
        };
    };

    pub const Declaration = struct {
        identifier: []const u8,
        type_expr: Id,
        initializer: Id,
    };
};
