const std = @import("std");
const builtin = @import("builtin");
const OP = @import("OP.zig");
const leb = std.leb;
const dwarf = std.dwarf;
const abi = dwarf.abi;
const mem = std.mem;
const assert = std.debug.assert;

/// Expressions can be evaluated in different contexts, each requiring its own set of inputs.
/// Callers should specify all the fields relevant to their context. If a field is required
/// by the expression and it isn't in the context, error.IncompleteExpressionContext is returned.
pub const ExpressionContext = struct {
    /// If specified, any addresses will pass through this function before being
    isValidMemory: ?*const fn (address: usize) bool = null,

    /// The compilation unit this expression relates to, if any
    compile_unit: ?*const dwarf.CompileUnit = null,

    /// Thread context
    thread_context: ?*std.debug.ThreadContext = null,
    reg_context: ?abi.RegisterContext = null,

    /// Call frame address, if in a CFI context
    cfa: ?usize = null,
};

pub const ExpressionOptions = struct {
    /// The address size of the target architecture
    addr_size: u8 = @sizeOf(usize),

    /// Endianess of the target architecture
    endian: std.builtin.Endian = .Little,

    /// Restrict the stack machine to a subset of opcodes used in call frame instructions
    call_frame_context: bool = false,
};

/// A stack machine that can decode and run DWARF expressions.
/// Expressions can be decoded for non-native address size and endianness,
/// but can only be executed if the current target matches the configuration.
pub fn StackMachine(comptime options: ExpressionOptions) type {
    const addr_type = switch (options.addr_size) {
        2 => u16,
        4 => u32,
        8 => u64,
        else => @compileError("Unsupported address size of " ++ options.addr_size),
    };

    const addr_type_signed = switch (options.addr_size) {
        2 => i16,
        4 => i32,
        8 => i64,
        else => @compileError("Unsupported address size of " ++ options.addr_size),
    };

    return struct {
        const Self = @This();

        const Operand = union(enum) {
            generic: addr_type,
            register: u8,
            type_size: u8,
            branch_offset: i16,
            base_register: struct {
                base_register: u8,
                offset: i64,
            },
            composite_location: struct {
                size: u64,
                offset: i64,
            },
            block: []const u8,
            register_type: struct {
                register: u8,
                type_offset: u64,
            },
            const_type: struct {
                type_offset: u64,
                value_bytes: []const u8,
            },
            deref_type: struct {
                size: u8,
                type_offset: u64,
            },
        };

        const Value = union(enum) {
            generic: addr_type,

            // Typed value with a maximum size of a register
            regval_type: struct {
                // Offset of DW_TAG_base_type DIE
                type_offset: u64,
                type_size: u8,
                value: addr_type,
            },

            // Typed value specified directly in the instruction stream
            const_type: struct {
                // Offset of DW_TAG_base_type DIE
                type_offset: u64,
                // Backed by the instruction stream
                value_bytes: []const u8,
            },

            pub fn asIntegral(self: Value) !addr_type {
                return switch (self) {
                    .generic => |v| v,

                    // TODO: For these two prongs, look up the type and assert it's integral?
                    .regval_type => |regval_type| regval_type.value,
                    .const_type => |const_type| {
                        const value: u64 = switch (const_type.value_bytes.len) {
                            1 => mem.readIntSliceNative(u8, const_type.value_bytes),
                            2 => mem.readIntSliceNative(u16, const_type.value_bytes),
                            4 => mem.readIntSliceNative(u32, const_type.value_bytes),
                            8 => mem.readIntSliceNative(u64, const_type.value_bytes),
                            else => return error.InvalidIntegralTypeSize,
                        };

                        return std.math.cast(addr_type, value) orelse error.TruncatedIntegralType;
                    },
                };
            }
        };

        stack: std.ArrayListUnmanaged(Value) = .{},

        pub fn reset(self: *Self) void {
            self.stack.clearRetainingCapacity();
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.stack.deinit(allocator);
        }

        fn generic(value: anytype) Operand {
            const int_info = @typeInfo(@TypeOf(value)).Int;
            if (@sizeOf(@TypeOf(value)) > options.addr_size) {
                return .{ .generic = switch (int_info.signedness) {
                    .signed => @bitCast(@as(addr_type_signed, @truncate(value))),
                    .unsigned => @truncate(value),
                } };
            } else {
                return .{ .generic = switch (int_info.signedness) {
                    .signed => @bitCast(@as(addr_type_signed, @intCast(value))),
                    .unsigned => @intCast(value),
                } };
            }
        }

        pub fn readOperand(stream: *std.io.FixedBufferStream([]const u8), opcode: u8) !?Operand {
            const reader = stream.reader();
            return switch (opcode) {
                OP.addr,
                OP.call_ref,
                => generic(try reader.readInt(addr_type, options.endian)),
                OP.const1u,
                OP.pick,
                => generic(try reader.readByte()),
                OP.deref_size,
                OP.xderef_size,
                => .{ .type_size = try reader.readByte() },
                OP.const1s => generic(try reader.readByteSigned()),
                OP.const2u,
                OP.call2,
                => generic(try reader.readInt(u16, options.endian)),
                OP.call4 => generic(try reader.readInt(u32, options.endian)),
                OP.const2s => generic(try reader.readInt(i16, options.endian)),
                OP.bra,
                OP.skip,
                => .{ .branch_offset = try reader.readInt(i16, options.endian) },
                OP.const4u => generic(try reader.readInt(u32, options.endian)),
                OP.const4s => generic(try reader.readInt(i32, options.endian)),
                OP.const8u => generic(try reader.readInt(u64, options.endian)),
                OP.const8s => generic(try reader.readInt(i64, options.endian)),
                OP.constu,
                OP.plus_uconst,
                OP.addrx,
                OP.constx,
                OP.convert,
                OP.reinterpret,
                => generic(try leb.readULEB128(u64, reader)),
                OP.consts,
                OP.fbreg,
                => generic(try leb.readILEB128(i64, reader)),
                OP.lit0...OP.lit31 => |n| generic(n - OP.lit0),
                OP.reg0...OP.reg31 => |n| .{ .register = n - OP.reg0 },
                OP.breg0...OP.breg31 => |n| .{ .base_register = .{
                    .base_register = n - OP.breg0,
                    .offset = try leb.readILEB128(i64, reader),
                } },
                OP.regx => .{ .register = try leb.readULEB128(u8, reader) },
                OP.bregx => blk: {
                    const base_register = try leb.readULEB128(u8, reader);
                    const offset = try leb.readILEB128(i64, reader);
                    break :blk .{ .base_register = .{
                        .base_register = base_register,
                        .offset = offset,
                    } };
                },
                OP.regval_type => blk: {
                    const register = try leb.readULEB128(u8, reader);
                    const type_offset = try leb.readULEB128(u64, reader);
                    break :blk .{ .register_type = .{
                        .register = register,
                        .type_offset = type_offset,
                    } };
                },
                OP.piece => .{
                    .composite_location = .{
                        .size = try leb.readULEB128(u8, reader),
                        .offset = 0,
                    },
                },
                OP.bit_piece => blk: {
                    const size = try leb.readULEB128(u8, reader);
                    const offset = try leb.readILEB128(i64, reader);
                    break :blk .{ .composite_location = .{
                        .size = size,
                        .offset = offset,
                    } };
                },
                OP.implicit_value, OP.entry_value => blk: {
                    const size = try leb.readULEB128(u8, reader);
                    if (stream.pos + size > stream.buffer.len) return error.InvalidExpression;
                    const block = stream.buffer[stream.pos..][0..size];
                    stream.pos += size;
                    break :blk .{
                        .block = block,
                    };
                },
                OP.const_type => blk: {
                    const type_offset = try leb.readULEB128(u8, reader);
                    const size = try reader.readByte();
                    if (stream.pos + size > stream.buffer.len) return error.InvalidExpression;
                    const value_bytes = stream.buffer[stream.pos..][0..size];
                    stream.pos += size;
                    break :blk .{ .const_type = .{
                        .type_offset = type_offset,
                        .value_bytes = value_bytes,
                    } };
                },
                OP.deref_type,
                OP.xderef_type,
                => .{
                    .deref_type = .{
                        .size = try reader.readByte(),
                        .type_offset = try leb.readULEB128(u64, reader),
                    },
                },
                OP.lo_user...OP.hi_user => return error.UnimplementedUserOpcode,
                else => null,
            };
        }

        pub fn run(
            self: *Self,
            expression: []const u8,
            allocator: std.mem.Allocator,
            context: ExpressionContext,
            initial_value: usize,
        ) !Value {
            try self.stack.append(allocator, .{ .generic = initial_value });
            var stream = std.io.fixedBufferStream(expression);
            while (try self.step(&stream, allocator, context)) {}
            if (self.stack.items.len == 0) return error.InvalidExpression;
            return self.stack.items[self.stack.items.len - 1];
        }

        /// Reads an opcode and its operands from the stream and executes it
        pub fn step(
            self: *Self,
            stream: *std.io.FixedBufferStream([]const u8),
            allocator: std.mem.Allocator,
            context: ExpressionContext,
        ) !bool {
            if (@sizeOf(usize) != @sizeOf(addr_type) or options.endian != comptime builtin.target.cpu.arch.endian())
                @compileError("Execution of non-native address sizees / endianness is not supported");

            const opcode = try stream.reader().readByte();
            if (options.call_frame_context and !opcodeValidInCFA(opcode)) return error.InvalidCFAOpcode;
            switch (opcode) {

                // 2.5.1.1: Literal Encodings
                OP.lit0...OP.lit31,
                OP.addr,
                OP.const1u,
                OP.const2u,
                OP.const4u,
                OP.const8u,
                OP.const1s,
                OP.const2s,
                OP.const4s,
                OP.const8s,
                OP.constu,
                OP.consts,
                => try self.stack.append(allocator, .{ .generic = (try readOperand(stream, opcode)).?.generic }),

                OP.const_type => {
                    const const_type = (try readOperand(stream, opcode)).?.const_type;
                    try self.stack.append(allocator, .{ .const_type = .{
                        .type_offset = const_type.type_offset,
                        .value_bytes = const_type.value_bytes,
                    } });
                },

                OP.addrx,
                OP.constx,
                => {
                    const debug_addr_index = (try readOperand(stream, opcode)).?.generic;

                    // TODO: Read item from .debug_addr, this requires need DW_AT_addr_base of the compile unit, push onto stack as generic

                    _ = debug_addr_index;
                    unreachable;
                },

                // 2.5.1.2: Register Values
                OP.fbreg => {
                    if (context.compile_unit == null) return error.ExpressionRequiresCompileUnit;
                    if (context.compile_unit.?.frame_base == null) return error.ExpressionRequiresFrameBase;

                    const offset: i64 = @intCast((try readOperand(stream, opcode)).?.generic);
                    _ = offset;

                    switch (context.compile_unit.?.frame_base.?.*) {
                        .ExprLoc => {
                            // TODO: Run this expression in a nested stack machine
                            return error.UnimplementedOpcode;
                        },
                        .LocListOffset => {
                            // TODO: Read value from .debug_loclists
                            return error.UnimplementedOpcode;
                        },
                        .SecOffset => {
                            // TODO: Read value from .debug_loclists
                            return error.UnimplementedOpcode;
                        },
                        else => return error.InvalidFrameBase,
                    }
                },
                OP.breg0...OP.breg31,
                OP.bregx,
                => {
                    if (context.thread_context == null) return error.IncompleteExpressionContext;

                    const base_register = (try readOperand(stream, opcode)).?.base_register;
                    var value: i64 = @intCast(mem.readIntSliceNative(usize, try abi.regBytes(
                        context.thread_context.?,
                        base_register.base_register,
                        context.reg_context,
                    )));
                    value += base_register.offset;
                    try self.stack.append(allocator, .{ .generic = @intCast(value) });
                },
                OP.regval_type => {
                    const register_type = (try readOperand(stream, opcode)).?.register_type;
                    const value = mem.readIntSliceNative(usize, try abi.regBytes(
                        context.thread_context.?,
                        register_type.register,
                        context.reg_context,
                    ));
                    try self.stack.append(allocator, .{
                        .regval_type = .{
                            .type_offset = register_type.type_offset,
                            .type_size = @sizeOf(addr_type),
                            .value = value,
                        },
                    });
                },

                // 2.5.1.3: Stack Operations
                OP.dup => {
                    if (self.stack.items.len == 0) return error.InvalidExpression;
                    try self.stack.append(allocator, self.stack.items[self.stack.items.len - 1]);
                },
                OP.drop => {
                    _ = self.stack.pop();
                },
                OP.pick, OP.over => {
                    const stack_index = if (opcode == OP.over) 1 else (try readOperand(stream, opcode)).?.generic;
                    if (stack_index >= self.stack.items.len) return error.InvalidExpression;
                    try self.stack.append(allocator, self.stack.items[self.stack.items.len - 1 - stack_index]);
                },
                OP.swap => {
                    if (self.stack.items.len < 2) return error.InvalidExpression;
                    mem.swap(Value, &self.stack.items[self.stack.items.len - 1], &self.stack.items[self.stack.items.len - 2]);
                },
                OP.rot => {
                    if (self.stack.items.len < 3) return error.InvalidExpression;
                    const first = self.stack.items[self.stack.items.len - 1];
                    self.stack.items[self.stack.items.len - 1] = self.stack.items[self.stack.items.len - 2];
                    self.stack.items[self.stack.items.len - 2] = self.stack.items[self.stack.items.len - 3];
                    self.stack.items[self.stack.items.len - 3] = first;
                },
                OP.deref,
                OP.xderef,
                OP.deref_size,
                OP.xderef_size,
                OP.deref_type,
                OP.xderef_type,
                => {
                    if (self.stack.items.len == 0) return error.InvalidExpression;
                    var addr = try self.stack.items[self.stack.items.len - 1].asIntegral();
                    const addr_space_identifier: ?usize = switch (opcode) {
                        OP.xderef,
                        OP.xderef_size,
                        OP.xderef_type,
                        => try self.stack.pop().asIntegral(),
                        else => null,
                    };

                    // Usage of addr_space_identifier in the address calculation is implementation defined.
                    // This code will need to be updated to handle any architectures that utilize this.
                    _ = addr_space_identifier;

                    if (context.isValidMemory) |isValidMemory| if (!isValidMemory(addr)) return error.InvalidExpression;

                    const operand = try readOperand(stream, opcode);
                    const size = switch (opcode) {
                        OP.deref => @sizeOf(addr_type),
                        OP.deref_size,
                        OP.xderef_size,
                        => operand.?.type_size,
                        OP.deref_type,
                        OP.xderef_type,
                        => operand.?.deref_type.size,
                        else => unreachable,
                    };

                    const value: addr_type = std.math.cast(addr_type, @as(u64, switch (size) {
                        1 => @as(*const u8, @ptrFromInt(addr)).*,
                        2 => @as(*const u16, @ptrFromInt(addr)).*,
                        4 => @as(*const u32, @ptrFromInt(addr)).*,
                        8 => @as(*const u64, @ptrFromInt(addr)).*,
                        else => return error.InvalidExpression,
                    })) orelse return error.InvalidExpression;

                    if (opcode == OP.deref_type) {
                        self.stack.items[self.stack.items.len - 1] = .{
                            .regval_type = .{
                                .type_offset = operand.?.deref_type.type_offset,
                                .type_size = operand.?.deref_type.size,
                                .value = value,
                            },
                        };
                    } else {
                        self.stack.items[self.stack.items.len - 1] = .{ .generic = value };
                    }
                },
                OP.push_object_address,
                OP.form_tls_address,
                => {
                    return error.UnimplementedExpressionOpcode;
                },
                OP.call_frame_cfa => {
                    if (context.cfa) |cfa| {
                        try self.stack.append(allocator, .{ .generic = cfa });
                    } else return error.IncompleteExpressionContext;
                },

                // 2.5.1.4: Arithmetic and Logical Operations
                OP.abs => {
                    if (self.stack.items.len == 0) return error.InvalidExpression;
                    const value: addr_type_signed = @bitCast(try self.stack.items[self.stack.items.len - 1].asIntegral());
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = std.math.absCast(value),
                    };
                },
                OP.@"and" => {
                    if (self.stack.items.len < 2) return error.InvalidExpression;
                    const a = try self.stack.pop().asIntegral();
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = a & try self.stack.items[self.stack.items.len - 1].asIntegral(),
                    };
                },
                OP.div => {
                    if (self.stack.items.len < 2) return error.InvalidExpression;
                    const a: addr_type_signed = @bitCast(try self.stack.pop().asIntegral());
                    const b: addr_type_signed = @bitCast(try self.stack.items[self.stack.items.len - 1].asIntegral());
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = @bitCast(try std.math.divTrunc(addr_type_signed, b, a)),
                    };
                },
                OP.minus => {
                    if (self.stack.items.len < 2) return error.InvalidExpression;
                    const b = try self.stack.pop().asIntegral();
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = try std.math.sub(addr_type, try self.stack.items[self.stack.items.len - 1].asIntegral(), b),
                    };
                },
                OP.mod => {
                    if (self.stack.items.len < 2) return error.InvalidExpression;
                    const a: addr_type_signed = @bitCast(try self.stack.pop().asIntegral());
                    const b: addr_type_signed = @bitCast(try self.stack.items[self.stack.items.len - 1].asIntegral());
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = @bitCast(@mod(b, a)),
                    };
                },
                OP.mul => {
                    if (self.stack.items.len < 2) return error.InvalidExpression;
                    const a: addr_type_signed = @bitCast(try self.stack.pop().asIntegral());
                    const b: addr_type_signed = @bitCast(try self.stack.items[self.stack.items.len - 1].asIntegral());
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = @bitCast(@mulWithOverflow(a, b)[0]),
                    };
                },
                OP.neg => {
                    if (self.stack.items.len == 0) return error.InvalidExpression;
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = @bitCast(
                            try std.math.negate(
                                @as(addr_type_signed, @bitCast(try self.stack.items[self.stack.items.len - 1].asIntegral())),
                            ),
                        ),
                    };
                },
                OP.not => {
                    if (self.stack.items.len == 0) return error.InvalidExpression;
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = ~try self.stack.items[self.stack.items.len - 1].asIntegral(),
                    };
                },
                OP.@"or" => {
                    if (self.stack.items.len < 2) return error.InvalidExpression;
                    const a = try self.stack.pop().asIntegral();
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = a | try self.stack.items[self.stack.items.len - 1].asIntegral(),
                    };
                },
                OP.plus => {
                    if (self.stack.items.len < 2) return error.InvalidExpression;
                    const b = try self.stack.pop().asIntegral();
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = try std.math.add(addr_type, try self.stack.items[self.stack.items.len - 1].asIntegral(), b),
                    };
                },
                OP.plus_uconst => {
                    if (self.stack.items.len == 0) return error.InvalidExpression;
                    const constant = (try readOperand(stream, opcode)).?.generic;
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = try std.math.add(addr_type, try self.stack.items[self.stack.items.len - 1].asIntegral(), constant),
                    };
                },
                OP.shl => {
                    if (self.stack.items.len < 2) return error.InvalidExpression;
                    const a = try self.stack.pop().asIntegral();
                    const b = try self.stack.items[self.stack.items.len - 1].asIntegral();
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = std.math.shl(usize, b, a),
                    };
                },
                OP.shr => {
                    if (self.stack.items.len < 2) return error.InvalidExpression;
                    const a = try self.stack.pop().asIntegral();
                    const b = try self.stack.items[self.stack.items.len - 1].asIntegral();
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = std.math.shr(usize, b, a),
                    };
                },
                OP.shra => {
                    if (self.stack.items.len < 2) return error.InvalidExpression;
                    const a = try self.stack.pop().asIntegral();
                    const b: addr_type_signed = @bitCast(try self.stack.items[self.stack.items.len - 1].asIntegral());
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = @bitCast(std.math.shr(addr_type_signed, b, a)),
                    };
                },
                OP.xor => {
                    if (self.stack.items.len < 2) return error.InvalidExpression;
                    const a = try self.stack.pop().asIntegral();
                    self.stack.items[self.stack.items.len - 1] = .{
                        .generic = a ^ try self.stack.items[self.stack.items.len - 1].asIntegral(),
                    };
                },

                // 2.5.1.5: Control Flow Operations
                OP.le,
                OP.ge,
                OP.eq,
                OP.lt,
                OP.gt,
                OP.ne,
                => {
                    if (self.stack.items.len < 2) return error.InvalidExpression;
                    const a = self.stack.pop();
                    const b = self.stack.items[self.stack.items.len - 1];

                    if (a == .generic and b == .generic) {
                        const a_int: addr_type_signed = @bitCast(a.asIntegral() catch unreachable);
                        const b_int: addr_type_signed = @bitCast(b.asIntegral() catch unreachable);
                        const result = @intFromBool(switch (opcode) {
                            OP.le => b_int < a_int,
                            OP.ge => b_int >= a_int,
                            OP.eq => b_int == a_int,
                            OP.lt => b_int < a_int,
                            OP.gt => b_int > a_int,
                            OP.ne => b_int != a_int,
                            else => unreachable,
                        });

                        self.stack.items[self.stack.items.len - 1] = .{ .generic = result };
                    } else {
                        // TODO: Load the types referenced by these values, find their comparison operator, and run it
                        return error.UnimplementedTypedComparison;
                    }
                },
                OP.skip, OP.bra => {
                    const branch_offset = (try readOperand(stream, opcode)).?.branch_offset;
                    const condition = if (opcode == OP.bra) blk: {
                        if (self.stack.items.len == 0) return error.InvalidExpression;
                        break :blk try self.stack.pop().asIntegral() != 0;
                    } else true;

                    if (condition) {
                        const new_pos = std.math.cast(
                            usize,
                            try std.math.add(addr_type_signed, @as(addr_type_signed, @intCast(stream.pos)), branch_offset),
                        ) orelse return error.InvalidExpression;

                        if (new_pos < 0 or new_pos >= stream.buffer.len) return error.InvalidExpression;
                        stream.pos = new_pos;
                    }
                },
                OP.call2,
                OP.call4,
                OP.call_ref,
                => {
                    const debug_info_offset = (try readOperand(stream, opcode)).?.generic;
                    _ = debug_info_offset;

                    // TODO: Load a DIE entry at debug_info_offset in a .debug_info section (the spec says that it
                    //       can be in a separate exe / shared object from the one containing this expression).
                    //       Transfer control to the DW_AT_location attribute, with the current stack as input.

                    return error.UnimplementedExpressionCall;
                },

                // 2.5.1.6: Type Conversions
                OP.convert => {
                    if (self.stack.items.len == 0) return error.InvalidExpression;
                    const type_offset = (try readOperand(stream, opcode)).?.generic;
                    _ = type_offset;

                    // TODO: Load the DW_TAG_base_type entry in context.compile_unit, find a conversion operator
                    //       from the old type to the new type, run it.

                    return error.UnimplementedTypeConversion;
                },
                OP.reinterpret => {
                    if (self.stack.items.len == 0) return error.InvalidExpression;
                    const type_offset = (try readOperand(stream, opcode)).?.generic;

                    // TODO: Load the DW_TAG_base_type entries in context.compile_unit and verify both types are the same size
                    const value = self.stack.items[self.stack.items.len - 1];
                    if (type_offset == 0) {
                        self.stack.items[self.stack.items.len - 1] = .{ .generic = try value.asIntegral() };
                    } else {
                        self.stack.items[self.stack.items.len - 1] = switch (value) {
                            .generic => |v| .{
                                .regval_type = .{
                                    .type_offset = type_offset,
                                    .type_size = @sizeOf(addr_type),
                                    .value = v,
                                },
                            },
                            .regval_type => |r| .{
                                .regval_type = .{
                                    .type_offset = type_offset,
                                    .type_size = r.type_size,
                                    .value = r.value,
                                },
                            },
                            .const_type => |c| .{
                                .const_type = .{
                                    .type_offset = type_offset,
                                    .value_bytes = c.value_bytes,
                                },
                            },
                        };
                    }
                },

                // 2.5.1.7: Special Operations
                OP.nop => {},
                OP.entry_value => {
                    const block = (try readOperand(stream, opcode)).?.block;
                    _ = block;

                    // TODO: If block is an expression, run it on a new stack. Push the resulting value onto this stack.
                    // TODO: If block is a register location, push the value that location had before running this program onto this stack.
                    //       This implies capturing all register values before executing this block, in case this program modifies them.
                    // TODO: If the block contains, OP.push_object_address, treat it as OP.nop

                    return error.UnimplementedSubExpression;
                },

                // These have already been handled by readOperand
                OP.lo_user...OP.hi_user => unreachable,
                else => {
                    //std.debug.print("Unknown DWARF expression opcode: {x}\n", .{opcode});
                    return error.UnknownExpressionOpcode;
                },
            }

            return stream.pos < stream.buffer.len;
        }
    };
}

pub fn Builder(comptime options: ExpressionOptions) type {
    const addr_type = switch (options.addr_size) {
        2 => u16,
        4 => u32,
        8 => u64,
        else => @compileError("Unsupported address size of " ++ options.addr_size),
    };

    return struct {
        /// Zero-operand instructions
        pub fn writeOpcode(writer: anytype, comptime opcode: u8) !void {
            if (options.call_frame_context and !comptime opcodeValidInCFA(opcode)) return error.InvalidCFAOpcode;
            switch (opcode) {
                OP.dup,
                OP.drop,
                OP.over,
                OP.swap,
                OP.rot,
                OP.deref,
                OP.xderef,
                OP.push_object_address,
                OP.form_tls_address,
                OP.call_frame_cfa,
                OP.abs,
                OP.@"and",
                OP.div,
                OP.minus,
                OP.mod,
                OP.mul,
                OP.neg,
                OP.not,
                OP.@"or",
                OP.plus,
                OP.shl,
                OP.shr,
                OP.shra,
                OP.xor,
                OP.le,
                OP.ge,
                OP.eq,
                OP.lt,
                OP.gt,
                OP.ne,
                OP.nop,
                => try writer.writeByte(opcode),
                else => @compileError("This opcode requires operands, use write<Opcode>() instead"),
            }
        }

        // 2.5.1.1: Literal Encodings
        pub fn writeLiteral(writer: anytype, literal: u8) !void {
            switch (literal) {
                0...31 => |n| try writer.writeByte(n + OP.lit0),
                else => return error.InvalidLiteral,
            }
        }

        pub fn writeConst(writer: anytype, comptime T: type, value: T) !void {
            if (@typeInfo(T) != .Int) @compileError("Constants must be integers");

            switch (T) {
                u8, i8, u16, i16, u32, i32, u64, i64 => {
                    try writer.writeByte(switch (T) {
                        u8 => OP.const1u,
                        i8 => OP.const1s,
                        u16 => OP.const2u,
                        i16 => OP.const2s,
                        u32 => OP.const4u,
                        i32 => OP.const4s,
                        u64 => OP.const8u,
                        i64 => OP.const8s,
                    });

                    try writer.writeInt(T, value, options.endian);
                },
                else => switch (@typeInfo(T).Int.signedness) {
                    .unsigned => {
                        try writer.writeByte(OP.constu);
                        try leb.writeULEB128(writer, value);
                    },
                    .signed => {
                        try writer.writeByte(OP.consts);
                        try leb.writeILEB128(writer, value);
                    },
                },
            }
        }

        pub fn writeConstx(writer: anytype, debug_addr_offset: anytype) !void {
            try writer.writeByte(OP.constx);
            try leb.writeULEB128(writer, debug_addr_offset);
        }

        pub fn writeConstType(writer: anytype, die_offset: anytype, size: u8, value_bytes: []const u8) !void {
            if (options.call_frame_context) return error.InvalidCFAOpcode;
            if (size != value_bytes.len) return error.InvalidValueSize;
            try writer.writeByte(OP.const_type);
            try leb.writeULEB128(writer, die_offset);
            try writer.writeByte(size);
            try writer.writeAll(value_bytes);
        }

        pub fn writeAddr(writer: anytype, value: addr_type) !void {
            try writer.writeByte(OP.addr);
            try writer.writeInt(addr_type, value, options.endian);
        }

        pub fn writeAddrx(writer: anytype, debug_addr_offset: anytype) !void {
            if (options.call_frame_context) return error.InvalidCFAOpcode;
            try writer.writeByte(OP.addrx);
            try leb.writeULEB128(writer, debug_addr_offset);
        }

        // 2.5.1.2: Register Values
        pub fn writeFbreg(writer: anytype, offset: anytype) !void {
            try writer.writeByte(OP.fbreg);
            try leb.writeILEB128(writer, offset);
        }

        pub fn writeBreg(writer: anytype, register: u8, offset: anytype) !void {
            if (register > 31) return error.InvalidRegister;
            try writer.writeByte(OP.reg0 + register);
            try leb.writeILEB128(writer, offset);
        }

        pub fn writeBregx(writer: anytype, register: anytype, offset: anytype) !void {
            try writer.writeByte(OP.bregx);
            try leb.writeULEB128(writer, register);
            try leb.writeILEB128(writer, offset);
        }

        pub fn writeRegvalType(writer: anytype, register: anytype, offset: anytype) !void {
            if (options.call_frame_context) return error.InvalidCFAOpcode;
            try writer.writeByte(OP.bregx);
            try leb.writeULEB128(writer, register);
            try leb.writeULEB128(writer, offset);
        }

        // 2.5.1.3: Stack Operations
        pub fn writePick(writer: anytype, index: u8) !void {
            try writer.writeByte(OP.pick);
            try writer.writeByte(index);
        }

        pub fn writeDerefSize(writer: anytype, size: u8) !void {
            try writer.writeByte(OP.deref_size);
            try writer.writeByte(size);
        }

        pub fn writeXDerefSize(writer: anytype, size: u8) !void {
            try writer.writeByte(OP.xderef_size);
            try writer.writeByte(size);
        }

        pub fn writeDerefType(writer: anytype, size: u8, die_offset: anytype) !void {
            if (options.call_frame_context) return error.InvalidCFAOpcode;
            try writer.writeByte(OP.deref_type);
            try writer.writeByte(size);
            try leb.writeULEB128(writer, die_offset);
        }

        pub fn writeXDerefType(writer: anytype, size: u8, die_offset: anytype) !void {
            try writer.writeByte(OP.xderef_type);
            try writer.writeByte(size);
            try leb.writeULEB128(writer, die_offset);
        }

        // 2.5.1.4: Arithmetic and Logical Operations

        pub fn writePlusUconst(writer: anytype, uint_value: anytype) !void {
            try writer.writeByte(OP.plus_uconst);
            try leb.writeULEB128(writer, uint_value);
        }

        // 2.5.1.5: Control Flow Operations

        pub fn writeSkip(writer: anytype, offset: i16) !void {
            try writer.writeByte(OP.skip);
            try writer.writeInt(i16, offset, options.endian);
        }

        pub fn writeBra(writer: anytype, offset: i16) !void {
            try writer.writeByte(OP.bra);
            try writer.writeInt(i16, offset, options.endian);
        }

        pub fn writeCall(writer: anytype, comptime T: type, offset: T) !void {
            if (options.call_frame_context) return error.InvalidCFAOpcode;
            switch (T) {
                u16 => try writer.writeByte(OP.call2),
                u32 => try writer.writeByte(OP.call4),
                else => @compileError("Call operand must be a 2 or 4 byte offset"),
            }

            try writer.writeInt(T, offset, options.endian);
        }

        pub fn writeCallRef(writer: anytype, debug_info_offset: addr_type) !void {
            if (options.call_frame_context) return error.InvalidCFAOpcode;
            try writer.writeByte(OP.call_ref);
            try writer.writeInt(addr_type, debug_info_offset, options.endian);
        }

        pub fn writeConvert(writer: anytype, die_offset: anytype) !void {
            if (options.call_frame_context) return error.InvalidCFAOpcode;
            try writer.writeByte(OP.convert);
            try leb.writeULEB128(writer, die_offset);
        }

        pub fn writeReinterpret(writer: anytype, die_offset: anytype) !void {
            if (options.call_frame_context) return error.InvalidCFAOpcode;
            try writer.writeByte(OP.reinterpret);
            try leb.writeULEB128(writer, die_offset);
        }

        // 2.5.1.7: Special Operations

        pub fn writeEntryValue(writer: anytype, expression: []const u8) !void {
            try writer.writeByte(OP.entry_value);
            try leb.writeULEB128(writer, expression.len);
            try writer.writeAll(expression);
        }

        // 2.6: Location Descriptions
        // TODO

    };
}

// Certain opcodes are not allowed in a CFA context, see 6.4.2
fn opcodeValidInCFA(opcode: u8) bool {
    return switch (opcode) {
        OP.addrx,
        OP.call2,
        OP.call4,
        OP.call_ref,
        OP.const_type,
        OP.constx,
        OP.convert,
        OP.deref_type,
        OP.regval_type,
        OP.reinterpret,
        OP.push_object_address,
        OP.call_frame_cfa,
        => false,
        else => true,
    };
}

const testing = std.testing;
test "DWARF expressions" {
    const allocator = std.testing.allocator;

    const options = ExpressionOptions{};
    var stack_machine = StackMachine(options){};
    defer stack_machine.deinit(allocator);

    const b = Builder(options);

    var program = std.ArrayList(u8).init(allocator);
    defer program.deinit();

    const writer = program.writer();

    // Literals
    {
        const context = ExpressionContext{};
        for (0..32) |i| {
            try b.writeLiteral(writer, @intCast(i));
        }

        _ = try stack_machine.run(program.items, allocator, context, 0);

        for (0..32) |i| {
            const expected = 31 - i;
            try testing.expectEqual(expected, stack_machine.stack.popOrNull().?.generic);
        }
    }
}
