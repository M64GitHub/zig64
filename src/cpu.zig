const std = @import("std");
const stdout = std.io.getStdOut().writer();

const Ram64k = @import("mem.zig");
const Sid = @import("sid.zig");
const Vic = @import("vic.zig");
const Asm = @import("asm.zig");

pub const Cpu = @This();

pc: u16,
sp: u8,
a: u8,
x: u8,
y: u8,
status: u8,
flags: CpuFlags,
opcode_last: u8,
cycles_executed: u32,
cycles_last_step: u8,
mem: *Ram64k,
sid: *Sid,
vic: *Vic,
dbg_enabled: bool,

pub const CpuFlags = struct {
    c: u1,
    z: u1,
    i: u1,
    d: u1,
    b: u1,
    unused: u1,
    v: u1,
    n: u1,
};

pub const FlagBit = enum(u8) {
    negative = 0b10000000,
    overflow = 0b01000000,
    unused = 0b000100000,
    brk = 0b000010000,
    decimal = 0b000001000,
    intDisable = 0b000000100,
    zero = 0b000000010,
    carry = 0b000000001,
};

pub fn init(mem: *Ram64k, sid: *Sid, vic: *Vic, pc_start: u16) Cpu {
    return Cpu{
        .pc = pc_start,
        .sp = 0xFF,
        .a = 0,
        .x = 0,
        .y = 0,
        .status = 0x00, // Default status flags (Interrupt disable set)
        .flags = CpuFlags{
            .c = 0,
            .z = 0,
            .i = 1, // Interrupt Disable set on boot
            .d = 0,
            .b = 0,
            .unused = 1, // Always 1 in 6502
            .v = 0,
            .n = 0,
        },
        .cycles_executed = 0,
        .cycles_last_step = 0,
        .opcode_last = 0x00, // No opcode executed yet
        .mem = mem,
        .sid = sid,
        .vic = vic,
        .dbg_enabled = false,
    };
}

fn doReset(cpu: *Cpu) void {
    // leaves memory unchanged
    cpu.a = 0;
    cpu.x = 0;
    cpu.y = 0;
    cpu.sp = 0xFD;
    cpu.status = 0x24;
    cpu.pc = 0xFFFC;
    cpu.flags = CpuFlags{
        .c = 0,
        .z = 0,
        .i = 0,
        .d = 0,
        .b = 0,
        .unused = 1,
        .v = 0,
        .n = 0,
    };

    cpu.cycles_executed = 0;
    cpu.cycles_last_step = 0;
    cpu.opcode_last = 0x00;
}

// Reset Cpu and clear memory
fn doHardReset(cpu: *Cpu) void {
    cpu.reset();
    cpu.mem.clear();
}

pub fn reset(cpu: *Cpu, hard: bool) void {
    if (hard) {
        if (cpu.dbg_enabled)
            stdout.print("[cpu] hard reset\n", .{}) catch {};
        cpu.doHardReset();
    } else {
        if (cpu.dbg_enabled)
            stdout.print("[cpu] reset\n", .{}) catch {};
        cpu.reset();
    }
}

pub fn writeMem(cpu: *Cpu, data: []const u8, addr: u16) void {
    var offs: u32 = 0;
    var i: u16 = addr;
    while (offs < data.len) : (i +%= 1) {
        cpu.mem.data[i] = data[offs];
        offs += 1;
    }
}

fn bytesToHex(memory: []u8, pc: usize, size: usize) [8]u8 {
    // Result is always 8 chars: "xx xx xx" or "xx xx   " or "xx      "
    var result: [8]u8 = "        ".*; // Start with 8 spaces
    const hex_chars = "0123456789ABCDEF";

    const clamped_size = @min(size, 3);
    const max_bytes = @min(clamped_size, memory.len - pc);

    for (0..max_bytes) |i| {
        const byte = memory[pc + i];
        const pos = i * 3;
        result[pos] = hex_chars[byte >> 4];
        result[pos + 1] = hex_chars[byte & 0xF];
    }

    return result;
}

fn padTo16(input: []const u8, maxlen: usize, buffer: *[16]u8) []u8 {
    buffer.* = "                ".*;
    const limit = @min(maxlen, 16);
    const len = @min(input.len, limit);
    @memcpy(buffer[0..len], input[0..len]);
    return buffer[0..limit]; // Safe because buffer lives outside
}

pub fn printStatus(cpu: *Cpu) void {
    var buf_disasm: [16]u8 = undefined;
    var buf_disasm_pad: [16]u8 = undefined;

    var bytes: [3]u8 = .{ 0, 0, 0 };
    const end = @min(cpu.pc +% 3, cpu.mem.data.len);
    @memcpy(bytes[0..(end - cpu.pc)], cpu.mem.data[cpu.pc..end]);
    const insn = Asm.decodeInstruction(&bytes);
    const disasm = Asm.disassembleInstruction(&buf_disasm, cpu.pc, insn) catch
        "???";

    const insn_size = Asm.getInstructionSize(insn);

    stdout.print("[cpu] PC: {X:0>4} | {s} | {s} | A: {X:0>2} | X: {X:0>2} | Y: {X:0>2} | SP: {X:0>2} | Cycl: {d:0>2} | Cycl-TT: {d} | ", .{
        cpu.pc,
        bytesToHex(&cpu.mem.data, cpu.pc, insn_size),
        padTo16(disasm, 12, &buf_disasm_pad),
        cpu.a,
        cpu.x,
        cpu.y,
        cpu.sp,
        cpu.cycles_last_step,
        cpu.cycles_executed,
    }) catch {};
    printFlags(cpu);
    stdout.print("\n", .{}) catch {};
}

pub fn printTrace(cpu: *Cpu) void {
    stdout.print("PC: {X:0>4} OP: {X:0>2} {X:0>2} {X:0>2} A:{X:0>2} X:{X:0>2} Y:{X:0>2} FL:{X:0>2}", .{
        cpu.pc,
        cpu.mem.data[cpu.pc],
        cpu.mem.data[cpu.pc + 1],
        cpu.mem.data[cpu.pc + 2],
        cpu.a,
        cpu.x,
        cpu.y,
        cpu.status,
    }) catch {};
    stdout.print("\n", .{}) catch {};
}

pub fn printFlags(cpu: *Cpu) void {
    cpu.flagsToPS();
    stdout.print("FL: {b:0>8}", .{cpu.status}) catch {};
}

pub fn readByte(cpu: *Cpu, addr: u16) u8 {
    const sid_base = cpu.sid.base_address;
    if ((addr >= sid_base) and (addr <= (sid_base + 25))) {
        const val = cpu.sid.registers[addr - 0xD400];
        if (cpu.sid.dbg_enabled) {
            std.debug.print(
                "[sid] Read ${X:04} = {X:02}, PC={X:04}\n",
                .{ addr, val, cpu.pc },
            );
        }
        return val;
    }
    return cpu.mem.data[addr];
}

pub fn readWord(cpu: *Cpu, addr: u16) u16 {
    const LoByte: u8 = cpu.readByte(addr);
    const HiByte: u8 = cpu.readByte(addr + 1); // No wrap for stack, etc.
    return @as(u16, LoByte) | (@as(u16, HiByte) << 8);
}

pub fn readWordZP(cpu: *Cpu, addr: u8) u16 {
    const LoByte: u8 = cpu.readByte(addr);
    const HiByte: u8 = cpu.readByte((addr +% 1) & 0xFF); // Wrap for zero page
    return @as(u16, LoByte) | (@as(u16, HiByte) << 8);
}

pub fn writeByte(cpu: *Cpu, val: u8, addr: u16) void {
    const sid_base = cpu.sid.base_address;
    // check sid reg writes
    if ((addr >= sid_base) and (addr <= (sid_base + 25))) {
        cpu.sid.writeRegisterCycle(addr - sid_base, val, cpu.cycles_executed);
    }
    cpu.mem.data[addr] = val;
    cpu.cycles_executed +%= 1;
}

pub fn writeWord(cpu: *Cpu, val: u16, addr: u16) void {
    cpu.mem.data[addr] = @truncate(val & 0xFF);
    cpu.mem.data[addr + 1] = @truncate(val >> 8);
    cpu.cycles_executed +%= 2;
}

pub fn sidRegWritten(cpu: *Cpu) bool {
    return cpu.sid.reg_written;
}

fn flagsToPS(cpu: *Cpu) void {
    var ps: u8 = 0;
    if (cpu.flags.unused != 0) {
        ps |= @intFromEnum(Cpu.FlagBit.unused);
    }
    if (cpu.flags.c != 0) {
        ps |= @intFromEnum(Cpu.FlagBit.carry);
    }
    if (cpu.flags.z != 0) {
        ps |= @intFromEnum(Cpu.FlagBit.zero);
    }
    if (cpu.flags.i != 0) {
        ps |= @intFromEnum(Cpu.FlagBit.intDisable);
    }
    if (cpu.flags.d != 0) {
        ps |= @intFromEnum(Cpu.FlagBit.decimal);
    }
    if (cpu.flags.b != 0) {
        ps |= @intFromEnum(Cpu.FlagBit.brk);
    }
    if (cpu.flags.v != 0) {
        ps |= @intFromEnum(Cpu.FlagBit.overflow);
    }
    if (cpu.flags.n != 0) {
        ps |= @intFromEnum(Cpu.FlagBit.negative);
    }
    cpu.status = ps;
}

pub fn psToFlags(cpu: *Cpu) void {
    cpu.flags.unused = @intFromBool((cpu.status & @intFromEnum(
        Cpu.FlagBit.unused,
    )) != 0);
    cpu.flags.c = @intFromBool((cpu.status & @intFromEnum(
        Cpu.FlagBit.carry,
    )) != 0);
    cpu.flags.z = @intFromBool((cpu.status & @intFromEnum(
        Cpu.FlagBit.zero,
    )) != 0);
    cpu.flags.i = @intFromBool((cpu.status & @intFromEnum(
        Cpu.FlagBit.intDisable,
    )) != 0);
    cpu.flags.d = @intFromBool((cpu.status & @intFromEnum(
        Cpu.FlagBit.decimal,
    )) != 0);
    cpu.flags.b = @intFromBool((cpu.status & @intFromEnum(
        Cpu.FlagBit.brk,
    )) != 0);
    cpu.flags.v = @intFromBool((cpu.status & @intFromEnum(
        Cpu.FlagBit.overflow,
    )) != 0);
    cpu.flags.n = @intFromBool((cpu.status & @intFromEnum(
        Cpu.FlagBit.negative,
    )) != 0);
}

fn fetchByte(cpu: *Cpu) i8 {
    return @as(i8, @bitCast(fetchUByte(cpu)));
}

fn fetchUByte(cpu: *Cpu) u8 {
    const data: u8 = cpu.mem.data[cpu.pc];
    cpu.pc +%= 1;
    cpu.cycles_executed +%= 1;
    return data;
}

fn fetchWord(cpu: *Cpu) u16 {
    var data: u16 = cpu.mem.data[cpu.pc];
    cpu.pc +%= 1;
    data |= @as(u16, cpu.mem.data[cpu.pc]) << 8;
    cpu.pc +%= 1;
    cpu.cycles_executed +%= 2;
    return data;
}

fn spToAddr(cpu: *Cpu) u16 {
    return @as(u16, cpu.sp) | 0x100;
}

fn pushB(cpu: *Cpu, val: u8) void {
    const sp_word: u16 = spToAddr(cpu);
    cpu.mem.data[sp_word] = val;
    cpu.cycles_executed +%= 1;
    cpu.sp -%= 1;
    cpu.cycles_executed +%= 1;
}

fn popB(cpu: *Cpu) u8 {
    cpu.sp +%= 1;
    cpu.cycles_executed +%= 1;
    const sp_word: u16 = spToAddr(cpu);
    const val: u8 = cpu.mem.data[sp_word];
    cpu.cycles_executed +%= 1;
    return val;
}

pub fn pushW(cpu: *Cpu, val: u16) void {
    cpu.writeByte(@truncate(val >> 8), spToAddr(cpu)); // High byte at current sp
    cpu.sp -%= 1;
    cpu.writeByte(@truncate(val & 0xff), spToAddr(cpu)); // Low byte at sp - 1
    cpu.sp -%= 1;
}

pub fn popW(cpu: *Cpu) u16 {
    cpu.sp +%= 1;
    const low = cpu.readByte(spToAddr(cpu)); // Low byte first
    cpu.sp +%= 1;
    const high = cpu.readByte(spToAddr(cpu)); // High byte second
    return (@as(u16, high) << 8) | low;
}

pub fn updateFlags(cpu: *Cpu, reg: u8) void {
    cpu.flags.z = 0;
    if (reg == 0) cpu.flags.z = 1;
    cpu.flags.n = 0;
    if ((reg & @intFromEnum(Cpu.FlagBit.negative)) != 0) cpu.flags.n = 1;
    cpu.flagsToPS();
}

fn loadReg(cpu: *Cpu, addr: u16, reg: *u8) void {
    reg.* = cpu.readByte(addr);
    cpu.updateFlags(reg.*);
}

pub fn bitAnd(cpu: *Cpu, addr: u16) void {
    cpu.a &= cpu.readByte(addr);
    cpu.updateFlags(cpu.a);
}

pub fn bitOra(cpu: *Cpu, addr: u16) void {
    cpu.a |= cpu.readByte(addr);
    cpu.updateFlags(cpu.a);
}

pub fn bitXor(cpu: *Cpu, addr: u16) void {
    cpu.a ^= cpu.readByte(addr);
    cpu.updateFlags(cpu.a);
}

pub fn branch(cpu: *Cpu, t1: u8, t2: u8) void {
    const offs: i8 = fetchByte(cpu);
    if (t1 == t2) {
        const old_pc = @as(u32, cpu.pc);
        var s_pc = @as(i32, cpu.pc);
        s_pc += @as(i32, offs);
        const u_pc = @as(u32, @bitCast(s_pc));
        cpu.pc = @as(u16, @truncate(u_pc));
        cpu.cycles_executed +%= 1;
        if ((u_pc >> 8) != (old_pc >> 8)) {
            cpu.cycles_executed +%= 1;
        }
    }
}

pub fn adc(cpu: *Cpu, op: u8) void {
    if (cpu.flags.d == 1) {
        // Decimal mode (BCD)
        const sum: u16 = @as(u16, cpu.a) + @as(u16, op) +
            @as(u16, cpu.flags.c);
        var al: u8 = (cpu.a & 0x0F) + (op & 0x0F) + @as(u8, cpu.flags.c);
        if (al > 0x09) al += 0x06;
        var ah: u8 = (cpu.a >> 4) + (op >> 4) +
            @as(u8, @intFromBool(al > 0x0F));
        if (ah > 0x09) ah += 0x06;
        cpu.a = ((ah & 0x0F) << 4) | (al & 0x0F);
        cpu.flags.c = @intFromBool(sum > 0x99);
        cpu.flags.z = @intFromBool(cpu.a == 0);
        cpu.flags.n = @intFromBool((cpu.a & 0x80) != 0);
        cpu.flags.v = @intFromBool(((cpu.a ^ op) & 0x80) == 0 and
            ((cpu.a ^ sum) & 0x80) != 0);
    } else {
        const old_a: u8 = cpu.a;
        const m: u8 = op;
        const sum: u16 = @as(u16, old_a) + @as(u16, m) + @as(u16, cpu.flags.c);
        cpu.a = @truncate(sum);
        cpu.flags.c = @intFromBool(sum > 0xFF);
        const signs_match = ((old_a ^ m) & 0x80) == 0;
        const sign_flipped = ((old_a ^ cpu.a) & 0x80) != 0;
        cpu.flags.v =
            @intFromBool(signs_match and sign_flipped and (sum <= 0xFF));
    }
    cpu.updateFlags(cpu.a);
}

pub fn sbc(cpu: *Cpu, op: u8) void {
    if (cpu.flags.d == 1) {
        // Decimal mode (BCD)
        var al: i16 = @as(i16, cpu.a & 0x0F) - @as(i16, op & 0x0F) -
            @as(i16, 1 - cpu.flags.c);
        if (al < 0) al -= 0x06;
        var ah: i16 = @as(i16, cpu.a >> 4) - @as(i16, op >> 4) -
            @as(i16, @intFromBool(al < 0));
        if (ah < 0) ah -= 0x06;
        const al_u8: u8 = @as(u8, @truncate(@as(u16, @bitCast(al & 0x0F))));
        const ah_u8: u8 = @as(u8, @truncate(@as(u16, @bitCast(ah & 0x0F))));
        cpu.a = (ah_u8 << 4) | al_u8;
        const result: i16 = @as(i16, cpu.a) - @as(i16, op) -
            @as(i16, 1 - cpu.flags.c);
        cpu.flags.c = @intFromBool(result >= 0);
        cpu.flags.z = @intFromBool(cpu.a == 0);
        cpu.flags.n = @intFromBool((cpu.a & 0x80) != 0);
        cpu.flags.v = @intFromBool(((cpu.a ^ op) & 0x80) != 0 and
            ((cpu.a ^ result) & 0x80) != 0);
    } else {
        const old_a: u8 = cpu.a;
        const m: u8 = op;
        const result: i16 = @as(i16, old_a) - @as(i16, m) -
            @as(i16, 1 - cpu.flags.c);
        cpu.a = @intCast(result & 0xFF); // Fixed type error!
        cpu.flags.c = @intFromBool(result >= 0);
        cpu.flags.v = @intFromBool(((old_a ^ m) & (old_a ^ cpu.a) & 0x80) != 0);
    }

    cpu.updateFlags(cpu.a);
}

pub fn asl(cpu: *Cpu, op: u8) u8 {
    cpu.flags.c = @as(u1, @intFromBool(op &
        @intFromEnum(Cpu.FlagBit.negative) > 0));
    const res: u8 = op << 1;
    cpu.updateFlags(res);
    cpu.cycles_executed +%= 1;
    return res;
}

pub fn lsr(cpu: *Cpu, op: u8) u8 {
    cpu.flags.c = @as(u1, @intFromBool(op &
        @intFromEnum(Cpu.FlagBit.carry) > 0));
    const res: u8 = op >> 1;
    cpu.updateFlags(res);
    cpu.cycles_executed +%= 1;
    return res;
}

pub fn rol(cpu: *Cpu, op: u8) u8 {
    const old_carry: u8 = cpu.flags.c;
    cpu.flags.c = @intFromBool((op &
        @intFromEnum(Cpu.FlagBit.negative)) != 0); // Store bit 7 in carry flag
    const res: u8 = (op << 1) | old_carry; // Rotate left, inserting old carry
    cpu.updateFlags(res);
    cpu.cycles_executed +%= 1;
    return res;
}

pub fn ror(cpu: *Cpu, op: u8) u8 {
    const old_carry: u8 = cpu.flags.c; // Store the old carry bit before shifting
    cpu.flags.c = @intFromBool((op &
        @intFromEnum(Cpu.FlagBit.carry)) != 0); // Store bit 0 in carry flag
    const res: u8 = (op >> 1) | (old_carry << 7); // Rotate right, inserting old carry
    cpu.updateFlags(res);
    cpu.cycles_executed +%= 1;
    return res;
}

fn pushPs(cpu: *Cpu) void {
    cpu.flagsToPS();
    const ps_stack: u8 = cpu.status |
        @intFromEnum(Cpu.FlagBit.brk) | @intFromEnum(Cpu.FlagBit.unused);
    cpu.pushB(@as(u8, @bitCast(ps_stack)));
}

fn popPs(cpu: *Cpu) void {
    cpu.status = popB(cpu);
    psToFlags(cpu);
    cpu.flags.b = 0;
    cpu.flags.unused = 0;
}

fn addrZp(cpu: *Cpu) u16 {
    const zp_addr = fetchUByte(cpu);
    return @as(u16, zp_addr);
}

fn addrZpX(cpu: *Cpu) u16 {
    var zp_addr: u8 = fetchUByte(cpu);
    zp_addr +%= cpu.x;
    cpu.cycles_executed +%= 1;
    return @as(u16, zp_addr);
}

fn addrZpY(cpu: *Cpu) u16 {
    var zp_addr: u8 = fetchUByte(cpu);
    zp_addr +%= cpu.y;
    cpu.cycles_executed +%= 1;
    return @as(u16, zp_addr);
}

fn addrAbs(cpu: *Cpu) u16 {
    const abs_addr: u16 = fetchWord(cpu);
    return abs_addr;
}

fn addrAbsX(cpu: *Cpu) u16 {
    const abs_addr: u16 = fetchWord(cpu);
    const abs_addr_x: u16 = abs_addr +% cpu.x;
    const pg_boundary: u16 = (abs_addr ^ abs_addr_x) >> 8;
    if (pg_boundary != 0) {
        cpu.cycles_executed +%= 1;
    }
    return abs_addr_x;
}

fn addrAbsX5(cpu: *Cpu) u16 {
    const abs_addr: u16 = fetchWord(cpu);
    const abs_addr_x: u16 = abs_addr +% cpu.x;
    const pg_boundary: u16 = (abs_addr ^ abs_addr_x) >> 8;
    if (pg_boundary != 0) {
        cpu.cycles_executed +%= 1;
    }
    return abs_addr_x;
}

fn addrAbsY(cpu: *Cpu) u16 {
    const abs_addr: u16 = fetchWord(cpu);
    const abs_addr_y: u16 = abs_addr +% cpu.y; // Wrapping addition
    const pg_boundary: u16 = (abs_addr ^ abs_addr_y) >> 8;
    if (pg_boundary != 0) {
        cpu.cycles_executed +%= 1;
    }
    return abs_addr_y;
}

fn addrIndX(cpu: *Cpu) u16 {
    var zp_addr: u8 = fetchUByte(cpu);
    zp_addr +%= cpu.x;
    cpu.cycles_executed +%= 1;
    return cpu.readWordZP(zp_addr);
}

fn addrIndY(cpu: *Cpu) u16 {
    const zp_addr: u8 = fetchUByte(cpu);
    const eff_addr: u16 = cpu.readWordZP(zp_addr); // Use zero-page version
    const eff_addr_y: u16 = eff_addr +% cpu.y;
    const pg_boundary: u16 = (eff_addr ^ eff_addr_y) >> 8;
    if (pg_boundary != 0) {
        cpu.cycles_executed +%= 1;
    }
    return eff_addr_y;
}

fn addrAbsY5(cpu: *Cpu) u16 {
    const abs_addr: u16 = fetchWord(cpu);
    const abs_addr_y: u16 = abs_addr +% cpu.y;
    const pg_boundary: u16 = (abs_addr ^ abs_addr_y) >> 8;
    if (pg_boundary != 0) {
        cpu.cycles_executed +%= 1;
    }
    return abs_addr_y;
}

fn addrIndY6(cpu: *Cpu) u16 {
    const zp_addr: u8 = fetchUByte(cpu);
    const eff_addr: u16 = cpu.readWordZP(zp_addr);
    const eff_addr_y: u16 = eff_addr +% cpu.y;
    const pg_boundary: u16 = (eff_addr ^ eff_addr_y) >> 8;
    if (pg_boundary != 0) {
        cpu.cycles_executed +%= 1;
    }
    return eff_addr_y;
}

fn cmpReg(cpu: *Cpu, op: u8, reg_val: u8) void {
    const tmp: i8 = @as(i8, @bitCast(reg_val -% op));
    cpu.flags.n = @intFromBool((@as(u8, @bitCast(tmp)) &
        @intFromEnum(Cpu.FlagBit.negative)) != 0);
    cpu.flags.z = @intFromBool(reg_val == op);
    cpu.flags.c = @intFromBool(reg_val >= op);
    cpu.flagsToPS();
}

pub fn runStep(cpu: *Cpu) u8 {
    cpu.sid.reg_written = false;
    cpu.sid.reg_changed = false;
    cpu.sid.last_change = null;
    cpu.vic.vsync_happened = false;
    cpu.vic.hsync_happened = false;
    cpu.vic.badline_happened = false;
    cpu.vic.rasterline_changed = false;

    // dbg output
    if (cpu.dbg_enabled) {
        cpu.opcode_last = cpu.mem.data[cpu.pc];
        cpu.printStatus();
    }

    const cycles_now: u32 = cpu.cycles_executed;
    const opcode: u8 = fetchUByte(cpu);
    cpu.opcode_last = opcode;

    switch (opcode) {
        Asm.and_imm.opcode => {
            cpu.a &= fetchUByte(cpu);
            cpu.updateFlags(cpu.a);
        },
        Asm.ora_imm.opcode => {
            cpu.a |= fetchUByte(cpu);
            cpu.updateFlags(cpu.a);
        },
        Asm.xor_imm.opcode => {
            cpu.a ^= fetchUByte(cpu);
            cpu.updateFlags(cpu.a);
        },
        Asm.and_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            cpu.bitAnd(addr);
        },
        Asm.ora_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            cpu.bitOra(addr);
        },
        Asm.xor_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            cpu.bitXor(addr);
        },
        Asm.and_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            cpu.bitAnd(addr);
        },
        Asm.ora_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            cpu.bitOra(addr);
        },
        Asm.xor_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            cpu.bitXor(addr);
        },
        Asm.and_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            cpu.bitAnd(addr);
        },
        Asm.ora_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            cpu.bitOra(addr);
        },
        Asm.xor_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            cpu.bitXor(addr);
        },
        Asm.and_absx.opcode => {
            const addr: u16 = addrAbsX(cpu);
            cpu.bitAnd(addr);
        },
        Asm.ora_absx.opcode => {
            const addr: u16 = addrAbsX(cpu);
            cpu.bitOra(addr);
        },
        Asm.xor_absx.opcode => {
            const addr: u16 = addrAbsX(cpu);
            cpu.bitXor(addr);
        },
        Asm.and_absy.opcode => {
            const addr: u16 = addrAbsY(cpu);
            cpu.bitAnd(addr);
        },
        Asm.ora_absy.opcode => {
            const addr: u16 = addrAbsY(cpu);
            cpu.bitOra(addr);
        },
        Asm.xor_absy.opcode => {
            const addr: u16 = addrAbsY(cpu);
            cpu.bitXor(addr);
        },
        Asm.and_indx.opcode => {
            const addr: u16 = addrIndX(cpu);
            cpu.bitAnd(addr);
        },
        Asm.ora_indx.opcode => {
            const addr: u16 = addrIndX(cpu);
            cpu.bitOra(addr);
        },
        Asm.xor_indx.opcode => {
            const addr: u16 = addrIndX(cpu);
            cpu.bitXor(addr);
        },
        Asm.and_indy.opcode => {
            const addr: u16 = addrIndY(cpu);
            cpu.bitAnd(addr);
        },
        Asm.ora_indy.opcode => {
            const addr: u16 = addrIndY(cpu);
            cpu.bitOra(addr);
        },
        Asm.xor_indy.opcode => {
            const addr: u16 = addrIndY(cpu);
            cpu.bitXor(addr);
        },
        Asm.bit_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            const val: u8 = cpu.readByte(addr);
            cpu.flags.z = @intFromBool(!((cpu.a & val) != 0));
            cpu.flags.n = @intFromBool((val & 128) != 0);
            cpu.flags.v = @intFromBool((val & 64) != 0);
        },
        Asm.bit_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            const val: u8 = cpu.readByte(addr);
            cpu.flags.z = @intFromBool(!((cpu.a & val) != 0));
            cpu.flags.n = @intFromBool((val & 128) != 0);
            cpu.flags.v = @intFromBool((val & 64) != 0);
        },
        Asm.lda_imm.opcode => {
            cpu.a = fetchUByte(cpu);
            cpu.updateFlags(cpu.a);
        },
        Asm.ldx_imm.opcode => {
            cpu.x = fetchUByte(cpu);
            cpu.updateFlags(cpu.x);
        },
        Asm.ldy_imm.opcode => {
            cpu.y = fetchUByte(cpu);
            cpu.updateFlags(cpu.y);
        },
        Asm.lda_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            cpu.loadReg(addr, &cpu.a);
        },
        Asm.ldx_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            cpu.loadReg(addr, &cpu.x);
        },
        Asm.ldx_zpy.opcode => {
            const addr: u16 = addrZpY(cpu);
            cpu.loadReg(addr, &cpu.x);
        },
        Asm.ldy_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            cpu.loadReg(addr, &cpu.y);
        },
        Asm.lda_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            cpu.loadReg(addr, &cpu.a);
        },
        Asm.ldy_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            cpu.loadReg(addr, &cpu.y);
        },
        Asm.lda_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            cpu.loadReg(addr, &cpu.a);
        },
        Asm.ldx_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            cpu.loadReg(addr, &cpu.x);
        },
        Asm.ldy_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            cpu.loadReg(addr, &cpu.y);
        },
        Asm.lda_absx.opcode => {
            const addr: u16 = addrAbsX(cpu);
            cpu.loadReg(addr, &cpu.a);
        },
        Asm.ldy_absx.opcode => {
            const addr: u16 = addrAbsX(cpu);
            cpu.loadReg(addr, &cpu.y);
        },
        Asm.lda_absy.opcode => {
            const addr: u16 = addrAbsY(cpu);
            cpu.loadReg(addr, &cpu.a);
        },
        Asm.ldx_absy.opcode => {
            const addr: u16 = addrAbsY(cpu);
            cpu.loadReg(addr, &cpu.x);
        },
        Asm.lda_indx.opcode => {
            const addr: u16 = addrIndX(cpu);
            cpu.loadReg(addr, &cpu.a);
        },
        Asm.sta_indx.opcode => {
            const addr: u16 = addrIndX(cpu);
            cpu.writeByte(cpu.a, addr);
        },
        Asm.lda_indy.opcode => {
            const addr: u16 = addrIndY(cpu);
            cpu.loadReg(addr, &cpu.a);
        },
        Asm.sta_indy.opcode => {
            const addr: u16 = addrIndY6(cpu);
            cpu.writeByte(cpu.a, addr);
        },
        Asm.sta_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            cpu.writeByte(cpu.a, addr);
        },
        Asm.stx_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            cpu.writeByte(cpu.x, addr);
        },
        Asm.stx_zpy.opcode => {
            const addr: u16 = addrZpY(cpu);
            cpu.writeByte(cpu.x, addr);
        },
        Asm.sty_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            cpu.writeByte(cpu.y, addr);
        },
        Asm.sta_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            cpu.writeByte(cpu.a, addr);
        },
        Asm.stx_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            cpu.writeByte(cpu.x, addr);
        },
        Asm.sty_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            cpu.writeByte(cpu.y, addr);
        },
        Asm.sta_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            cpu.writeByte(cpu.a, addr);
        },
        Asm.sty_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            cpu.writeByte(cpu.y, addr);
        },
        Asm.sta_absx.opcode => {
            const addr: u16 = addrAbsX5(cpu);
            cpu.writeByte(cpu.a, addr);
        },
        Asm.sta_absy.opcode => {
            const addr: u16 = addrAbsY5(cpu);
            cpu.writeByte(cpu.a, addr);
        },

        Asm.jsr.opcode => {
            const jsr_addr: u16 = fetchWord(cpu);
            const ret_addr = cpu.pc - 1;
            cpu.pushW(ret_addr);
            cpu.pc = jsr_addr;
            cpu.cycles_executed +%= 1; // Matches 6 cycles with fetch and push
            if (cpu.dbg_enabled) {
                stdout.print("[cpu] JSR {X:0>4}, return to {X:0>4}\n", .{
                    jsr_addr,
                    ret_addr,
                }) catch {};
            }
        },

        Asm.rts.opcode => {
            if (cpu.sp == 0xFF) {
                if (cpu.dbg_enabled) {
                    stdout.print("[cpu] RTS EXIT!\n", .{}) catch {};
                }
                cpu.cycles_last_step =
                    @as(u8, @truncate(cpu.cycles_executed -% cycles_now));
                return 0;
            }

            const ret_addr: u16 = popW(cpu);
            cpu.pc = ret_addr + 1;
            cpu.cycles_executed +%= 2;
            if (cpu.dbg_enabled) {
                stdout.print("[cpu] RTS to {X:0>4}\n", .{
                    ret_addr + 1,
                }) catch {};
            }
        },

        Asm.jmp_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            cpu.pc = addr;
            if (cpu.dbg_enabled) {
                stdout.print("[cpu] JMP {X:0>4}\n", .{addr}) catch {};
            }
        },

        Asm.jmp_ind.opcode => {
            const addr: u16 = addrAbs(cpu);
            const lo: u8 = cpu.readByte(addr);
            const hi_addr: u16 = (addr & 0xFF00) | ((addr + 1) & 0x00FF); // Wrap to $xx00
            const hi: u8 = cpu.readByte(hi_addr);
            cpu.pc = @as(u16, lo) | (@as(u16, hi) << 8);
        },

        Asm.tsx.opcode => {
            cpu.x = cpu.sp;
            cpu.cycles_executed +%= 1;
            cpu.updateFlags(cpu.x);
        },
        Asm.txs.opcode => {
            cpu.sp = cpu.x;
            cpu.cycles_executed +%= 1;
        },
        Asm.pha.opcode => {
            cpu.pushB(cpu.a);
        },
        Asm.pla.opcode => {
            cpu.a = popB(cpu);
            cpu.updateFlags(cpu.a);
            cpu.cycles_executed +%= 1;
        },
        Asm.php.opcode => {
            pushPs(cpu);
        },
        Asm.plp.opcode => {
            popPs(cpu);
            cpu.cycles_executed +%= 1;
        },
        Asm.tax.opcode => {
            cpu.x = cpu.a;
            cpu.cycles_executed +%= 1;
            cpu.updateFlags(cpu.x);
        },
        Asm.tay.opcode => {
            cpu.y = cpu.a;
            cpu.cycles_executed +%= 1;
            cpu.updateFlags(cpu.y);
        },
        Asm.txa.opcode => {
            cpu.a = cpu.x;
            cpu.cycles_executed +%= 1;
            cpu.updateFlags(cpu.a);
        },
        Asm.tya.opcode => {
            cpu.a = cpu.y;
            cpu.cycles_executed +%= 1;
            cpu.updateFlags(cpu.a);
        },
        Asm.inx.opcode => {
            cpu.x +%= 1;
            cpu.cycles_executed +%= 1;
            cpu.updateFlags(cpu.x);
        },
        Asm.iny.opcode => {
            cpu.y +%= 1;
            cpu.cycles_executed +%= 1;
            cpu.updateFlags(cpu.y);
        },
        Asm.dex.opcode => {
            cpu.x -%= 1;
            cpu.cycles_executed +%= 1;
            cpu.updateFlags(cpu.x);
        },
        Asm.dey.opcode => {
            cpu.y -%= 1;
            cpu.cycles_executed +%= 1;
            cpu.updateFlags(cpu.y);
        },
        Asm.dec_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            var val: u8 = cpu.readByte(addr);
            val -%= 1;
            cpu.cycles_executed +%= 1;
            cpu.writeByte(val, addr);
            cpu.updateFlags(val);
        },
        Asm.dec_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            var val: u8 = cpu.readByte(addr);
            val -%= 1;
            cpu.cycles_executed +%= 1;
            cpu.writeByte(val, addr);
            cpu.updateFlags(val);
        },
        Asm.dec_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            var val: u8 = cpu.readByte(addr);
            val -%= 1;
            cpu.cycles_executed +%= 1;
            cpu.writeByte(val, addr);
            cpu.updateFlags(val);
        },
        Asm.dec_absx.opcode => {
            const addr: u16 = addrAbsX5(cpu);
            var val: u8 = cpu.readByte(addr);
            val -%= 1;
            cpu.cycles_executed +%= 1;
            cpu.writeByte(val, addr);
            cpu.updateFlags(val);
        },
        Asm.inc_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            var val: u8 = cpu.readByte(addr);
            val +%= 1;
            cpu.cycles_executed +%= 1;
            cpu.writeByte(val, addr);
            cpu.updateFlags(val);
        },
        Asm.inc_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            var val: u8 = cpu.readByte(addr);
            val +%= 1;
            cpu.cycles_executed +%= 1;
            cpu.writeByte(val, addr);
            cpu.updateFlags(val);
        },
        Asm.inc_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            var val: u8 = cpu.readByte(addr);
            val +%= 1;
            cpu.cycles_executed +%= 1;
            cpu.writeByte(val, addr);
            cpu.updateFlags(val);
        },
        Asm.inc_absx.opcode => {
            const addr: u16 = addrAbsX5(cpu);
            var val: u8 = cpu.readByte(addr);
            val +%= 1;
            cpu.cycles_executed +%= 1;
            cpu.writeByte(val, addr);
            cpu.updateFlags(val);
        },
        Asm.beq.opcode => {
            cpu.branch(@as(u8, cpu.flags.z), 1);
        },
        Asm.bne.opcode => {
            cpu.branch(@as(u8, cpu.flags.z), 0);
        },
        Asm.bcs.opcode => {
            cpu.branch(@as(u8, cpu.flags.c), 1);
        },
        Asm.bcc.opcode => {
            cpu.branch(@as(u8, cpu.flags.c), 0);
        },
        Asm.bmi.opcode => {
            cpu.branch(@as(u8, cpu.flags.n), 1);
        },
        Asm.bpl.opcode => {
            cpu.branch(@as(u8, cpu.flags.n), 0);
        },
        Asm.bvc.opcode => {
            cpu.branch(@as(u8, cpu.flags.v), 0);
        },
        Asm.bvs.opcode => {
            cpu.branch(@as(u8, cpu.flags.v), 1);
        },
        Asm.clc.opcode => {
            cpu.flags.c = 0;
            cpu.cycles_executed +%= 1;
            cpu.flagsToPS();
        },
        Asm.sec.opcode => {
            cpu.flags.c = 1;
            cpu.cycles_executed +%= 1;
            cpu.flagsToPS();
        },
        Asm.cld.opcode => {
            cpu.flags.d = 0;
            cpu.cycles_executed +%= 1;
            cpu.flagsToPS();
        },
        Asm.sed.opcode => {
            cpu.flags.d = 1;
            cpu.cycles_executed +%= 1;
            cpu.flagsToPS();
        },
        Asm.cli.opcode => {
            cpu.flags.i = 0;
            cpu.cycles_executed +%= 1;
            cpu.flagsToPS();
        },
        Asm.sei.opcode => {
            cpu.flags.i = 1;
            cpu.cycles_executed +%= 1;
            cpu.flagsToPS();
        },
        Asm.clv.opcode => {
            cpu.flags.v = 0;
            cpu.cycles_executed +%= 1;
            cpu.flagsToPS();
        },
        Asm.nop.opcode => {
            cpu.cycles_executed +%= 1;
        },
        Asm.adc_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.adc(op);
        },
        Asm.adc_absx.opcode => {
            const addr: u16 = addrAbsX(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.adc(op);
        },
        Asm.adc_absy.opcode => {
            const addr: u16 = addrAbsY(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.adc(op);
        },
        Asm.adc_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.adc(op);
        },
        Asm.adc_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.adc(op);
        },
        Asm.adc_indx.opcode => {
            const addr: u16 = addrIndX(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.adc(op);
        },
        Asm.adc_indy.opcode => {
            const addr: u16 = addrIndY(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.adc(op);
        },
        Asm.adc_imm.opcode => {
            const op: u8 = fetchUByte(cpu);
            cpu.adc(op);
        },
        Asm.sbc_imm.opcode => {
            const op: u8 = fetchUByte(cpu);
            cpu.sbc(op);
        },
        Asm.sbc_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.sbc(op);
        },
        Asm.sbc_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.sbc(op);
        },
        Asm.sbc_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.sbc(op);
        },
        Asm.sbc_absx.opcode => {
            const addr: u16 = addrAbsX(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.sbc(op);
        },
        Asm.sbc_absy.opcode => {
            const addr: u16 = addrAbsY(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.sbc(op);
        },
        Asm.sbc_indx.opcode => {
            const addr: u16 = addrIndX(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.sbc(op);
        },
        Asm.sbc_indy.opcode => {
            const addr: u16 = addrIndY(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.sbc(op);
        },
        Asm.cpx_imm.opcode => {
            const op: u8 = fetchUByte(cpu);
            cpu.cmpReg(op, cpu.x);
        },
        Asm.cpy_imm.opcode => {
            const op: u8 = fetchUByte(cpu);
            cpu.cmpReg(op, cpu.y);
        },
        Asm.cpx_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.cmpReg(op, cpu.x);
        },
        Asm.cpy_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.cmpReg(op, cpu.y);
        },
        Asm.cpx_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.cmpReg(op, cpu.x);
        },
        Asm.cpy_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.cmpReg(op, cpu.y);
        },
        Asm.cmp_imm.opcode => {
            const op: u8 = fetchUByte(cpu);
            cpu.cmpReg(op, cpu.a);
        },
        Asm.cmp_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.cmpReg(op, cpu.a);
        },
        Asm.cmp_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.cmpReg(op, cpu.a);
        },
        Asm.cmp_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.cmpReg(op, cpu.a);
        },
        Asm.cmp_absx.opcode => {
            const addr: u16 = addrAbsX(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.cmpReg(op, cpu.a);
        },
        Asm.cmp_absy.opcode => {
            const addr: u16 = addrAbsY(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.cmpReg(op, cpu.a);
        },
        Asm.cmp_indx.opcode => {
            const addr: u16 = addrIndX(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.cmpReg(op, cpu.a);
        },
        Asm.cmp_indy.opcode => {
            const addr: u16 = addrIndY(cpu);
            const op: u8 = cpu.readByte(addr);
            cpu.cmpReg(op, cpu.a);
        },
        Asm.asl_a.opcode => {
            cpu.a = cpu.asl(cpu.a);
        },
        Asm.asl_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.asl(op);
            cpu.writeByte(res, addr);
        },
        Asm.asl_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.asl(op);
            cpu.writeByte(res, addr);
        },
        Asm.asl_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.asl(op);
            cpu.writeByte(res, addr);
        },
        Asm.asl_absx.opcode => {
            const addr: u16 = addrAbsX5(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.asl(op);
            cpu.writeByte(res, addr);
        },
        Asm.lsr_a.opcode => {
            cpu.a = cpu.lsr(cpu.a);
        },
        Asm.lsr_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.lsr(op);
            cpu.writeByte(res, addr);
        },
        Asm.lsr_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.lsr(op);
            cpu.writeByte(res, addr);
        },
        Asm.lsr_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.lsr(op);
            cpu.writeByte(res, addr);
        },
        Asm.lsr_absx.opcode => {
            const addr: u16 = addrAbsX5(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.lsr(op);
            cpu.writeByte(res, addr);
        },
        Asm.rol_a.opcode => {
            cpu.a = cpu.rol(cpu.a);
        },
        Asm.rol_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.rol(op);
            cpu.writeByte(res, addr);
        },
        Asm.rol_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.rol(op);
            cpu.writeByte(res, addr);
        },
        Asm.rol_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.rol(op);
            cpu.writeByte(res, addr);
        },
        Asm.rol_absx.opcode => {
            const addr: u16 = addrAbsX5(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.rol(op);
            cpu.writeByte(res, addr);
        },
        Asm.ror_a.opcode => {
            cpu.a = cpu.ror(cpu.a);
        },
        Asm.ror_zp.opcode => {
            const addr: u16 = addrZp(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.ror(op);
            cpu.writeByte(res, addr);
        },
        Asm.ror_zpx.opcode => {
            const addr: u16 = addrZpX(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.ror(op);
            cpu.writeByte(res, addr);
        },
        Asm.ror_abs.opcode => {
            const addr: u16 = addrAbs(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.ror(op);
            cpu.writeByte(res, addr);
        },
        Asm.ror_absx.opcode => {
            const addr: u16 = addrAbsX5(cpu);
            const op: u8 = cpu.readByte(addr);
            const res: u8 = cpu.ror(op);
            cpu.writeByte(res, addr);
        },
        Asm.brk.opcode => {
            cpu.pushW(cpu.pc + 1);
            pushPs(cpu);
            cpu.pc = cpu.readWord(65534);
            cpu.flags.b = 1;
            cpu.flags.i = 1;
            return 0;
        },
        Asm.rti.opcode => {
            popPs(cpu);
            cpu.pc = popW(cpu);
        },
        else => return 0,
    }
    cpu.cycles_last_step =
        @as(u8, @truncate(cpu.cycles_executed -% cycles_now));

    const vic_cycles = cpu.vic.emulate(cpu.cycles_last_step);
    cpu.cycles_last_step += vic_cycles;
    cpu.cycles_executed += vic_cycles;

    // dbg output vic, sid

    if (cpu.vic.dbg_enabled) {
        cpu.vic.printStatus();
    }

    // return from interrupt vector
    if ((cpu.mem.data[0x01] & 0x07) != 0x5 and
        ((cpu.pc == 0xea31) or (cpu.pc == 0xea81)))
    {
        stdout.print("[cpu] RTI\n", .{}) catch {};

        return 0;
    }

    return cpu.cycles_last_step;
}
