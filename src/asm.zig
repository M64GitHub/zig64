const std = @import("std");
const stdout = std.io.getStdOut().writer();

pub const Asm = @This();

pub const Group = enum {
    branch, // Jumps and branches (e.g., JSR, BEQ)
    load_store, // Load/store ops (e.g., LDA, STA)
    control, // CPU control (e.g., NOP, CLI)
    math, // Arithmetic (e.g., ADC, SBC)
    logic, // Bitwise (e.g., AND, ORA)
    compare, // Comparisons (e.g., CMP, CPX)
    shift, // Bit shifts (e.g., ASL, ROR)
    stack, // Stack ops (e.g., PHA, PHP)
    transfer, // Register transfers (e.g., TAX, TSX)
};

pub const AddrMode = enum {
    implied,
    immediate,
    zero_page,
    zero_page_x,
    zero_page_y,
    absolute,
    absolute_x,
    absolute_y,
    indirect,
    indexed_indirect_x, // (zp,x)
    indirect_indexed_y, // (zp),y
};

pub const OperandType = enum {
    none, // No operand source/target (e.g., NOP)
    register, // Direct register ops (e.g., TAX)
    memory, // Memory access (e.g., STA)
    immediate, // Literal value (e.g., LDA #$xx)
};

pub const OperandSize = enum {
    none,
    byte,
    word,
};

pub const AccessType = struct {
    pub const none: u2 = 0x00;
    pub const read: u2 = 0x01;
    pub const write: u2 = 0x02;
    pub const read_write: u2 = read | write; // 0x03
};

pub const OperandId = struct {
    pub const none: u8 = 0x00;
    pub const a: u8 = 0x01; // Accumulator
    pub const x: u8 = 0x02; // X register
    pub const y: u8 = 0x04; // Y register
    pub const sp: u8 = 0x08; // Stack pointer
    pub const memory: u8 = 0x10; // Memory access
    pub const constant: u8 = 0x20; // Immediate constant value (e.g., #$10)
};

pub const Operand = struct {
    id: u8,
    type: OperandType,
    size: OperandSize,
    access: u2,
    bytes: [2]u8 = [_]u8{ 0, 0 },
    len: u8 = 0, // How many bytes are valid
};

pub const Instruction = struct {
    opcode: u8, // e.g., 0xA9 for LDA immediate
    mnemonic: []const u8, // e.g., "LDA"
    addr_mode: AddrMode, // e.g., .immediate
    group: Group, // e.g., .load_store
    operand1: Operand, // e.g., the accumulator for LDA
    operand2: ?Operand = null, // Optional second operand, e.g., null or X for TAX
};

pub fn getInstructionSize(insn: Instruction) u8 {
    return switch (insn.addr_mode) {
        .implied => 1,
        .immediate,
        .zero_page,
        .zero_page_x,
        .zero_page_y,
        .indexed_indirect_x,
        .indirect_indexed_y,
        => 2,
        .absolute, .absolute_x, .absolute_y, .indirect => 3,
    };
}

pub fn disassembleForward(mem: []u8, pc_start: u16, count: usize) !void {
    var pc = pc_start;
    var counter: usize = 0;

    while (counter < count) : (counter += 1) {
        // Grab up to 3 bytes, pad with 0s if out of bounds
        var bytes: [3]u8 = .{ 0, 0, 0 };
        const end = @min(pc +% 3, mem.len);
        @memcpy(bytes[0..(end - pc)], mem[pc..end]);

        const insn = Asm.decodeInsn(&bytes);
        var obuf: [32]u8 = undefined;
        const str = try Asm.disassembleCodeLine(&obuf, pc, insn);
        stdout.print("{s}\n", .{str}) catch {};
        pc = pc +% Asm.getInstructionSize(insn);
    }
}

pub fn disassembleInsn(buffer: []u8, pc: u16, insn: Instruction) ![]const u8 {
    if (insn.group == .branch and insn.addr_mode == .immediate) {
        if (insn.operand1.len == 1) {
            const offset = @as(i8, @bitCast(insn.operand1.bytes[0]));
            const target = pc +% 2 +% @as(u16, @bitCast(@as(i16, offset)));
            return std.fmt.bufPrint(
                buffer,
                "{s} ${X:0>4}",
                .{ insn.mnemonic, target },
            );
        }
        return std.fmt.bufPrint(buffer, "{s}", .{insn.mnemonic});
    }

    switch (insn.addr_mode) {
        .implied => return std.fmt.bufPrint(buffer, "{s}", .{insn.mnemonic}),
        .immediate => {
            if (insn.operand2) |op| {
                return std.fmt.bufPrint(
                    buffer,
                    "{s} #${X:0>2}",
                    .{ insn.mnemonic, op.bytes[0] },
                );
            }
            return std.fmt.bufPrint(buffer, "{s}", .{insn.mnemonic});
        },
        .zero_page => {
            if (insn.operand2) |op| {
                return std.fmt.bufPrint(
                    buffer,
                    "{s} ${X:0>2}",
                    .{ insn.mnemonic, op.bytes[0] },
                );
            } else {
                return std.fmt.bufPrint(
                    buffer,
                    "{s} ${X:0>2}",
                    .{ insn.mnemonic, insn.operand1.bytes[0] },
                );
            }
        },
        .zero_page_x => {
            if (insn.operand2) |op| {
                return std.fmt.bufPrint(
                    buffer,
                    "{s} ${X:0>2},X",
                    .{ insn.mnemonic, op.bytes[0] },
                );
            }
            return std.fmt.bufPrint(buffer, "{s}", .{insn.mnemonic});
        },
        .zero_page_y => {
            if (insn.operand2) |op| {
                return std.fmt.bufPrint(
                    buffer,
                    "{s} ${X:0>2},Y",
                    .{ insn.mnemonic, op.bytes[0] },
                );
            }
            return std.fmt.bufPrint(buffer, "{s}", .{insn.mnemonic});
        },
        .absolute => {
            if (insn.operand2) |op| {
                const addr = @as(u16, op.bytes[0]) | (@as(u16, op.bytes[1]) << 8);
                return std.fmt.bufPrint(
                    buffer,
                    "{s} ${X:0>4}",
                    .{ insn.mnemonic, addr },
                );
            } else {
                const addr = @as(u16, insn.operand1.bytes[0]) |
                    (@as(u16, insn.operand1.bytes[1]) << 8);
                return std.fmt.bufPrint(
                    buffer,
                    "{s} ${X:0>4}",
                    .{ insn.mnemonic, addr },
                );
            }
        },
        .absolute_x => {
            if (insn.operand2) |op| {
                const addr = @as(u16, op.bytes[0]) |
                    (@as(u16, op.bytes[1]) << 8);
                return std.fmt.bufPrint(
                    buffer,
                    "{s} ${X:0>4},X",
                    .{ insn.mnemonic, addr },
                );
            }
            return std.fmt.bufPrint(buffer, "{s}", .{insn.mnemonic});
        },
        .absolute_y => {
            if (insn.operand2) |op| {
                const addr = @as(u16, op.bytes[0]) | (@as(u16, op.bytes[1]) << 8);
                return std.fmt.bufPrint(
                    buffer,
                    "{s} ${X:0>4},Y",
                    .{ insn.mnemonic, addr },
                );
            }
            return std.fmt.bufPrint(buffer, "{s}", .{insn.mnemonic});
        },
        .indirect => {
            if (insn.operand1.len == 2) {
                const addr = @as(u16, insn.operand1.bytes[0]) |
                    (@as(u16, insn.operand1.bytes[1]) << 8);
                return std.fmt.bufPrint(
                    buffer,
                    "{s} (${X:0>4})",
                    .{ insn.mnemonic, addr },
                );
            }
            return std.fmt.bufPrint(buffer, "{s}", .{insn.mnemonic});
        },
        .indexed_indirect_x => {
            if (insn.operand2) |op| {
                return std.fmt.bufPrint(
                    buffer,
                    "{s} (${X:0>2},X)",
                    .{ insn.mnemonic, op.bytes[0] },
                );
            }
            return std.fmt.bufPrint(buffer, "{s}", .{insn.mnemonic});
        },
        .indirect_indexed_y => {
            if (insn.operand2) |op| {
                return std.fmt.bufPrint(
                    buffer,
                    "{s} (${X:0>2}),Y",
                    .{ insn.mnemonic, op.bytes[0] },
                );
            }
            return std.fmt.bufPrint(buffer, "{s}", .{insn.mnemonic});
        },
    }

    return std.fmt.bufPrint(buffer, "{s}", .{insn.mnemonic});
}

pub fn disassembleCodeLine(buffer: []u8, pc: u16, insn: Instruction) ![]const u8 {
    const size = getInstructionSize(insn);
    var temp_buffer: [16]u8 = undefined;
    const disasm = try disassembleInsn(&temp_buffer, pc, insn);

    return switch (size) {
        1 => std.fmt.bufPrint(
            buffer,
            "{X:0>4}:  {X:0>2}        {s}",
            .{ pc, insn.opcode, disasm },
        ),

        2 => std.fmt.bufPrint(
            buffer,
            "{X:0>4}:  {X:0>2} {X:0>2}     {s}",
            .{
                pc,
                insn.opcode,
                if (insn.operand2) |op| op.bytes[0] else insn.operand1.bytes[0],
                disasm,
            },
        ),

        3 => std.fmt.bufPrint(
            buffer,
            "{X:0>4}:  {X:0>2} {X:0>2} {X:0>2}  {s}",
            .{
                pc,
                insn.opcode,
                if (insn.operand2) |op| op.bytes[0] else insn.operand1.bytes[0],
                if (insn.operand2) |op| op.bytes[1] else insn.operand1.bytes[1],
                disasm,
            },
        ),

        else => unreachable,
    };
}

pub fn decodeInsn(bytes: []u8) Instruction {
    const dummy = Instruction{
        .opcode = if (bytes.len > 0) bytes[0] else 0x00,
        .mnemonic = "???",
        .addr_mode = .implied,
        .group = .control,
        .operand1 = Operand{
            .id = OperandId.none,
            .type = .none,
            .size = .none,
            .access = AccessType.none,
        },
    };
    if (bytes.len == 0) return dummy;

    const opcode = bytes[0];

    return switch (opcode) {
        // Branch Instructions
        0x00 => { // BRK
            return brk;
        },
        0x20 => { // JSR
            var insn = jsr;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },
        0x40 => { // RTI
            return rti;
        },
        0x60 => { // RTS
            return rts;
        },
        0x4C => { // JMP absolute
            var insn = jmp_abs;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },
        0x6C => { // JMP indirect
            var insn = jmp_ind;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },
        0x10 => { // BPL
            var insn = bpl;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0x30 => { // BMI
            var insn = bmi;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0x50 => { // BVC
            var insn = bvc;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0x70 => { // BVS
            var insn = bvs;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0x90 => { // BCC
            var insn = bcc;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0xB0 => { // BCS
            var insn = bcs;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0xD0 => { // BNE
            var insn = bne;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0xF0 => { // BEQ
            var insn = beq;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },

        // Load/Store Instructions
        0xA9 => { // LDA immediate
            var insn = lda_imm;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xA5 => { // LDA zero page
            var insn = lda_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xB5 => { // LDA zero page X
            var insn = lda_zpx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xAD => { // LDA absolute
            var insn = lda_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0xBD => { // LDA absolute X
            var insn = lda_absx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0xB9 => { // LDA absolute Y
            var insn = lda_absy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0xA1 => { // LDA (indirect,X)
            var insn = lda_indx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xB1 => { // LDA (indirect),Y
            var insn = lda_indy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xA2 => { // LDX immediate
            var insn = ldx_imm;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xA6 => { // LDX zero page
            var insn = ldx_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xB6 => { // LDX zero page Y
            var insn = ldx_zpy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xAE => { // LDX absolute
            var insn = ldx_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0xBE => { // LDX absolute Y
            var insn = ldx_absy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0xA0 => { // LDY immediate
            var insn = ldy_imm;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xA4 => { // LDY zero page
            var insn = ldy_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xB4 => { // LDY zero page X
            var insn = ldy_zpx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xAC => { // LDY absolute
            var insn = ldy_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0xBC => { // LDY absolute X
            var insn = ldy_absx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x85 => { // STA zero page
            var insn = sta_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x95 => { // STA zero page X
            var insn = sta_zpx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x8D => { // STA absolute
            var insn = sta_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x9D => { // STA absolute X
            var insn = sta_absx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x99 => { // STA absolute Y
            var insn = sta_absy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x81 => { // STA (indirect,X)
            var insn = sta_indx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x91 => { // STA (indirect),Y
            var insn = sta_indy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x86 => { // STX zero page
            var insn = stx_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x96 => { // STX zero page Y
            var insn = stx_zpy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x8E => { // STX absolute
            var insn = stx_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x84 => { // STY zero page
            var insn = sty_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x94 => { // STY zero page X
            var insn = sty_zpx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x8C => { // STY absolute
            var insn = sty_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0xC6 => { // DEC zero page
            var insn = dec_zp;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0xD6 => { // DEC zero page X
            var insn = dec_zpx;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0xCE => { // DEC absolute
            var insn = dec_abs;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },
        0xDE => { // DEC absolute X
            var insn = dec_absx;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },
        0xE6 => { // INC zero page
            var insn = inc_zp;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0xF6 => { // INC zero page X
            var insn = inc_zpx;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0xEE => { // INC absolute
            var insn = inc_abs;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },
        0xFE => { // INC absolute X
            var insn = inc_absx;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },

        // Control Instructions
        0x18 => { // CLC
            return clc;
        },
        0x38 => { // SEC
            return sec;
        },
        0x58 => { // CLI
            return cli;
        },
        0x78 => { // SEI
            return sei;
        },
        0xB8 => { // CLV
            return clv;
        },
        0xD8 => { // CLD
            return cld;
        },
        0xF8 => { // SED
            return sed;
        },
        0xEA => { // NOP
            return nop;
        },

        // Math Instructions
        0x69 => { // ADC immediate
            var insn = adc_imm;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x65 => { // ADC zero page
            var insn = adc_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x75 => { // ADC zero page X
            var insn = adc_zpx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x6D => { // ADC absolute
            var insn = adc_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x7D => { // ADC absolute X
            var insn = adc_absx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x79 => { // ADC absolute Y
            var insn = adc_absy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x61 => { // ADC (indirect,X)
            var insn = adc_indx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x71 => { // ADC (indirect),Y
            var insn = adc_indy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xE9 => { // SBC immediate
            var insn = sbc_imm;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xE5 => { // SBC zero page
            var insn = sbc_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xF5 => { // SBC zero page X
            var insn = sbc_zpx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xED => { // SBC absolute
            var insn = sbc_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0xFD => { // SBC absolute X
            var insn = sbc_absx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0xF9 => { // SBC absolute Y
            var insn = sbc_absy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0xE1 => { // SBC (indirect,X)
            var insn = sbc_indx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xF1 => { // SBC (indirect),Y
            var insn = sbc_indy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },

        // Logic Instructions
        0x29 => { // AND immediate
            var insn = and_imm;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x25 => { // AND zero page
            var insn = and_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x35 => { // AND zero page X
            var insn = and_zpx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x2D => { // AND absolute
            var insn = and_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x3D => { // AND absolute X
            var insn = and_absx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x39 => { // AND absolute Y
            var insn = and_absy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x21 => { // AND (indirect,X)
            var insn = and_indx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x31 => { // AND (indirect),Y
            var insn = and_indy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x09 => { // ORA immediate
            var insn = ora_imm;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x05 => { // ORA zero page
            var insn = ora_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x15 => { // ORA zero page X
            var insn = ora_zpx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x0D => { // ORA absolute
            var insn = ora_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x1D => { // ORA absolute X
            var insn = ora_absx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x19 => { // ORA absolute Y
            var insn = ora_absy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x01 => { // ORA (indirect,X)
            var insn = ora_indx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x11 => { // ORA (indirect),Y
            var insn = ora_indy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x49 => { // XOR immediate
            var insn = xor_imm;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x45 => { // XOR zero page
            var insn = xor_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x55 => { // XOR zero page X
            var insn = xor_zpx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x4D => { // XOR absolute
            var insn = xor_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x5D => { // XOR absolute X
            var insn = xor_absx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x59 => { // XOR absolute Y
            var insn = xor_absy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0x41 => { // XOR (indirect,X)
            var insn = xor_indx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x51 => { // XOR (indirect),Y
            var insn = xor_indy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x24 => { // BIT zero page
            var insn = bit_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0x2C => { // BIT absolute
            var insn = bit_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },

        // Compare Instructions
        0xC9 => { // CMP immediate
            var insn = cmp_imm;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xC5 => { // CMP zero page
            var insn = cmp_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xD5 => { // CMP zero page X
            var insn = cmp_zpx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xCD => { // CMP absolute
            var insn = cmp_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0xDD => { // CMP absolute X
            var insn = cmp_absx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0xD9 => { // CMP absolute Y
            var insn = cmp_absy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0xC1 => { // CMP (indirect,X)
            var insn = cmp_indx;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xD1 => { // CMP (indirect),Y
            var insn = cmp_indy;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xE0 => { // CPX immediate
            var insn = cpx_imm;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xE4 => { // CPX zero page
            var insn = cpx_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xEC => { // CPX absolute
            var insn = cpx_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },
        0xC0 => { // CPY immediate
            var insn = cpy_imm;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xC4 => { // CPY zero page
            var insn = cpy_zp;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.len = 1;
            return insn;
        },
        0xCC => { // CPY absolute
            var insn = cpy_abs;
            insn.operand2.?.bytes[0] = bytes[1];
            insn.operand2.?.bytes[1] = bytes[2];
            insn.operand2.?.len = 2;
            return insn;
        },

        // Shift Instructions
        0x0A => { // ASL accumulator
            return asl_a;
        },
        0x06 => { // ASL zero page
            var insn = asl_zp;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0x16 => { // ASL zero page X
            var insn = asl_zpx;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0x0E => { // ASL absolute
            var insn = asl_abs;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },
        0x1E => { // ASL absolute X
            var insn = asl_absx;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },
        0x2A => { // ROL accumulator
            return rol_a;
        },
        0x26 => { // ROL zero page
            var insn = rol_zp;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0x36 => { // ROL zero page X
            var insn = rol_zpx;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0x2E => { // ROL absolute
            var insn = rol_abs;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },
        0x3E => { // ROL absolute X
            var insn = rol_absx;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },
        0x4A => { // LSR accumulator
            return lsr_a;
        },
        0x46 => { // LSR zero page
            var insn = lsr_zp;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0x56 => { // LSR zero page X
            var insn = lsr_zpx;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0x4E => { // LSR absolute
            var insn = lsr_abs;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },
        0x5E => { // LSR absolute X
            var insn = lsr_absx;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },
        0x6A => { // ROR accumulator
            return ror_a;
        },
        0x66 => { // ROR zero page
            var insn = ror_zp;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0x76 => { // ROR zero page X
            var insn = ror_zpx;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.len = 1;
            return insn;
        },
        0x6E => { // ROR absolute
            var insn = ror_abs;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },
        0x7E => { // ROR absolute X
            var insn = ror_absx;
            insn.operand1.bytes[0] = bytes[1];
            insn.operand1.bytes[1] = bytes[2];
            insn.operand1.len = 2;
            return insn;
        },

        // Stack Instructions
        0x48 => { // PHA
            return pha;
        },
        0x68 => { // PLA
            return pla;
        },
        0x08 => { // PHP
            return php;
        },
        0x28 => { // PLP
            return plp;
        },

        // Transfer Instructions
        0xAA => { // TAX
            return tax;
        },
        0xA8 => { // TAY
            return tay;
        },
        0x8A => { // TXA
            return txa;
        },
        0x98 => { // TYA
            return tya;
        },
        0xBA => { // TSX
            return tsx;
        },
        0x9A => { // TXS
            return txs;
        },
        0xCA => { // DEX
            return dex;
        },
        0x88 => { // DEY
            return dey;
        },
        0xE8 => { // INX
            return inx;
        },
        0xC8 => { // INY
            return iny;
        },

        // Unknown opcode
        else => dummy,
    };
}

// branch instructions
pub const brk = Instruction{
    .opcode = 0x00,
    .mnemonic = "BRK",
    .addr_mode = .implied,
    .group = .branch,
    .operand1 = Operand{
        .id = OperandId.sp,
        .type = .register,
        .size = .none,
        .access = AccessType.write,
    },
    .operand2 = null,
};
pub const jsr = Instruction{
    .opcode = 0x20,
    .mnemonic = "JSR",
    .addr_mode = .absolute,
    .group = .branch,
    .operand1 = Operand{
        .id = OperandId.sp | OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.write,
    }, // e.g., $1234
    .operand2 = null,
};
pub const rti = Instruction{
    .opcode = 0x40,
    .mnemonic = "RTI",
    .addr_mode = .implied,
    .group = .branch,
    .operand1 = Operand{
        .id = OperandId.sp,
        .type = .register,
        .size = .none,
        .access = AccessType.read,
    },
    .operand2 = null,
};
pub const rts = Instruction{
    .opcode = 0x60,
    .mnemonic = "RTS",
    .addr_mode = .implied,
    .group = .branch,
    .operand1 = Operand{
        .id = OperandId.sp,
        .type = .register,
        .size = .none,
        .access = AccessType.read,
    },
    .operand2 = null,
};
pub const jmp_abs = Instruction{
    .opcode = 0x4C,
    .mnemonic = "JMP",
    .addr_mode = .absolute,
    .group = .branch,
    .operand1 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    }, // e.g., $1234
    .operand2 = null,
};
pub const jmp_ind = Instruction{
    .opcode = 0x6C,
    .mnemonic = "JMP",
    .addr_mode = .indirect,
    .group = .branch,
    .operand1 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    }, // e.g., ($1234)
    .operand2 = null,
};
pub const bpl = Instruction{
    .opcode = 0x10,
    .mnemonic = "BPL",
    .addr_mode = .immediate,
    .group = .branch,
    .operand1 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    }, // e.g., +5
    .operand2 = null,
};
pub const bmi = Instruction{
    .opcode = 0x30,
    .mnemonic = "BMI",
    .addr_mode = .immediate,
    .group = .branch,
    .operand1 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = null,
};
pub const bvc = Instruction{
    .opcode = 0x50,
    .mnemonic = "BVC",
    .addr_mode = .immediate,
    .group = .branch,
    .operand1 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = null,
};
pub const bvs = Instruction{
    .opcode = 0x70,
    .mnemonic = "BVS",
    .addr_mode = .immediate,
    .group = .branch,
    .operand1 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = null,
};
pub const bcc = Instruction{
    .opcode = 0x90,
    .mnemonic = "BCC",
    .addr_mode = .immediate,
    .group = .branch,
    .operand1 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = null,
};
pub const bcs = Instruction{
    .opcode = 0xB0,
    .mnemonic = "BCS",
    .addr_mode = .immediate,
    .group = .branch,
    .operand1 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = null,
};
pub const bne = Instruction{
    .opcode = 0xD0,
    .mnemonic = "BNE",
    .addr_mode = .immediate,
    .group = .branch,
    .operand1 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = null,
};
pub const beq = Instruction{
    .opcode = 0xF0,
    .mnemonic = "BEQ",
    .addr_mode = .immediate,
    .group = .branch,
    .operand1 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = null,
};

// load/store instructions

pub const lda_imm = Instruction{
    .opcode = 0xA9,
    .mnemonic = "LDA",
    .addr_mode = .immediate,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    }, // #$10
};
pub const lda_zp = Instruction{
    .opcode = 0xA5,
    .mnemonic = "LDA",
    .addr_mode = .zero_page,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    }, // $50
};
pub const lda_zpx = Instruction{
    .opcode = 0xB5,
    .mnemonic = "LDA",
    .addr_mode = .zero_page_x,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const lda_abs = Instruction{
    .opcode = 0xAD,
    .mnemonic = "LDA",
    .addr_mode = .absolute,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    }, // $1234
};
pub const lda_absx = Instruction{
    .opcode = 0xBD,
    .mnemonic = "LDA",
    .addr_mode = .absolute_x,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const lda_absy = Instruction{
    .opcode = 0xB9,
    .mnemonic = "LDA",
    .addr_mode = .absolute_y,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const lda_indx = Instruction{
    .opcode = 0xA1,
    .mnemonic = "LDA",
    .addr_mode = .indexed_indirect_x,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    }, // ($50,X)
};
pub const lda_indy = Instruction{
    .opcode = 0xB1,
    .mnemonic = "LDA",
    .addr_mode = .indirect_indexed_y,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    }, // ($50),Y
};
pub const ldx_imm = Instruction{
    .opcode = 0xA2,
    .mnemonic = "LDX",
    .addr_mode = .immediate,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const ldx_zp = Instruction{
    .opcode = 0xA6,
    .mnemonic = "LDX",
    .addr_mode = .zero_page,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const ldx_zpy = Instruction{
    .opcode = 0xB6,
    .mnemonic = "LDX",
    .addr_mode = .zero_page_y,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const ldx_abs = Instruction{
    .opcode = 0xAE,
    .mnemonic = "LDX",
    .addr_mode = .absolute,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const ldx_absy = Instruction{
    .opcode = 0xBE,
    .mnemonic = "LDX",
    .addr_mode = .absolute_y,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const ldy_imm = Instruction{
    .opcode = 0xA0,
    .mnemonic = "LDY",
    .addr_mode = .immediate,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const ldy_zp = Instruction{
    .opcode = 0xA4,
    .mnemonic = "LDY",
    .addr_mode = .zero_page,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const ldy_zpx = Instruction{
    .opcode = 0xB4,
    .mnemonic = "LDY",
    .addr_mode = .zero_page_x,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const ldy_abs = Instruction{
    .opcode = 0xAC,
    .mnemonic = "LDY",
    .addr_mode = .absolute,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const ldy_absx = Instruction{
    .opcode = 0xBC,
    .mnemonic = "LDY",
    .addr_mode = .absolute_x,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const sta_zp = Instruction{
    .opcode = 0x85,
    .mnemonic = "STA",
    .addr_mode = .zero_page,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const sta_zpx = Instruction{
    .opcode = 0x95,
    .mnemonic = "STA",
    .addr_mode = .zero_page_x,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const sta_abs = Instruction{
    .opcode = 0x8D,
    .mnemonic = "STA",
    .addr_mode = .absolute,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.write,
    },
};
pub const sta_absx = Instruction{
    .opcode = 0x9D,
    .mnemonic = "STA",
    .addr_mode = .absolute_x,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.write,
    }, // $D400
};
pub const sta_absy = Instruction{
    .opcode = 0x99,
    .mnemonic = "STA",
    .addr_mode = .absolute_y,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .word,
        .access = AccessType.write,
    },
};
pub const sta_indx = Instruction{
    .opcode = 0x81,
    .mnemonic = "STA",
    .addr_mode = .indexed_indirect_x,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const sta_indy = Instruction{
    .opcode = 0x91,
    .mnemonic = "STA",
    .addr_mode = .indirect_indexed_y,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const stx_zp = Instruction{
    .opcode = 0x86,
    .mnemonic = "STX",
    .addr_mode = .zero_page,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const stx_zpy = Instruction{
    .opcode = 0x96,
    .mnemonic = "STX",
    .addr_mode = .zero_page_y,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const stx_abs = Instruction{
    .opcode = 0x8E,
    .mnemonic = "STX",
    .addr_mode = .absolute,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.write,
    },
};
pub const sty_zp = Instruction{
    .opcode = 0x84,
    .mnemonic = "STY",
    .addr_mode = .zero_page,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const sty_zpx = Instruction{
    .opcode = 0x94,
    .mnemonic = "STY",
    .addr_mode = .zero_page_x,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const sty_abs = Instruction{
    .opcode = 0x8C,
    .mnemonic = "STY",
    .addr_mode = .absolute,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.write,
    },
};
pub const dec_zp = Instruction{
    .opcode = 0xC6,
    .mnemonic = "DEC",
    .addr_mode = .zero_page,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const dec_zpx = Instruction{
    .opcode = 0xD6,
    .mnemonic = "DEC",
    .addr_mode = .zero_page_x,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const dec_abs = Instruction{
    .opcode = 0xCE,
    .mnemonic = "DEC",
    .addr_mode = .absolute,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const dec_absx = Instruction{
    .opcode = 0xDE,
    .mnemonic = "DEC",
    .addr_mode = .absolute_x,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const inc_zp = Instruction{
    .opcode = 0xE6,
    .mnemonic = "INC",
    .addr_mode = .zero_page,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const inc_zpx = Instruction{
    .opcode = 0xF6,
    .mnemonic = "INC",
    .addr_mode = .zero_page_x,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const inc_abs = Instruction{
    .opcode = 0xEE,
    .mnemonic = "INC",
    .addr_mode = .absolute,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const inc_absx = Instruction{
    .opcode = 0xFE,
    .mnemonic = "INC",
    .addr_mode = .absolute_x,
    .group = .load_store,
    .operand1 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};

// control instructions
pub const clc = Instruction{
    .opcode = 0x18,
    .mnemonic = "CLC",
    .addr_mode = .implied,
    .group = .control,
    .operand1 = Operand{
        .id = OperandId.none,
        .type = .none,
        .size = .none,
        .access = AccessType.none,
    },
    .operand2 = null,
};
pub const sec = Instruction{
    .opcode = 0x38,
    .mnemonic = "SEC",
    .addr_mode = .implied,
    .group = .control,
    .operand1 = Operand{
        .id = OperandId.none,
        .type = .none,
        .size = .none,
        .access = AccessType.none,
    },
    .operand2 = null,
};
pub const cli = Instruction{
    .opcode = 0x58,
    .mnemonic = "CLI",
    .addr_mode = .implied,
    .group = .control,
    .operand1 = Operand{
        .id = OperandId.none,
        .type = .none,
        .size = .none,
        .access = AccessType.none,
    },
    .operand2 = null,
};
pub const sei = Instruction{
    .opcode = 0x78,
    .mnemonic = "SEI",
    .addr_mode = .implied,
    .group = .control,
    .operand1 = Operand{
        .id = OperandId.none,
        .type = .none,
        .size = .none,
        .access = AccessType.none,
    },
    .operand2 = null,
};
pub const clv = Instruction{
    .opcode = 0xB8,
    .mnemonic = "CLV",
    .addr_mode = .implied,
    .group = .control,
    .operand1 = Operand{
        .id = OperandId.none,
        .type = .none,
        .size = .none,
        .access = AccessType.none,
    },
    .operand2 = null,
};
pub const cld = Instruction{
    .opcode = 0xD8,
    .mnemonic = "CLD",
    .addr_mode = .implied,
    .group = .control,
    .operand1 = Operand{
        .id = OperandId.none,
        .type = .none,
        .size = .none,
        .access = AccessType.none,
    },
    .operand2 = null,
};
pub const sed = Instruction{
    .opcode = 0xF8,
    .mnemonic = "SED",
    .addr_mode = .implied,
    .group = .control,
    .operand1 = Operand{
        .id = OperandId.none,
        .type = .none,
        .size = .none,
        .access = AccessType.none,
    },
    .operand2 = null,
};
pub const nop = Instruction{
    .opcode = 0xEA,
    .mnemonic = "NOP",
    .addr_mode = .implied,
    .group = .control,
    .operand1 = Operand{
        .id = OperandId.none,
        .type = .none,
        .size = .none,
        .access = AccessType.none,
    },
    .operand2 = null,
};

// math instructions
pub const adc_imm = Instruction{
    .opcode = 0x69,
    .mnemonic = "ADC",
    .addr_mode = .immediate,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const adc_zp = Instruction{
    .opcode = 0x65,
    .mnemonic = "ADC",
    .addr_mode = .zero_page,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const adc_zpx = Instruction{
    .opcode = 0x75,
    .mnemonic = "ADC",
    .addr_mode = .zero_page_x,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const adc_abs = Instruction{
    .opcode = 0x6D,
    .mnemonic = "ADC",
    .addr_mode = .absolute,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const adc_absx = Instruction{
    .opcode = 0x7D,
    .mnemonic = "ADC",
    .addr_mode = .absolute_x,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const adc_absy = Instruction{
    .opcode = 0x79,
    .mnemonic = "ADC",
    .addr_mode = .absolute_y,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const adc_indx = Instruction{
    .opcode = 0x61,
    .mnemonic = "ADC",
    .addr_mode = .indexed_indirect_x,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const adc_indy = Instruction{
    .opcode = 0x71,
    .mnemonic = "ADC",
    .addr_mode = .indirect_indexed_y,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const sbc_imm = Instruction{
    .opcode = 0xE9,
    .mnemonic = "SBC",
    .addr_mode = .immediate,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const sbc_zp = Instruction{
    .opcode = 0xE5,
    .mnemonic = "SBC",
    .addr_mode = .zero_page,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const sbc_zpx = Instruction{
    .opcode = 0xF5,
    .mnemonic = "SBC",
    .addr_mode = .zero_page_x,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const sbc_abs = Instruction{
    .opcode = 0xED,
    .mnemonic = "SBC",
    .addr_mode = .absolute,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const sbc_absx = Instruction{
    .opcode = 0xFD,
    .mnemonic = "SBC",
    .addr_mode = .absolute_x,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const sbc_absy = Instruction{
    .opcode = 0xF9,
    .mnemonic = "SBC",
    .addr_mode = .absolute_y,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const sbc_indx = Instruction{
    .opcode = 0xE1,
    .mnemonic = "SBC",
    .addr_mode = .indexed_indirect_x,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const sbc_indy = Instruction{
    .opcode = 0xF1,
    .mnemonic = "SBC",
    .addr_mode = .indirect_indexed_y,
    .group = .math,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};

// logic instructions
pub const and_imm = Instruction{
    .opcode = 0x29,
    .mnemonic = "AND",
    .addr_mode = .immediate,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const and_zp = Instruction{
    .opcode = 0x25,
    .mnemonic = "AND",
    .addr_mode = .zero_page,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const and_zpx = Instruction{
    .opcode = 0x35,
    .mnemonic = "AND",
    .addr_mode = .zero_page_x,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const and_abs = Instruction{
    .opcode = 0x2D,
    .mnemonic = "AND",
    .addr_mode = .absolute,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const and_absx = Instruction{
    .opcode = 0x3D,
    .mnemonic = "AND",
    .addr_mode = .absolute_x,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const and_absy = Instruction{
    .opcode = 0x39,
    .mnemonic = "AND",
    .addr_mode = .absolute_y,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const and_indx = Instruction{
    .opcode = 0x21,
    .mnemonic = "AND",
    .addr_mode = .indexed_indirect_x,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const and_indy = Instruction{
    .opcode = 0x31,
    .mnemonic = "AND",
    .addr_mode = .indirect_indexed_y,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const ora_imm = Instruction{
    .opcode = 0x09,
    .mnemonic = "ORA",
    .addr_mode = .immediate,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const ora_zp = Instruction{
    .opcode = 0x05,
    .mnemonic = "ORA",
    .addr_mode = .zero_page,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const ora_zpx = Instruction{
    .opcode = 0x15,
    .mnemonic = "ORA",
    .addr_mode = .zero_page_x,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const ora_abs = Instruction{
    .opcode = 0x0D,
    .mnemonic = "ORA",
    .addr_mode = .absolute,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const ora_absx = Instruction{
    .opcode = 0x1D,
    .mnemonic = "ORA",
    .addr_mode = .absolute_x,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const ora_absy = Instruction{
    .opcode = 0x19,
    .mnemonic = "ORA",
    .addr_mode = .absolute_y,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const ora_indx = Instruction{
    .opcode = 0x01,
    .mnemonic = "ORA",
    .addr_mode = .indexed_indirect_x,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const ora_indy = Instruction{
    .opcode = 0x11,
    .mnemonic = "ORA",
    .addr_mode = .indirect_indexed_y,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const xor_imm = Instruction{
    .opcode = 0x49,
    .mnemonic = "XOR",
    .addr_mode = .immediate,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const xor_zp = Instruction{
    .opcode = 0x45,
    .mnemonic = "XOR",
    .addr_mode = .zero_page,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const xor_zpx = Instruction{
    .opcode = 0x55,
    .mnemonic = "XOR",
    .addr_mode = .zero_page_x,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const xor_abs = Instruction{
    .opcode = 0x4D,
    .mnemonic = "XOR",
    .addr_mode = .absolute,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const xor_absx = Instruction{
    .opcode = 0x5D,
    .mnemonic = "XOR",
    .addr_mode = .absolute_x,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const xor_absy = Instruction{
    .opcode = 0x59,
    .mnemonic = "XOR",
    .addr_mode = .absolute_y,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const xor_indx = Instruction{
    .opcode = 0x41,
    .mnemonic = "XOR",
    .addr_mode = .indexed_indirect_x,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const xor_indy = Instruction{
    .opcode = 0x51,
    .mnemonic = "XOR",
    .addr_mode = .indirect_indexed_y,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const bit_zp = Instruction{
    .opcode = 0x24,
    .mnemonic = "BIT",
    .addr_mode = .zero_page,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const bit_abs = Instruction{
    .opcode = 0x2C,
    .mnemonic = "BIT",
    .addr_mode = .absolute,
    .group = .logic,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};

// compare instructions
pub const cmp_imm = Instruction{
    .opcode = 0xC9,
    .mnemonic = "CMP",
    .addr_mode = .immediate,
    .group = .compare,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const cmp_zp = Instruction{
    .opcode = 0xC5,
    .mnemonic = "CMP",
    .addr_mode = .zero_page,
    .group = .compare,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const cmp_zpx = Instruction{
    .opcode = 0xD5,
    .mnemonic = "CMP",
    .addr_mode = .zero_page_x,
    .group = .compare,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const cmp_abs = Instruction{
    .opcode = 0xCD,
    .mnemonic = "CMP",
    .addr_mode = .absolute,
    .group = .compare,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const cmp_absx = Instruction{
    .opcode = 0xDD,
    .mnemonic = "CMP",
    .addr_mode = .absolute_x,
    .group = .compare,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const cmp_absy = Instruction{
    .opcode = 0xD9,
    .mnemonic = "CMP",
    .addr_mode = .absolute_y,
    .group = .compare,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const cmp_indx = Instruction{
    .opcode = 0xC1,
    .mnemonic = "CMP",
    .addr_mode = .indexed_indirect_x,
    .group = .compare,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const cmp_indy = Instruction{
    .opcode = 0xD1,
    .mnemonic = "CMP",
    .addr_mode = .indirect_indexed_y,
    .group = .compare,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory | OperandId.y,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const cpx_imm = Instruction{
    .opcode = 0xE0,
    .mnemonic = "CPX",
    .addr_mode = .immediate,
    .group = .compare,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const cpx_zp = Instruction{
    .opcode = 0xE4,
    .mnemonic = "CPX",
    .addr_mode = .zero_page,
    .group = .compare,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const cpx_abs = Instruction{
    .opcode = 0xEC,
    .mnemonic = "CPX",
    .addr_mode = .absolute,
    .group = .compare,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};
pub const cpy_imm = Instruction{
    .opcode = 0xC0,
    .mnemonic = "CPY",
    .addr_mode = .immediate,
    .group = .compare,
    .operand1 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.constant,
        .type = .immediate,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const cpy_zp = Instruction{
    .opcode = 0xC4,
    .mnemonic = "CPY",
    .addr_mode = .zero_page,
    .group = .compare,
    .operand1 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
};
pub const cpy_abs = Instruction{
    .opcode = 0xCC,
    .mnemonic = "CPY",
    .addr_mode = .absolute,
    .group = .compare,
    .operand1 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read,
    },
};

// shift instructions
pub const asl_a = Instruction{
    .opcode = 0x0A,
    .mnemonic = "ASL",
    .addr_mode = .implied,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const asl_zp = Instruction{
    .opcode = 0x06,
    .mnemonic = "ASL",
    .addr_mode = .zero_page,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const asl_zpx = Instruction{
    .opcode = 0x16,
    .mnemonic = "ASL",
    .addr_mode = .zero_page_x,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const asl_abs = Instruction{
    .opcode = 0x0E,
    .mnemonic = "ASL",
    .addr_mode = .absolute,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const asl_absx = Instruction{
    .opcode = 0x1E,
    .mnemonic = "ASL",
    .addr_mode = .absolute_x,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const rol_a = Instruction{
    .opcode = 0x2A,
    .mnemonic = "ROL",
    .addr_mode = .implied,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const rol_zp = Instruction{
    .opcode = 0x26,
    .mnemonic = "ROL",
    .addr_mode = .zero_page,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const rol_zpx = Instruction{
    .opcode = 0x36,
    .mnemonic = "ROL",
    .addr_mode = .zero_page_x,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const rol_abs = Instruction{
    .opcode = 0x2E,
    .mnemonic = "ROL",
    .addr_mode = .absolute,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const rol_absx = Instruction{
    .opcode = 0x3E,
    .mnemonic = "ROL",
    .addr_mode = .absolute_x,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const lsr_a = Instruction{
    .opcode = 0x4A,
    .mnemonic = "LSR",
    .addr_mode = .implied,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const lsr_zp = Instruction{
    .opcode = 0x46,
    .mnemonic = "LSR",
    .addr_mode = .zero_page,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const lsr_zpx = Instruction{
    .opcode = 0x56,
    .mnemonic = "LSR",
    .addr_mode = .zero_page_x,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const lsr_abs = Instruction{
    .opcode = 0x4E,
    .mnemonic = "LSR",
    .addr_mode = .absolute,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const lsr_absx = Instruction{
    .opcode = 0x5E,
    .mnemonic = "LSR",
    .addr_mode = .absolute_x,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const ror_a = Instruction{
    .opcode = 0x6A,
    .mnemonic = "ROR",
    .addr_mode = .implied,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const ror_zp = Instruction{
    .opcode = 0x66,
    .mnemonic = "ROR",
    .addr_mode = .zero_page,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const ror_zpx = Instruction{
    .opcode = 0x76,
    .mnemonic = "ROR",
    .addr_mode = .zero_page_x,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const ror_abs = Instruction{
    .opcode = 0x6E,
    .mnemonic = "ROR",
    .addr_mode = .absolute,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory,
        .type = .memory,
        .size = .word,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const ror_absx = Instruction{
    .opcode = 0x7E,
    .mnemonic = "ROR",
    .addr_mode = .absolute_x,
    .group = .shift,
    .operand1 = Operand{
        .id = OperandId.memory | OperandId.x,
        .type = .memory,
        .size = .word,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};

// stack instructions
pub const pha = Instruction{
    .opcode = 0x48,
    .mnemonic = "PHA",
    .addr_mode = .implied,
    .group = .stack,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.sp | OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const pla = Instruction{
    .opcode = 0x68,
    .mnemonic = "PLA",
    .addr_mode = .implied,
    .group = .stack,
    .operand1 = Operand{
        .id = OperandId.sp | OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const php = Instruction{
    .opcode = 0x08,
    .mnemonic = "PHP",
    .addr_mode = .implied,
    .group = .stack,
    .operand1 = Operand{
        .id = OperandId.sp | OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.write,
    },
    .operand2 = null,
};
pub const plp = Instruction{
    .opcode = 0x28,
    .mnemonic = "PLP",
    .addr_mode = .implied,
    .group = .stack,
    .operand1 = Operand{
        .id = OperandId.sp | OperandId.memory,
        .type = .memory,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = null,
};

// transfer instructions
pub const tax = Instruction{
    .opcode = 0xAA,
    .mnemonic = "TAX",
    .addr_mode = .implied,
    .group = .transfer,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const tay = Instruction{
    .opcode = 0xA8,
    .mnemonic = "TAY",
    .addr_mode = .implied,
    .group = .transfer,
    .operand1 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const txa = Instruction{
    .opcode = 0x8A,
    .mnemonic = "TXA",
    .addr_mode = .implied,
    .group = .transfer,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const tya = Instruction{
    .opcode = 0x98,
    .mnemonic = "TYA",
    .addr_mode = .implied,
    .group = .transfer,
    .operand1 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.a,
        .type = .register,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const tsx = Instruction{
    .opcode = 0xBA,
    .mnemonic = "TSX",
    .addr_mode = .implied,
    .group = .transfer,
    .operand1 = Operand{
        .id = OperandId.sp,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const txs = Instruction{
    .opcode = 0x9A,
    .mnemonic = "TXS",
    .addr_mode = .implied,
    .group = .transfer,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read,
    },
    .operand2 = Operand{
        .id = OperandId.sp,
        .type = .register,
        .size = .byte,
        .access = AccessType.write,
    },
};
pub const dex = Instruction{
    .opcode = 0xCA,
    .mnemonic = "DEX",
    .addr_mode = .implied,
    .group = .transfer,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const dey = Instruction{
    .opcode = 0x88,
    .mnemonic = "DEY",
    .addr_mode = .implied,
    .group = .transfer,
    .operand1 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const inx = Instruction{
    .opcode = 0xE8,
    .mnemonic = "INX",
    .addr_mode = .implied,
    .group = .transfer,
    .operand1 = Operand{
        .id = OperandId.x,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
pub const iny = Instruction{
    .opcode = 0xC8,
    .mnemonic = "INY",
    .addr_mode = .implied,
    .group = .transfer,
    .operand1 = Operand{
        .id = OperandId.y,
        .type = .register,
        .size = .byte,
        .access = AccessType.read_write,
    },
    .operand2 = null,
};
