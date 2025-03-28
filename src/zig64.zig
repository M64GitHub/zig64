const std = @import("std");
const stdout = std.io.getStdOut().writer();

const C64 = @This();

cpu: Cpu,
mem: Ram64k,
vic: Vic,
sid: Sid,
resid: ?*opaque {}, // optional resid integration  TODO: tbd
dbg_enabled: bool,
cpu_dbg_enabled: bool,
sid_dbg_enabled: bool,
vic_dbg_enabled: bool,

pub fn init(
    allocator: std.mem.Allocator,
    vic_model: Vic.Model,
    init_addr: u16,
) !*C64 {
    var c64 = try allocator.create(C64);
    c64.* = C64{
        .cpu = Cpu.init(c64, init_addr),
        .mem = Ram64k.init(),
        .vic = Vic.init(c64, vic_model),
        .sid = Sid.init(c64, Sid.std_base),
        .resid = null,
        .dbg_enabled = false,
        .cpu_dbg_enabled = false,
        .sid_dbg_enabled = false,
        .vic_dbg_enabled = false,
    };

    // default startup value: BASIC ROM, KERNAL ROM, and I/O
    c64.mem.data[0x01] = 0x37;
    return c64;
}

pub fn deinit(c64: *C64, allocator: std.mem.Allocator) void {
    allocator.destroy(c64);
}

pub fn call(c64: *C64, address: u16) void {
    c64.cpu.ext_sid_reg_written = false;
    c64.cpu.pushW(0x0000);
    c64.cpu.pc = address;
    if (c64.dbg_enabled) {
        stdout.print("[c64] calling address: {X:0>4}\n", .{
            address,
        }) catch {};
    }
    while (c64.cpu.runStep() != 0) {}
    c64.cpu.sid_reg_written = c64.cpu.ext_sid_reg_written;
    c64.cpu.sid_reg_changed = c64.cpu.ext_sid_reg_changed;
}

pub fn loadPrg(
    c64: *C64,
    allocator: std.mem.Allocator,
    file_name: []const u8,
    pc_to_loadaddr: bool,
) !u16 {
    var file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    if (c64.dbg_enabled) {
        try stdout.print("[c64] loading file: '{s}'\n", .{
            file_name,
        });
    }
    const stat = try file.stat();
    const file_size = stat.size;

    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    return c64.setPrg(buffer, pc_to_loadaddr);
}

pub fn run(c64: *C64) void {
    while (c64.cpu.runStep() != 0) {}
}

pub fn runFrames(c64: *C64, frame_count: u32) u32 {
    if (frame_count == 0) return;
    var frames_executed: u32 = 0;
    var cycles_max: u32 = 0;
    var cycles: u32 = 0;

    if (c64.vic.model == .pal) cycles_max = Vic.Timing.cyclesVsyncPal;
    if (c64.vic.model == .ntsc) cycles_max = Vic.Timing.cyclesVsyncNtsc;

    while (frames_executed < frame_count) {
        cycles += c64.cpu.runStep();
        if (cycles >= cycles_max) {
            frames_executed += 1;
            cycles = 0;
        }
    }
    c64.cpu.frame_ctr += frames_executed;
    return frames_executed;
}

pub fn setPrg(c64: *C64, program: []const u8, pc_to_loadaddr: bool) !u16 {
    var load_address: u16 = 0;
    if ((program.len != 0) and (program.len > 2)) {
        var offs: u32 = 0;
        const lo: u16 = program[offs];
        offs += 1;
        const hi: u16 = @as(u16, program[offs]) << 8;
        offs += 1;
        load_address = @as(u16, lo) | @as(u16, hi);

        if (c64.dbg_enabled) {
            try stdout.print("[c64] file load address: ${X:0>4}\n", .{
                load_address,
            });
        }

        var i: u16 = load_address;
        while (i < (load_address +% program.len -% 2)) : (i +%= 1) {
            c64.mem.data[i] = program[offs];
            if (c64.dbg_enabled)
                stdout.print("[c64] writing mem: {X:0>4} offs: {X:0>4} data: {X:0>2}\n", .{
                    i,
                    offs,
                    program[offs],
                }) catch {};
            offs += 1;
        }
    }
    if (pc_to_loadaddr) c64.cpu.pc = load_address;
    return load_address;
}

// virtual sid
const Sid = struct {
    base_address: u16,
    registers: [25]u8,
    c64: *C64,

    pub const std_base = 0xD400;

    pub fn init(c64: *C64, base_address: u16) Sid {
        return Sid{
            .base_address = base_address,
            .registers = [_]u8{0} ** 25,
            .c64 = c64,
        };
    }

    pub fn getRegisters(sid: *Sid) [25]u8 {
        return sid.registers;
    }

    pub fn printRegisters(sid: *Sid) void {
        stdout.print("[sid] registers: ", .{}) catch {};
        for (sid.registers) |v| {
            stdout.print("{X:0>2} ", .{v}) catch {};
        }
        stdout.print("\n", .{}) catch {};
    }
};

// virtual vic
pub const Vic = struct {
    model: Model,
    vsync_happened: bool,
    hsync_happened: bool,
    badline_happened: bool,
    rasterline_changed: bool,
    rasterline: u16,
    frame_ctr: usize,
    c64: *C64,

    pub const Model = enum {
        pal,
        ntsc,
    };

    pub const Timing = struct {
        const cyclesVsyncPal = 19656; // 63 cycles x 312 rasterlines
        const cyclesVsyncNtsc = 17030;
        const cyclesRasterlinePal = 63;
        const cyclesRasterlineNtsc = 65;
        const cyclesBadlineStealing = 40; // cycles vic steals cpu on badline
    };

    pub fn init(c64: *C64, vic_model: Model) Vic {
        const vic = Vic{
            .model = vic_model,
            .vsync_happened = true,
            .hsync_happened = true,
            .badline_happened = false,
            .rasterline_changed = false,
            .rasterline = 0,
            .frame_ctr = 0,
            .c64 = c64,
        };

        return vic;
    }

    pub fn emulateD012(vic: *Vic) void {
        vic.rasterline += 1;
        vic.rasterline_changed = true;
        vic.hsync_happened = true;

        vic.c64.mem.data[0xD012] = vic.c64.mem.data[0xD012] +% 1;
        if ((vic.c64.mem.data[0xD012] == 0) or
            (((vic.c64.mem.data[0xD011] & 0x80) != 0) and
                (vic.c64.mem.data[0xD012] >= 0x38)))
        {
            vic.c64.mem.data[0xD011] ^= 0x80;
            vic.c64.mem.data[0xD012] = 0x00;
            vic.rasterline = 0;
            vic.vsync_happened = true;
        }

        // check badline
        if (vic.rasterline % 8 == 3) {
            vic.badline_happened = true;
            vic.c64.cpu.cycles_executed += Timing.cyclesBadlineStealing;
            vic.c64.cpu.cycles_last_step += Timing.cyclesBadlineStealing;
            vic.c64.cpu.cycles_since_hsync += Timing.cyclesBadlineStealing;
            vic.c64.cpu.cycles_since_vsync += Timing.cyclesBadlineStealing;
        }
    }

    pub fn printStatus(vic: *Vic) void {
        stdout.print("[vic] RL: {X:0>4} | VSYNC: {} | HSYNC: {} | BL: {} | RL-CHG: {} | FRM: {d}\n", .{
            vic.rasterline,
            vic.vsync_happened,
            vic.hsync_happened,
            vic.badline_happened,
            vic.rasterline_changed,
            vic.frame_ctr,
        }) catch {};
    }
};

// virtual mem
pub const Ram64k = struct {
    data: [0x10000]u8,

    pub fn init() Ram64k {
        return Ram64k{
            .data = [_]u8{0} ** 65536,
        };
    }

    pub fn clear(self: *Ram64k) void {
        @memset(&self.data, 0);
    }
};

// virtual cpu
pub const Cpu = struct {
    pc: u16,
    sp: u8,
    a: u8,
    x: u8,
    y: u8,
    status: u8,
    flags: CpuFlags,
    opcode_last: u8,
    cycles_executed: u32,
    cycles_since_vsync: u16,
    cycles_since_hsync: u8,
    cycles_last_step: u8,
    sid_reg_changed: bool,
    sid_reg_written: bool,
    ext_sid_reg_written: bool,
    ext_sid_reg_changed: bool,
    c64: *C64,

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

    pub fn init(c64: *C64, pc_start: u16) Cpu {
        return Cpu{
            .pc = pc_start,
            .sp = 0xFD,
            .a = 0,
            .x = 0,
            .y = 0,
            .status = 0x24, // Default status flags (Interrupt disable set)
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
            .sid_reg_changed = false,
            .sid_reg_written = false,
            .ext_sid_reg_written = false,
            .ext_sid_reg_changed = false,
            .cycles_since_vsync = 0,
            .cycles_since_hsync = 0,
            .c64 = c64,
        };
    }

    pub fn reset(cpu: *Cpu) void {
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
    pub fn hardReset(cpu: *Cpu) void {
        cpu.reset();
        cpu.c64.mem.clear();
    }

    pub fn writeMem(cpu: *Cpu, data: []const u8, addr: u16) void {
        var offs: u32 = 0;
        var i: u16 = addr;
        while (offs < data.len) : (i +%= 1) {
            cpu.c64.mem.data[i] = data[offs];
            offs += 1;
        }
    }

    pub fn printStatus(cpu: *Cpu) void {
        var buf: [16]u8 = undefined;

        const disasm = disassembleOpcode(
            &buf,
            cpu.pc,
            cpu.opcode_last,
            cpu.c64.mem.data[cpu.pc +% 1],
            cpu.c64.mem.data[cpu.pc +% 2],
        ) catch "???";

        const insn = opcode2Insn(cpu.opcode_last);
        const insn_size = getInsnSize(insn);

        stdout.print("[cpu] PC: {X:0>4} | DIS: {s} (sz: {d}) | A: {X:0>2} | X: {X:0>2} | Y: {X:0>2} | SP: {X:0>2} | Opc: {X:0>2} | {X:0>2} {X:0>2} | Last Cycl: {d} | Cycl-TT: {d} | ", .{
            cpu.pc,
            disasm,
            insn_size,
            cpu.a,
            cpu.x,
            cpu.y,
            cpu.sp,
            cpu.opcode_last,
            cpu.c64.mem.data[cpu.pc +% 1],
            cpu.c64.mem.data[cpu.pc +% 2],
            cpu.cycles_last_step,
            cpu.cycles_executed,
        }) catch {};
        printFlags(cpu);
        stdout.print("\n", .{}) catch {};
    }

    pub fn printFlags(cpu: *Cpu) void {
        cpu.flagsToPS();
        stdout.print("FL: {b:0>8}", .{cpu.status}) catch {};
    }

    pub fn readByte(cpu: *Cpu, addr: u16) u8 {
        const sid_base = cpu.c64.sid.base_address;
        if ((addr >= sid_base) and (addr <= (sid_base + 25))) {
            const val = cpu.c64.sid.registers[addr - 0xD400];
            if (cpu.c64.sid_dbg_enabled) {
                std.debug.print(
                    "[sid] Read ${X:04} = {X:02}, PC={X:04}\n",
                    .{ addr, val, cpu.pc },
                );
            }
            return val;
        }
        return cpu.c64.mem.data[addr];
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
        const sid_base = cpu.c64.sid.base_address;
        if ((addr >= sid_base) and (addr <= (sid_base + 25))) {
            cpu.sid_reg_written = true;
            cpu.ext_sid_reg_written = true;
            cpu.c64.sid.registers[addr - sid_base] = val;
            if (cpu.c64.sid_dbg_enabled) {
                std.debug.print(
                    "[DEBUG] Write ${X:04} = {X:02}, PC={X:04}\n",
                    .{ addr, val, cpu.pc },
                );
            }
            if (cpu.c64.mem.data[addr] != val) {
                cpu.sid_reg_changed = true;
                cpu.ext_sid_reg_changed = true;
            }
        }
        cpu.c64.mem.data[addr] = val;
        cpu.cycles_executed +%= 1;
    }

    pub fn writeWord(cpu: *Cpu, val: u16, addr: u16) void {
        cpu.c64.mem.data[addr] = @truncate(val & 0xFF);
        cpu.c64.mem.data[addr + 1] = @truncate(val >> 8);
        cpu.cycles_executed +%= 2;
    }

    pub fn sidRegWritten(cpu: *Cpu) bool {
        return cpu.sid_reg_written;
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

    fn psToFlags(cpu: *Cpu) void {
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
        const data: u8 = cpu.c64.mem.data[cpu.pc];
        cpu.pc +%= 1;
        cpu.cycles_executed +%= 1;
        return data;
    }

    fn fetchWord(cpu: *Cpu) u16 {
        var data: u16 = cpu.c64.mem.data[cpu.pc];
        cpu.pc +%= 1;
        data |= @as(u16, cpu.c64.mem.data[cpu.pc]) << 8;
        cpu.pc +%= 1;
        cpu.cycles_executed +%= 2;
        return data;
    }

    fn spToAddr(cpu: *Cpu) u16 {
        return @as(u16, cpu.sp) | 0x100;
    }

    fn pushB(cpu: *Cpu, val: u8) void {
        const sp_word: u16 = spToAddr(cpu);
        cpu.c64.mem.data[sp_word] = val;
        cpu.cycles_executed +%= 1;
        cpu.sp -%= 1;
        cpu.cycles_executed +%= 1;
    }

    fn popB(cpu: *Cpu) u8 {
        cpu.sp +%= 1;
        cpu.cycles_executed +%= 1;
        const sp_word: u16 = spToAddr(cpu);
        const val: u8 = cpu.c64.mem.data[sp_word];
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
            // Binary mode
            const signs_equ: bool = (cpu.a ^ op) &
                @intFromEnum(Cpu.FlagBit.negative) == 0;
            const old_sign: bool = (cpu.a &
                @as(u8, @intFromEnum(Cpu.FlagBit.negative))) != 0;
            const sum: u16 = @as(u16, cpu.a) + @as(u16, op) +
                @as(u16, cpu.flags.c);
            cpu.a = @truncate(sum & 0xFF);
            cpu.flags.c = @intFromBool(sum > 0xFF);
            cpu.flags.z = @intFromBool(cpu.a == 0);
            cpu.flags.n = @intFromBool((cpu.a &
                @intFromEnum(Cpu.FlagBit.negative)) != 0);
            const new_sign: bool = (cpu.a &
                @as(u8, @intFromEnum(Cpu.FlagBit.negative))) != 0;
            cpu.flags.v = @intFromBool(signs_equ and (old_sign != new_sign));
        }
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
            // Binary mode
            const old_sign: bool = (cpu.a & @as(u8, @intFromEnum(
                Cpu.FlagBit.negative,
            ))) != 0;
            const result: i16 = @as(i16, cpu.a) - @as(i16, op) - @as(
                i16,
                1 - cpu.flags.c,
            );
            if (cpu.a > op) cpu.flags.c = 1;
            cpu.a = @as(u8, @truncate(@as(u16, @bitCast(result & 0xFF))));
            const new_sign: bool = (cpu.a & @as(u8, @intFromEnum(
                Cpu.FlagBit.negative,
            ))) != 0;
            cpu.flags.v = @intFromBool(old_sign != new_sign);
            cpu.updateFlags(cpu.a);
        }
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
        flagsToPS(cpu);
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
    }

    pub fn runStep(cpu: *Cpu) u8 {
        cpu.sid_reg_written = false;
        cpu.sid_reg_changed = false;
        cpu.c64.vic.vsync_happened = false;
        cpu.c64.vic.hsync_happened = false;
        cpu.c64.vic.badline_happened = false;
        cpu.c64.vic.rasterline_changed = false;

        // dbg output
        if (cpu.c64.cpu_dbg_enabled) {
            cpu.opcode_last = cpu.c64.mem.data[cpu.pc];
            cpu.printStatus();
        }

        const cycles_now: u32 = cpu.cycles_executed;
        const opcode: u8 = fetchUByte(cpu);
        cpu.opcode_last = opcode;

        switch (opcode) {
            Cpu.Insn.and_imm.value => {
                cpu.a &= fetchUByte(cpu);
                cpu.updateFlags(cpu.a);
            },
            Cpu.Insn.ora_imm.value => {
                cpu.a |= fetchUByte(cpu);
                cpu.updateFlags(cpu.a);
            },
            Cpu.Insn.eor_imm.value => {
                cpu.a ^= fetchUByte(cpu);
                cpu.updateFlags(cpu.a);
            },
            Cpu.Insn.and_zp.value => {
                const addr: u16 = addrZp(cpu);
                cpu.bitAnd(addr);
            },
            Cpu.Insn.ora_zp.value => {
                const addr: u16 = addrZp(cpu);
                cpu.bitOra(addr);
            },
            Cpu.Insn.eor_zp.value => {
                const addr: u16 = addrZp(cpu);
                cpu.bitXor(addr);
            },
            Cpu.Insn.and_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                cpu.bitAnd(addr);
            },
            Cpu.Insn.ora_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                cpu.bitOra(addr);
            },
            Cpu.Insn.eor_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                cpu.bitXor(addr);
            },
            Cpu.Insn.and_abs.value => {
                const addr: u16 = addrAbs(cpu);
                cpu.bitAnd(addr);
            },
            Cpu.Insn.ora_abs.value => {
                const addr: u16 = addrAbs(cpu);
                cpu.bitOra(addr);
            },
            Cpu.Insn.eor_abs.value => {
                const addr: u16 = addrAbs(cpu);
                cpu.bitXor(addr);
            },
            Cpu.Insn.and_absx.value => {
                const addr: u16 = addrAbsX(cpu);
                cpu.bitAnd(addr);
            },
            Cpu.Insn.ora_absx.value => {
                const addr: u16 = addrAbsX(cpu);
                cpu.bitOra(addr);
            },
            Cpu.Insn.eor_absx.value => {
                const addr: u16 = addrAbsX(cpu);
                cpu.bitXor(addr);
            },
            Cpu.Insn.and_absy.value => {
                const addr: u16 = addrAbsY(cpu);
                cpu.bitAnd(addr);
            },
            Cpu.Insn.ora_absy.value => {
                const addr: u16 = addrAbsY(cpu);
                cpu.bitOra(addr);
            },
            Cpu.Insn.eor_absy.value => {
                const addr: u16 = addrAbsY(cpu);
                cpu.bitXor(addr);
            },
            Cpu.Insn.and_indx.value => {
                const addr: u16 = addrIndX(cpu);
                cpu.bitAnd(addr);
            },
            Cpu.Insn.ora_indx.value => {
                const addr: u16 = addrIndX(cpu);
                cpu.bitOra(addr);
            },
            Cpu.Insn.eor_indx.value => {
                const addr: u16 = addrIndX(cpu);
                cpu.bitXor(addr);
            },
            Cpu.Insn.and_indy.value => {
                const addr: u16 = addrIndY(cpu);
                cpu.bitAnd(addr);
            },
            Cpu.Insn.ora_indy.value => {
                const addr: u16 = addrIndY(cpu);
                cpu.bitOra(addr);
            },
            Cpu.Insn.eor_indy.value => {
                const addr: u16 = addrIndY(cpu);
                cpu.bitXor(addr);
            },
            Cpu.Insn.bit_zp.value => {
                const addr: u16 = addrZp(cpu);
                const val: u8 = cpu.readByte(addr);
                cpu.flags.z = @intFromBool(!((cpu.a & val) != 0));
                cpu.flags.n = @intFromBool((val & 128) != 0);
                cpu.flags.v = @intFromBool((val & 64) != 0);
            },
            Cpu.Insn.bit_abs.value => {
                const addr: u16 = addrAbs(cpu);
                const val: u8 = cpu.readByte(addr);
                cpu.flags.z = @intFromBool(!((cpu.a & val) != 0));
                cpu.flags.n = @intFromBool((val & 128) != 0);
                cpu.flags.v = @intFromBool((val & 64) != 0);
            },
            Cpu.Insn.lda_imm.value => {
                cpu.a = fetchUByte(cpu);
                cpu.updateFlags(cpu.a);
            },
            Cpu.Insn.ldx_imm.value => {
                cpu.x = fetchUByte(cpu);
                cpu.updateFlags(cpu.x);
            },
            Cpu.Insn.ldy_imm.value => {
                cpu.y = fetchUByte(cpu);
                cpu.updateFlags(cpu.y);
            },
            Cpu.Insn.lda_zp.value => {
                const addr: u16 = addrZp(cpu);
                cpu.loadReg(addr, &cpu.a);
            },
            Cpu.Insn.ldx_zp.value => {
                const addr: u16 = addrZp(cpu);
                cpu.loadReg(addr, &cpu.x);
            },
            Cpu.Insn.ldx_zpy.value => {
                const addr: u16 = addrZpY(cpu);
                cpu.loadReg(addr, &cpu.x);
            },
            Cpu.Insn.ldy_zp.value => {
                const addr: u16 = addrZp(cpu);
                cpu.loadReg(addr, &cpu.y);
            },
            Cpu.Insn.lda_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                cpu.loadReg(addr, &cpu.a);
            },
            Cpu.Insn.ldy_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                cpu.loadReg(addr, &cpu.y);
            },
            Cpu.Insn.lda_abs.value => {
                const addr: u16 = addrAbs(cpu);
                cpu.loadReg(addr, &cpu.a);
            },
            Cpu.Insn.ldx_abs.value => {
                const addr: u16 = addrAbs(cpu);
                cpu.loadReg(addr, &cpu.x);
            },
            Cpu.Insn.ldy_abs.value => {
                const addr: u16 = addrAbs(cpu);
                cpu.loadReg(addr, &cpu.y);
            },
            Cpu.Insn.lda_absx.value => {
                const addr: u16 = addrAbsX(cpu);
                cpu.loadReg(addr, &cpu.a);
            },
            Cpu.Insn.ldy_absx.value => {
                const addr: u16 = addrAbsX(cpu);
                cpu.loadReg(addr, &cpu.y);
            },
            Cpu.Insn.lda_absy.value => {
                const addr: u16 = addrAbsY(cpu);
                cpu.loadReg(addr, &cpu.a);
            },
            Cpu.Insn.ldx_absy.value => {
                const addr: u16 = addrAbsY(cpu);
                cpu.loadReg(addr, &cpu.x);
            },
            Cpu.Insn.lda_indx.value => {
                const addr: u16 = addrIndX(cpu);
                cpu.loadReg(addr, &cpu.a);
            },
            Cpu.Insn.sta_indx.value => {
                const addr: u16 = addrIndX(cpu);
                cpu.writeByte(cpu.a, addr);
            },
            Cpu.Insn.lda_indy.value => {
                const addr: u16 = addrIndY(cpu);
                cpu.loadReg(addr, &cpu.a);
            },
            Cpu.Insn.sta_indy.value => {
                const addr: u16 = addrIndY6(cpu);
                cpu.writeByte(cpu.a, addr);
            },
            Cpu.Insn.sta_zp.value => {
                const addr: u16 = addrZp(cpu);
                cpu.writeByte(cpu.a, addr);
            },
            Cpu.Insn.stx_zp.value => {
                const addr: u16 = addrZp(cpu);
                cpu.writeByte(cpu.x, addr);
            },
            Cpu.Insn.stx_zpy.value => {
                const addr: u16 = addrZpY(cpu);
                cpu.writeByte(cpu.x, addr);
            },
            Cpu.Insn.sty_zp.value => {
                const addr: u16 = addrZp(cpu);
                cpu.writeByte(cpu.y, addr);
            },
            Cpu.Insn.sta_abs.value => {
                const addr: u16 = addrAbs(cpu);
                cpu.writeByte(cpu.a, addr);
            },
            Cpu.Insn.stx_abs.value => {
                const addr: u16 = addrAbs(cpu);
                cpu.writeByte(cpu.x, addr);
            },
            Cpu.Insn.sty_abs.value => {
                const addr: u16 = addrAbs(cpu);
                cpu.writeByte(cpu.y, addr);
            },
            Cpu.Insn.sta_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                cpu.writeByte(cpu.a, addr);
            },
            Cpu.Insn.sty_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                cpu.writeByte(cpu.y, addr);
            },
            Cpu.Insn.sta_absx.value => {
                const addr: u16 = addrAbsX5(cpu);
                cpu.writeByte(cpu.a, addr);
            },
            Cpu.Insn.sta_absy.value => {
                const addr: u16 = addrAbsY5(cpu);
                cpu.writeByte(cpu.a, addr);
            },

            Cpu.Insn.jsr.value => {
                const jsr_addr: u16 = fetchWord(cpu);
                const ret_addr = cpu.pc - 1;
                cpu.pushW(ret_addr);
                cpu.pc = jsr_addr;
                cpu.cycles_executed +%= 1; // Matches 6 cycles with fetch and push
                if (cpu.c64.cpu_dbg_enabled) {
                    stdout.print("[cpu] JSR {X:0>4}, return to {X:0>4}\n", .{
                        jsr_addr,
                        ret_addr,
                    }) catch {};
                }
            },

            Cpu.Insn.rts.value => {
                const ret_addr: u16 = popW(cpu);
                cpu.pc = ret_addr + 1;
                cpu.cycles_executed +%= 2;
                if (cpu.c64.cpu_dbg_enabled) {
                    stdout.print("[cpu] RTS to {X:0>4}\n", .{
                        ret_addr + 1,
                    }) catch {};
                }
                if (ret_addr == 0x0000) {
                    if (cpu.c64.cpu_dbg_enabled) {
                        stdout.print("[cpu] RTS EXIT!\n", .{}) catch {};
                    }
                    cpu.cycles_last_step =
                        @as(u8, @truncate(cpu.cycles_executed -% cycles_now));

                    // skip vic timing on exit

                    return 0;
                }
            },
            Cpu.Insn.jmp_abs.value => {
                const addr: u16 = addrAbs(cpu);
                cpu.pc = addr;
                if (cpu.c64.cpu_dbg_enabled) {
                    stdout.print("[cpu] JMP {X:0>4}\n", .{addr}) catch {};
                }
            },

            Cpu.Insn.jmp_ind.value => {
                const addr: u16 = addrAbs(cpu);
                const lo: u8 = cpu.readByte(addr);
                const hi_addr: u16 = (addr & 0xFF00) | ((addr + 1) & 0x00FF); // Wrap to $xx00
                const hi: u8 = cpu.readByte(hi_addr);
                cpu.pc = @as(u16, lo) | (@as(u16, hi) << 8);
            },

            Cpu.Insn.tsx.value => {
                cpu.x = cpu.sp;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.x);
            },
            Cpu.Insn.txs.value => {
                cpu.sp = cpu.x;
                cpu.cycles_executed +%= 1;
            },
            Cpu.Insn.pha.value => {
                cpu.pushB(cpu.a);
            },
            Cpu.Insn.pla.value => {
                cpu.a = popB(cpu);
                cpu.updateFlags(cpu.a);
                cpu.cycles_executed +%= 1;
            },
            Cpu.Insn.php.value => {
                pushPs(cpu);
            },
            Cpu.Insn.plp.value => {
                popPs(cpu);
                cpu.cycles_executed +%= 1;
            },
            Cpu.Insn.tax.value => {
                cpu.x = cpu.a;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.x);
            },
            Cpu.Insn.tay.value => {
                cpu.y = cpu.a;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.y);
            },
            Cpu.Insn.txa.value => {
                cpu.a = cpu.x;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.a);
            },
            Cpu.Insn.tya.value => {
                cpu.a = cpu.y;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.a);
            },
            Cpu.Insn.inx.value => {
                cpu.x +%= 1;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.x);
            },
            Cpu.Insn.iny.value => {
                cpu.y +%= 1;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.y);
            },
            Cpu.Insn.dex.value => {
                cpu.x -%= 1;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.x);
            },
            Cpu.Insn.dey.value => {
                cpu.y -%= 1;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.y);
            },
            Cpu.Insn.dec_zp.value => {
                const addr: u16 = addrZp(cpu);
                var val: u8 = cpu.readByte(addr);
                val -%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            Cpu.Insn.dec_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                var val: u8 = cpu.readByte(addr);
                val -%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            Cpu.Insn.dec_abs.value => {
                const addr: u16 = addrAbs(cpu);
                var val: u8 = cpu.readByte(addr);
                val -%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            Cpu.Insn.dec_absx.value => {
                const addr: u16 = addrAbsX5(cpu);
                var val: u8 = cpu.readByte(addr);
                val -%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            Cpu.Insn.inc_zp.value => {
                const addr: u16 = addrZp(cpu);
                var val: u8 = cpu.readByte(addr);
                val +%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            Cpu.Insn.inc_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                var val: u8 = cpu.readByte(addr);
                val +%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            Cpu.Insn.inc_abs.value => {
                const addr: u16 = addrAbs(cpu);
                var val: u8 = cpu.readByte(addr);
                val +%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            Cpu.Insn.inc_absx.value => {
                const addr: u16 = addrAbsX5(cpu);
                var val: u8 = cpu.readByte(addr);
                val +%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            Cpu.Insn.beq.value => {
                cpu.branch(@as(u8, cpu.flags.z), 1);
            },
            Cpu.Insn.bne.value => {
                cpu.branch(@as(u8, cpu.flags.z), 0);
            },
            Cpu.Insn.bcs.value => {
                cpu.branch(@as(u8, cpu.flags.c), 1);
            },
            Cpu.Insn.bcc.value => {
                cpu.branch(@as(u8, cpu.flags.c), 0);
            },
            Cpu.Insn.bmi.value => {
                cpu.branch(@as(u8, cpu.flags.n), 1);
            },
            Cpu.Insn.bpl.value => {
                cpu.branch(@as(u8, cpu.flags.n), 0);
            },
            Cpu.Insn.bvc.value => {
                cpu.branch(@as(u8, cpu.flags.v), 0);
            },
            Cpu.Insn.bvs.value => {
                cpu.branch(@as(u8, cpu.flags.v), 1);
            },
            Cpu.Insn.clc.value => {
                cpu.flags.c = 0;
                cpu.cycles_executed +%= 1;
            },
            Cpu.Insn.sec.value => {
                cpu.flags.c = 1;
                cpu.cycles_executed +%= 1;
            },
            Cpu.Insn.cld.value => {
                cpu.flags.d = 0;
                cpu.cycles_executed +%= 1;
            },
            Cpu.Insn.sed.value => {
                cpu.flags.d = 1;
                cpu.cycles_executed +%= 1;
            },
            Cpu.Insn.cli.value => {
                cpu.flags.i = 0;
                cpu.cycles_executed +%= 1;
            },
            Cpu.Insn.sei.value => {
                cpu.flags.i = 1;
                cpu.cycles_executed +%= 1;
            },
            Cpu.Insn.clv.value => {
                cpu.flags.v = 0;
                cpu.cycles_executed +%= 1;
            },
            Cpu.Insn.nop.value => {
                cpu.cycles_executed +%= 1;
            },
            Cpu.Insn.adc_abs.value => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.adc(op);
            },
            Cpu.Insn.adc_absx.value => {
                const addr: u16 = addrAbsX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.adc(op);
            },
            Cpu.Insn.adc_absy.value => {
                const addr: u16 = addrAbsY(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.adc(op);
            },
            Cpu.Insn.adc_zp.value => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.adc(op);
            },
            Cpu.Insn.adc_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.adc(op);
            },
            Cpu.Insn.adc_indx.value => {
                const addr: u16 = addrIndX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.adc(op);
            },
            Cpu.Insn.adc_indy.value => {
                const addr: u16 = addrIndY(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.adc(op);
            },
            Cpu.Insn.adc_imm.value => {
                const op: u8 = fetchUByte(cpu);
                cpu.adc(op);
            },
            Cpu.Insn.sbc_imm.value => {
                const op: u8 = fetchUByte(cpu);
                cpu.sbc(op);
            },
            Cpu.Insn.sbc_abs.value => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.sbc(op);
            },
            Cpu.Insn.sbc_zp.value => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.sbc(op);
            },
            Cpu.Insn.sbc_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.sbc(op);
            },
            Cpu.Insn.sbc_absx.value => {
                const addr: u16 = addrAbsX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.sbc(op);
            },
            Cpu.Insn.sbc_absy.value => {
                const addr: u16 = addrAbsY(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.sbc(op);
            },
            Cpu.Insn.sbc_indx.value => {
                const addr: u16 = addrIndX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.sbc(op);
            },
            Cpu.Insn.sbc_indy.value => {
                const addr: u16 = addrIndY(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.sbc(op);
            },
            Cpu.Insn.cpx_imm.value => {
                const op: u8 = fetchUByte(cpu);
                cpu.cmpReg(op, cpu.x);
            },
            Cpu.Insn.cpy_imm.value => {
                const op: u8 = fetchUByte(cpu);
                cpu.cmpReg(op, cpu.y);
            },
            Cpu.Insn.cpx_zp.value => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.x);
            },
            Cpu.Insn.cpy_zp.value => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.y);
            },
            Cpu.Insn.cpx_abs.value => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.x);
            },
            Cpu.Insn.cpy_abs.value => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.y);
            },
            Cpu.Insn.cmp_imm.value => {
                const op: u8 = fetchUByte(cpu);
                cpu.cmpReg(op, cpu.a);
            },
            Cpu.Insn.cmp_zp.value => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.a);
            },
            Cpu.Insn.cmp_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.a);
            },
            Cpu.Insn.cmp_abs.value => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.a);
            },
            Cpu.Insn.cmp_absx.value => {
                const addr: u16 = addrAbsX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.a);
            },
            Cpu.Insn.cmp_absy.value => {
                const addr: u16 = addrAbsY(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.a);
            },
            Cpu.Insn.cmp_indx.value => {
                const addr: u16 = addrIndX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.a);
            },
            Cpu.Insn.cmp_indy.value => {
                const addr: u16 = addrIndY(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.a);
            },
            Cpu.Insn.asl_a.value => {
                cpu.a = cpu.asl(cpu.a);
            },
            Cpu.Insn.asl_zp.value => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.asl(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.asl_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.asl(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.asl_abs.value => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.asl(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.asl_absx.value => {
                const addr: u16 = addrAbsX5(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.asl(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.lsr_a.value => {
                cpu.a = cpu.lsr(cpu.a);
            },
            Cpu.Insn.lsr_zp.value => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.lsr(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.lsr_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.lsr(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.lsr_abs.value => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.lsr(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.lsr_absx.value => {
                const addr: u16 = addrAbsX5(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.lsr(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.rol_a.value => {
                cpu.a = cpu.rol(cpu.a);
            },
            Cpu.Insn.rol_zp.value => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.rol(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.rol_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.rol(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.rol_abs.value => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.rol(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.rol_absx.value => {
                const addr: u16 = addrAbsX5(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.rol(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.ror_a.value => {
                cpu.a = cpu.ror(cpu.a);
            },
            Cpu.Insn.ror_zp.value => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.ror(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.ror_zpx.value => {
                const addr: u16 = addrZpX(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.ror(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.ror_abs.value => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.ror(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.ror_absx.value => {
                const addr: u16 = addrAbsX5(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.ror(op);
                cpu.writeByte(res, addr);
            },
            Cpu.Insn.brk.value => {
                cpu.pushW(cpu.pc + 1);
                pushPs(cpu);
                cpu.pc = cpu.readWord(65534);
                cpu.flags.b = 1;
                cpu.flags.i = 1;
                return 0;
            },
            Cpu.Insn.rti.value => {
                popPs(cpu);
                cpu.pc = popW(cpu);
            },
            else => return 0,
        }
        cpu.cycles_last_step =
            @as(u8, @truncate(cpu.cycles_executed -% cycles_now));

        cpu.cycles_since_vsync += cpu.cycles_last_step;
        cpu.cycles_since_hsync += cpu.cycles_last_step;

        // VIC vertical sync
        if (cpu.c64.vic.model == Vic.Model.pal and
            cpu.cycles_since_vsync >= Vic.Timing.cyclesVsyncPal)
        {
            cpu.c64.vic.frame_ctr += 1;
            cpu.cycles_since_vsync = 0;
        }

        if (cpu.c64.vic.model == Vic.Model.ntsc and
            cpu.cycles_since_vsync >= Vic.Timing.cyclesVsyncNtsc)
        {
            cpu.c64.vic.frame_ctr += 1;
            cpu.cycles_since_vsync = 0;
        }

        // VIC horizontal sync
        if (cpu.c64.vic.model == Vic.Model.pal and
            cpu.cycles_since_hsync >= Vic.Timing.cyclesRasterlinePal)
        {
            cpu.c64.vic.emulateD012();
            cpu.cycles_since_hsync = 0;
        }

        if (cpu.c64.vic.model == Vic.Model.ntsc and
            cpu.cycles_since_hsync >= Vic.Timing.cyclesRasterlineNtsc)
        {
            cpu.c64.vic.emulateD012();
            cpu.cycles_since_hsync = 0;
        }

        // dbg output vic, sid

        if (cpu.c64.vic_dbg_enabled) {
            cpu.c64.vic.printStatus();
        }

        if (cpu.c64.sid_dbg_enabled and cpu.sid_reg_written) {
            cpu.c64.sid.printRegisters();
        }

        // return from interrupt vector
        if ((cpu.c64.mem.data[0x01] & 0x07) != 0x5 and
            ((cpu.pc == 0xea31) or (cpu.pc == 0xea81)))
        {
            stdout.print("[cpu] RTI\n", .{}) catch {};

            return 0;
        }

        return cpu.cycles_last_step;
    }

    pub fn disassemble(cpu: *Cpu, pc_start: u16, count: usize) void {
        var pc = pc_start; // Current program counter
        var counter: usize = 0; // Instruction counter

        while (counter < count) : (counter += 1) {
            // Get the opcode and operands from memory
            const opcode = cpu.c64.mem.data[pc];
            const byte2 = if (pc + 1 < 0x10000) cpu.c64.mem.data[pc +% 1] else 0; // Avoid overflow
            const byte3 = if (pc + 2 < 0x10000) cpu.c64.mem.data[pc +% 2] else 0; // Avoid overflow

            // Buffer for the disassembled string
            var buf: [16]u8 = undefined;
            const disasm = disassembleOpcode(&buf, pc, opcode, byte2, byte3) catch "???";

            // Print the address and disassembled instruction
            stdout.print("${X:0>4}: {s}\n", .{ pc, disasm }) catch {};

            // Get the instruction size and advance pc
            const insn = opcode2Insn(opcode);
            const size = getInsnSize(insn);
            pc = pc +% size; // Wrapping addition for 16-bit address space
        }
    }

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

    pub const Operand = struct {
        pub const none: u8 = 0x00;
        pub const a: u8 = 0x01; // Accumulator
        pub const x: u8 = 0x02; // X register
        pub const y: u8 = 0x04; // Y register
        pub const sp: u8 = 0x08; // Stack pointer
        pub const memory: u8 = 0x10; // Memory access
    };

    pub const Opcode = struct {
        value: u8,
        mnemonic: []const u8,
        addr_mode: AddrMode,
        group: Group,
        operand_type: OperandType,
        operand_size: OperandSize,
        access_type: u2,
        operand: u8,
    };

    pub const Insn = struct {
        // Branch instructions
        pub const brk = Opcode{
            .value = 0x00,
            .mnemonic = "BRK",
            .addr_mode = .implied,
            .group = .branch,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.sp,
        };
        pub const rti = Opcode{
            .value = 0x40,
            .mnemonic = "RTI",
            .addr_mode = .implied,
            .group = .branch,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.sp,
        };
        pub const rts = Opcode{
            .value = 0x60,
            .mnemonic = "RTS",
            .addr_mode = .implied,
            .group = .branch,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.sp,
        };
        pub const jsr = Opcode{
            .value = 0x20,
            .mnemonic = "JSR",
            .addr_mode = .absolute,
            .group = .branch,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.none,
            .operand = Operand.sp | Operand.memory,
        };
        pub const jmp_abs = Opcode{
            .value = 0x4C,
            .mnemonic = "JMP",
            .addr_mode = .absolute,
            .group = .branch,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.none,
            .operand = Operand.memory,
        };
        pub const jmp_ind = Opcode{
            .value = 0x6C,
            .mnemonic = "JMP",
            .addr_mode = .indirect,
            .group = .branch,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.memory,
        };
        pub const beq = Opcode{
            .value = 0xF0,
            .mnemonic = "BEQ",
            .addr_mode = .immediate,
            .group = .branch,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };
        pub const bne = Opcode{
            .value = 0xD0,
            .mnemonic = "BNE",
            .addr_mode = .immediate,
            .group = .branch,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };
        pub const bcs = Opcode{
            .value = 0xB0,
            .mnemonic = "BCS",
            .addr_mode = .immediate,
            .group = .branch,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };
        pub const bcc = Opcode{
            .value = 0x90,
            .mnemonic = "BCC",
            .addr_mode = .immediate,
            .group = .branch,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };
        pub const bmi = Opcode{
            .value = 0x30,
            .mnemonic = "BMI",
            .addr_mode = .immediate,
            .group = .branch,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };
        pub const bpl = Opcode{
            .value = 0x10,
            .mnemonic = "BPL",
            .addr_mode = .immediate,
            .group = .branch,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };
        pub const bvc = Opcode{
            .value = 0x50,
            .mnemonic = "BVC",
            .addr_mode = .immediate,
            .group = .branch,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };
        pub const bvs = Opcode{
            .value = 0x70,
            .mnemonic = "BVS",
            .addr_mode = .immediate,
            .group = .branch,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };

        // Load/Store instructions
        pub const lda_imm = Opcode{
            .value = 0xA9,
            .mnemonic = "LDA",
            .addr_mode = .immediate,
            .group = .load_store,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a,
        };
        pub const lda_zp = Opcode{
            .value = 0xA5,
            .mnemonic = "LDA",
            .addr_mode = .zero_page,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const lda_zpx = Opcode{
            .value = 0xB5,
            .mnemonic = "LDA",
            .addr_mode = .zero_page_x,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const lda_abs = Opcode{
            .value = 0xAD,
            .mnemonic = "LDA",
            .addr_mode = .absolute,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const lda_absx = Opcode{
            .value = 0xBD,
            .mnemonic = "LDA",
            .addr_mode = .absolute_x,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const lda_absy = Opcode{
            .value = 0xB9,
            .mnemonic = "LDA",
            .addr_mode = .absolute_y,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const lda_indx = Opcode{
            .value = 0xA1,
            .mnemonic = "LDA",
            .addr_mode = .indexed_indirect_x,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const lda_indy = Opcode{
            .value = 0xB1,
            .mnemonic = "LDA",
            .addr_mode = .indirect_indexed_y,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const ldx_imm = Opcode{
            .value = 0xA2,
            .mnemonic = "LDX",
            .addr_mode = .immediate,
            .group = .load_store,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.x,
        };
        pub const ldx_zp = Opcode{
            .value = 0xA6,
            .mnemonic = "LDX",
            .addr_mode = .zero_page,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.x | Operand.memory,
        };
        pub const ldx_zpy = Opcode{
            .value = 0xB6,
            .mnemonic = "LDX",
            .addr_mode = .zero_page_y,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.x | Operand.y | Operand.memory,
        };
        pub const ldx_abs = Opcode{
            .value = 0xAE,
            .mnemonic = "LDX",
            .addr_mode = .absolute,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.x | Operand.memory,
        };
        pub const ldx_absy = Opcode{
            .value = 0xBE,
            .mnemonic = "LDX",
            .addr_mode = .absolute_y,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.x | Operand.y | Operand.memory,
        };
        pub const ldy_imm = Opcode{
            .value = 0xA0,
            .mnemonic = "LDY",
            .addr_mode = .immediate,
            .group = .load_store,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.y,
        };
        pub const ldy_zp = Opcode{
            .value = 0xA4,
            .mnemonic = "LDY",
            .addr_mode = .zero_page,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.y | Operand.memory,
        };
        pub const ldy_zpx = Opcode{
            .value = 0xB4,
            .mnemonic = "LDY",
            .addr_mode = .zero_page_x,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.y | Operand.x | Operand.memory,
        };
        pub const ldy_abs = Opcode{
            .value = 0xAC,
            .mnemonic = "LDY",
            .addr_mode = .absolute,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.y | Operand.memory,
        };
        pub const ldy_absx = Opcode{
            .value = 0xBC,
            .mnemonic = "LDY",
            .addr_mode = .absolute_x,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.y | Operand.x | Operand.memory,
        };
        pub const sta_zp = Opcode{
            .value = 0x85,
            .mnemonic = "STA",
            .addr_mode = .zero_page,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.write,
            .operand = Operand.a | Operand.memory,
        };
        pub const sta_zpx = Opcode{
            .value = 0x95,
            .mnemonic = "STA",
            .addr_mode = .zero_page_x,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.write,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const sta_abs = Opcode{
            .value = 0x8D,
            .mnemonic = "STA",
            .addr_mode = .absolute,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.write,
            .operand = Operand.a | Operand.memory,
        };
        pub const sta_absx = Opcode{
            .value = 0x9D,
            .mnemonic = "STA",
            .addr_mode = .absolute_x,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.write,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const sta_absy = Opcode{
            .value = 0x99,
            .mnemonic = "STA",
            .addr_mode = .absolute_y,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.write,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const sta_indx = Opcode{
            .value = 0x81,
            .mnemonic = "STA",
            .addr_mode = .indexed_indirect_x,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.write,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const sta_indy = Opcode{
            .value = 0x91,
            .mnemonic = "STA",
            .addr_mode = .indirect_indexed_y,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.write,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const stx_zp = Opcode{
            .value = 0x86,
            .mnemonic = "STX",
            .addr_mode = .zero_page,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.write,
            .operand = Operand.x | Operand.memory,
        };
        pub const stx_zpy = Opcode{
            .value = 0x96,
            .mnemonic = "STX",
            .addr_mode = .zero_page_y,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.write,
            .operand = Operand.x | Operand.y | Operand.memory,
        };
        pub const stx_abs = Opcode{
            .value = 0x8E,
            .mnemonic = "STX",
            .addr_mode = .absolute,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.write,
            .operand = Operand.x | Operand.memory,
        };
        pub const sty_zp = Opcode{
            .value = 0x84,
            .mnemonic = "STY",
            .addr_mode = .zero_page,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.write,
            .operand = Operand.y | Operand.memory,
        };
        pub const sty_zpx = Opcode{
            .value = 0x94,
            .mnemonic = "STY",
            .addr_mode = .zero_page_x,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.write,
            .operand = Operand.y | Operand.x | Operand.memory,
        };
        pub const sty_abs = Opcode{
            .value = 0x8C,
            .mnemonic = "STY",
            .addr_mode = .absolute,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.write,
            .operand = Operand.y | Operand.memory,
        };
        pub const dec_zp = Opcode{
            .value = 0xC6,
            .mnemonic = "DEC",
            .addr_mode = .zero_page,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read_write,
            .operand = Operand.memory,
        };
        pub const dec_zpx = Opcode{
            .value = 0xD6,
            .mnemonic = "DEC",
            .addr_mode = .zero_page_x,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read_write,
            .operand = Operand.x | Operand.memory,
        };
        pub const dec_abs = Opcode{
            .value = 0xCE,
            .mnemonic = "DEC",
            .addr_mode = .absolute,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read_write,
            .operand = Operand.memory,
        };
        pub const dec_absx = Opcode{
            .value = 0xDE,
            .mnemonic = "DEC",
            .addr_mode = .absolute_x,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read_write,
            .operand = Operand.x | Operand.memory,
        };
        pub const inc_zp = Opcode{
            .value = 0xE6,
            .mnemonic = "INC",
            .addr_mode = .zero_page,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read_write,
            .operand = Operand.memory,
        };
        pub const inc_zpx = Opcode{
            .value = 0xF6,
            .mnemonic = "INC",
            .addr_mode = .zero_page_x,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read_write,
            .operand = Operand.x | Operand.memory,
        };
        pub const inc_abs = Opcode{
            .value = 0xEE,
            .mnemonic = "INC",
            .addr_mode = .absolute,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read_write,
            .operand = Operand.memory,
        };
        pub const inc_absx = Opcode{
            .value = 0xFE,
            .mnemonic = "INC",
            .addr_mode = .absolute_x,
            .group = .load_store,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read_write,
            .operand = Operand.x | Operand.memory,
        };

        // Control instructions
        pub const nop = Opcode{
            .value = 0xEA,
            .mnemonic = "NOP",
            .addr_mode = .implied,
            .group = .control,
            .operand_type = .none,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };
        pub const clc = Opcode{
            .value = 0x18,
            .mnemonic = "CLC",
            .addr_mode = .implied,
            .group = .control,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };
        pub const sec = Opcode{
            .value = 0x38,
            .mnemonic = "SEC",
            .addr_mode = .implied,
            .group = .control,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };
        pub const cli = Opcode{
            .value = 0x58,
            .mnemonic = "CLI",
            .addr_mode = .implied,
            .group = .control,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };
        pub const sei = Opcode{
            .value = 0x78,
            .mnemonic = "SEI",
            .addr_mode = .implied,
            .group = .control,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };
        pub const cld = Opcode{
            .value = 0xD8,
            .mnemonic = "CLD",
            .addr_mode = .implied,
            .group = .control,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };
        pub const sed = Opcode{
            .value = 0xF8,
            .mnemonic = "SED",
            .addr_mode = .implied,
            .group = .control,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };
        pub const clv = Opcode{
            .value = 0xB8,
            .mnemonic = "CLV",
            .addr_mode = .implied,
            .group = .control,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.none,
        };

        // Math instructions
        pub const adc_imm = Opcode{
            .value = 0x69,
            .mnemonic = "ADC",
            .addr_mode = .immediate,
            .group = .math,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a,
        };
        pub const adc_zp = Opcode{
            .value = 0x65,
            .mnemonic = "ADC",
            .addr_mode = .zero_page,
            .group = .math,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const adc_zpx = Opcode{
            .value = 0x75,
            .mnemonic = "ADC",
            .addr_mode = .zero_page_x,
            .group = .math,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const adc_abs = Opcode{
            .value = 0x6D,
            .mnemonic = "ADC",
            .addr_mode = .absolute,
            .group = .math,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const adc_absx = Opcode{
            .value = 0x7D,
            .mnemonic = "ADC",
            .addr_mode = .absolute_x,
            .group = .math,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const adc_absy = Opcode{
            .value = 0x79,
            .mnemonic = "ADC",
            .addr_mode = .absolute_y,
            .group = .math,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const adc_indx = Opcode{
            .value = 0x61,
            .mnemonic = "ADC",
            .addr_mode = .indexed_indirect_x,
            .group = .math,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const adc_indy = Opcode{
            .value = 0x71,
            .mnemonic = "ADC",
            .addr_mode = .indirect_indexed_y,
            .group = .math,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const sbc_imm = Opcode{
            .value = 0xE9,
            .mnemonic = "SBC",
            .addr_mode = .immediate,
            .group = .math,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a,
        };
        pub const sbc_zp = Opcode{
            .value = 0xE5,
            .mnemonic = "SBC",
            .addr_mode = .zero_page,
            .group = .math,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const sbc_zpx = Opcode{
            .value = 0xF5,
            .mnemonic = "SBC",
            .addr_mode = .zero_page_x,
            .group = .math,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const sbc_abs = Opcode{
            .value = 0xED,
            .mnemonic = "SBC",
            .addr_mode = .absolute,
            .group = .math,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const sbc_absx = Opcode{
            .value = 0xFD,
            .mnemonic = "SBC",
            .addr_mode = .absolute_x,
            .group = .math,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const sbc_absy = Opcode{
            .value = 0xF9,
            .mnemonic = "SBC",
            .addr_mode = .absolute_y,
            .group = .math,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const sbc_indx = Opcode{
            .value = 0xE1,
            .mnemonic = "SBC",
            .addr_mode = .indexed_indirect_x,
            .group = .math,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const sbc_indy = Opcode{
            .value = 0xF1,
            .mnemonic = "SBC",
            .addr_mode = .indirect_indexed_y,
            .group = .math,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.y | Operand.memory,
        };

        // Logic instructions
        pub const and_imm = Opcode{
            .value = 0x29,
            .mnemonic = "AND",
            .addr_mode = .immediate,
            .group = .logic,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a,
        };
        pub const and_zp = Opcode{
            .value = 0x25,
            .mnemonic = "AND",
            .addr_mode = .zero_page,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const and_zpx = Opcode{
            .value = 0x35,
            .mnemonic = "AND",
            .addr_mode = .zero_page_x,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const and_abs = Opcode{
            .value = 0x2D,
            .mnemonic = "AND",
            .addr_mode = .absolute,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const and_absx = Opcode{
            .value = 0x3D,
            .mnemonic = "AND",
            .addr_mode = .absolute_x,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const and_absy = Opcode{
            .value = 0x39,
            .mnemonic = "AND",
            .addr_mode = .absolute_y,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const and_indx = Opcode{
            .value = 0x21,
            .mnemonic = "AND",
            .addr_mode = .indexed_indirect_x,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const and_indy = Opcode{
            .value = 0x31,
            .mnemonic = "AND",
            .addr_mode = .indirect_indexed_y,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const ora_imm = Opcode{
            .value = 0x09,
            .mnemonic = "ORA",
            .addr_mode = .immediate,
            .group = .logic,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a,
        };
        pub const ora_zp = Opcode{
            .value = 0x05,
            .mnemonic = "ORA",
            .addr_mode = .zero_page,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const ora_zpx = Opcode{
            .value = 0x15,
            .mnemonic = "ORA",
            .addr_mode = .zero_page_x,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const ora_abs = Opcode{
            .value = 0x0D,
            .mnemonic = "ORA",
            .addr_mode = .absolute,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const ora_absx = Opcode{
            .value = 0x1D,
            .mnemonic = "ORA",
            .addr_mode = .absolute_x,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const ora_absy = Opcode{
            .value = 0x19,
            .mnemonic = "ORA",
            .addr_mode = .absolute_y,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const ora_indx = Opcode{
            .value = 0x01,
            .mnemonic = "ORA",
            .addr_mode = .indexed_indirect_x,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const ora_indy = Opcode{
            .value = 0x11,
            .mnemonic = "ORA",
            .addr_mode = .indirect_indexed_y,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const eor_imm = Opcode{
            .value = 0x49,
            .mnemonic = "EOR",
            .addr_mode = .immediate,
            .group = .logic,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a,
        };
        pub const eor_zp = Opcode{
            .value = 0x45,
            .mnemonic = "EOR",
            .addr_mode = .zero_page,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const eor_zpx = Opcode{
            .value = 0x55,
            .mnemonic = "EOR",
            .addr_mode = .zero_page_x,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const eor_abs = Opcode{
            .value = 0x4D,
            .mnemonic = "EOR",
            .addr_mode = .absolute,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const eor_absx = Opcode{
            .value = 0x5D,
            .mnemonic = "EOR",
            .addr_mode = .absolute_x,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const eor_absy = Opcode{
            .value = 0x59,
            .mnemonic = "EOR",
            .addr_mode = .absolute_y,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const eor_indx = Opcode{
            .value = 0x41,
            .mnemonic = "EOR",
            .addr_mode = .indexed_indirect_x,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const eor_indy = Opcode{
            .value = 0x51,
            .mnemonic = "EOR",
            .addr_mode = .indirect_indexed_y,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const bit_zp = Opcode{
            .value = 0x24,
            .mnemonic = "BIT",
            .addr_mode = .zero_page,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const bit_abs = Opcode{
            .value = 0x2C,
            .mnemonic = "BIT",
            .addr_mode = .absolute,
            .group = .logic,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };

        // Compare instructions
        pub const cmp_imm = Opcode{
            .value = 0xC9,
            .mnemonic = "CMP",
            .addr_mode = .immediate,
            .group = .compare,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a,
        };
        pub const cmp_zp = Opcode{
            .value = 0xC5,
            .mnemonic = "CMP",
            .addr_mode = .zero_page,
            .group = .compare,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const cmp_zpx = Opcode{
            .value = 0xD5,
            .mnemonic = "CMP",
            .addr_mode = .zero_page_x,
            .group = .compare,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const cmp_abs = Opcode{
            .value = 0xCD,
            .mnemonic = "CMP",
            .addr_mode = .absolute,
            .group = .compare,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.memory,
        };
        pub const cmp_absx = Opcode{
            .value = 0xDD,
            .mnemonic = "CMP",
            .addr_mode = .absolute_x,
            .group = .compare,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const cmp_absy = Opcode{
            .value = 0xD9,
            .mnemonic = "CMP",
            .addr_mode = .absolute_y,
            .group = .compare,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const cmp_indx = Opcode{
            .value = 0xC1,
            .mnemonic = "CMP",
            .addr_mode = .indexed_indirect_x,
            .group = .compare,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.x | Operand.memory,
        };
        pub const cmp_indy = Opcode{
            .value = 0xD1,
            .mnemonic = "CMP",
            .addr_mode = .indirect_indexed_y,
            .group = .compare,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.y | Operand.memory,
        };
        pub const cpx_imm = Opcode{
            .value = 0xE0,
            .mnemonic = "CPX",
            .addr_mode = .immediate,
            .group = .compare,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.x,
        };
        pub const cpx_zp = Opcode{
            .value = 0xE4,
            .mnemonic = "CPX",
            .addr_mode = .zero_page,
            .group = .compare,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.x | Operand.memory,
        };
        pub const cpx_abs = Opcode{
            .value = 0xEC,
            .mnemonic = "CPX",
            .addr_mode = .absolute,
            .group = .compare,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.x | Operand.memory,
        };
        pub const cpy_imm = Opcode{
            .value = 0xC0,
            .mnemonic = "CPY",
            .addr_mode = .immediate,
            .group = .compare,
            .operand_type = .immediate,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.y,
        };
        pub const cpy_zp = Opcode{
            .value = 0xC4,
            .mnemonic = "CPY",
            .addr_mode = .zero_page,
            .group = .compare,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read,
            .operand = Operand.y | Operand.memory,
        };
        pub const cpy_abs = Opcode{
            .value = 0xCC,
            .mnemonic = "CPY",
            .addr_mode = .absolute,
            .group = .compare,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read,
            .operand = Operand.y | Operand.memory,
        };

        // Shift instructions
        pub const asl_a = Opcode{
            .value = 0x0A,
            .mnemonic = "ASL",
            .addr_mode = .implied,
            .group = .shift,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.read_write,
            .operand = Operand.a,
        };
        pub const asl_zp = Opcode{
            .value = 0x06,
            .mnemonic = "ASL",
            .addr_mode = .zero_page,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read_write,
            .operand = Operand.memory,
        };
        pub const asl_zpx = Opcode{
            .value = 0x16,
            .mnemonic = "ASL",
            .addr_mode = .zero_page_x,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read_write,
            .operand = Operand.x | Operand.memory,
        };
        pub const asl_abs = Opcode{
            .value = 0x0E,
            .mnemonic = "ASL",
            .addr_mode = .absolute,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read_write,
            .operand = Operand.memory,
        };
        pub const asl_absx = Opcode{
            .value = 0x1E,
            .mnemonic = "ASL",
            .addr_mode = .absolute_x,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read_write,
            .operand = Operand.x | Operand.memory,
        };
        pub const lsr_a = Opcode{
            .value = 0x4A,
            .mnemonic = "LSR",
            .addr_mode = .implied,
            .group = .shift,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.read_write,
            .operand = Operand.a,
        };
        pub const lsr_zp = Opcode{
            .value = 0x46,
            .mnemonic = "LSR",
            .addr_mode = .zero_page,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read_write,
            .operand = Operand.memory,
        };
        pub const lsr_zpx = Opcode{
            .value = 0x56,
            .mnemonic = "LSR",
            .addr_mode = .zero_page_x,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read_write,
            .operand = Operand.x | Operand.memory,
        };
        pub const lsr_abs = Opcode{
            .value = 0x4E,
            .mnemonic = "LSR",
            .addr_mode = .absolute,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read_write,
            .operand = Operand.memory,
        };
        pub const lsr_absx = Opcode{
            .value = 0x5E,
            .mnemonic = "LSR",
            .addr_mode = .absolute_x,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read_write,
            .operand = Operand.x | Operand.memory,
        };
        pub const rol_a = Opcode{
            .value = 0x2A,
            .mnemonic = "ROL",
            .addr_mode = .implied,
            .group = .shift,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.read_write,
            .operand = Operand.a,
        };
        pub const rol_zp = Opcode{
            .value = 0x26,
            .mnemonic = "ROL",
            .addr_mode = .zero_page,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read_write,
            .operand = Operand.memory,
        };
        pub const rol_zpx = Opcode{
            .value = 0x36,
            .mnemonic = "ROL",
            .addr_mode = .zero_page_x,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read_write,
            .operand = Operand.x | Operand.memory,
        };
        pub const rol_abs = Opcode{
            .value = 0x2E,
            .mnemonic = "ROL",
            .addr_mode = .absolute,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read_write,
            .operand = Operand.memory,
        };
        pub const rol_absx = Opcode{
            .value = 0x3E,
            .mnemonic = "ROL",
            .addr_mode = .absolute_x,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read_write,
            .operand = Operand.x | Operand.memory,
        };
        pub const ror_a = Opcode{
            .value = 0x6A,
            .mnemonic = "ROR",
            .addr_mode = .implied,
            .group = .shift,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.read_write,
            .operand = Operand.a,
        };
        pub const ror_zp = Opcode{
            .value = 0x66,
            .mnemonic = "ROR",
            .addr_mode = .zero_page,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read_write,
            .operand = Operand.memory,
        };
        pub const ror_zpx = Opcode{
            .value = 0x76,
            .mnemonic = "ROR",
            .addr_mode = .zero_page_x,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .byte,
            .access_type = AccessType.read_write,
            .operand = Operand.x | Operand.memory,
        };
        pub const ror_abs = Opcode{
            .value = 0x6E,
            .mnemonic = "ROR",
            .addr_mode = .absolute,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read_write,
            .operand = Operand.memory,
        };
        pub const ror_absx = Opcode{
            .value = 0x7E,
            .mnemonic = "ROR",
            .addr_mode = .absolute_x,
            .group = .shift,
            .operand_type = .memory,
            .operand_size = .word,
            .access_type = AccessType.read_write,
            .operand = Operand.x | Operand.memory,
        };

        // Stack instructions
        pub const pha = Opcode{
            .value = 0x48,
            .mnemonic = "PHA",
            .addr_mode = .implied,
            .group = .stack,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.write,
            .operand = Operand.a | Operand.sp | Operand.memory,
        };
        pub const pla = Opcode{
            .value = 0x68,
            .mnemonic = "PLA",
            .addr_mode = .implied,
            .group = .stack,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.read,
            .operand = Operand.a | Operand.sp | Operand.memory,
        };
        pub const php = Opcode{
            .value = 0x08,
            .mnemonic = "PHP",
            .addr_mode = .implied,
            .group = .stack,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.write,
            .operand = Operand.sp | Operand.memory,
        };
        pub const plp = Opcode{
            .value = 0x28,
            .mnemonic = "PLP",
            .addr_mode = .implied,
            .group = .stack,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.read,
            .operand = Operand.sp | Operand.memory,
        };

        // Transfer instructions
        pub const tax = Opcode{
            .value = 0xAA,
            .mnemonic = "TAX",
            .addr_mode = .implied,
            .group = .transfer,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.a | Operand.x,
        };
        pub const tay = Opcode{
            .value = 0xA8,
            .mnemonic = "TAY",
            .addr_mode = .implied,
            .group = .transfer,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.a | Operand.y,
        };
        pub const txa = Opcode{
            .value = 0x8A,
            .mnemonic = "TXA",
            .addr_mode = .implied,
            .group = .transfer,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.x | Operand.a,
        };
        pub const tya = Opcode{
            .value = 0x98,
            .mnemonic = "TYA",
            .addr_mode = .implied,
            .group = .transfer,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.y | Operand.a,
        };
        pub const tsx = Opcode{
            .value = 0xBA,
            .mnemonic = "TSX",
            .addr_mode = .implied,
            .group = .transfer,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.sp | Operand.x,
        };
        pub const txs = Opcode{
            .value = 0x9A,
            .mnemonic = "TXS",
            .addr_mode = .implied,
            .group = .transfer,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.none,
            .operand = Operand.x | Operand.sp,
        };
        pub const dex = Opcode{
            .value = 0xCA,
            .mnemonic = "DEX",
            .addr_mode = .implied,
            .group = .transfer,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.read_write,
            .operand = Operand.x,
        };
        pub const dey = Opcode{
            .value = 0x88,
            .mnemonic = "DEY",
            .addr_mode = .implied,
            .group = .transfer,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.read_write,
            .operand = Operand.y,
        };
        pub const inx = Opcode{
            .value = 0xE8,
            .mnemonic = "INX",
            .addr_mode = .implied,
            .group = .transfer,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.read_write,
            .operand = Operand.x,
        };
        pub const iny = Opcode{
            .value = 0xC8,
            .mnemonic = "INY",
            .addr_mode = .implied,
            .group = .transfer,
            .operand_type = .register,
            .operand_size = .none,
            .access_type = AccessType.read_write,
            .operand = Operand.y,
        };
    };

    pub fn opcode2Insn(opcode_value: u8) Opcode {
        return switch (opcode_value) {
            // Branch instructions
            0x00 => Insn.brk,
            0x40 => Insn.rti,
            0x60 => Insn.rts,
            0x20 => Insn.jsr,
            0x4C => Insn.jmp_abs,
            0x6C => Insn.jmp_ind,
            0xF0 => Insn.beq,
            0xD0 => Insn.bne,
            0xB0 => Insn.bcs,
            0x90 => Insn.bcc,
            0x30 => Insn.bmi,
            0x10 => Insn.bpl,
            0x50 => Insn.bvc,
            0x70 => Insn.bvs,

            // Load/Store instructions
            0xA9 => Insn.lda_imm,
            0xA5 => Insn.lda_zp,
            0xB5 => Insn.lda_zpx,
            0xAD => Insn.lda_abs,
            0xBD => Insn.lda_absx,
            0xB9 => Insn.lda_absy,
            0xA1 => Insn.lda_indx,
            0xB1 => Insn.lda_indy,
            0xA2 => Insn.ldx_imm,
            0xA6 => Insn.ldx_zp,
            0xB6 => Insn.ldx_zpy,
            0xAE => Insn.ldx_abs,
            0xBE => Insn.ldx_absy,
            0xA0 => Insn.ldy_imm,
            0xA4 => Insn.ldy_zp,
            0xB4 => Insn.ldy_zpx,
            0xAC => Insn.ldy_abs,
            0xBC => Insn.ldy_absx,
            0x85 => Insn.sta_zp,
            0x95 => Insn.sta_zpx,
            0x8D => Insn.sta_abs,
            0x9D => Insn.sta_absx,
            0x99 => Insn.sta_absy,
            0x81 => Insn.sta_indx,
            0x91 => Insn.sta_indy,
            0x86 => Insn.stx_zp,
            0x96 => Insn.stx_zpy,
            0x8E => Insn.stx_abs,
            0x84 => Insn.sty_zp,
            0x94 => Insn.sty_zpx,
            0x8C => Insn.sty_abs,
            0xC6 => Insn.dec_zp,
            0xD6 => Insn.dec_zpx,
            0xCE => Insn.dec_abs,
            0xDE => Insn.dec_absx,
            0xE6 => Insn.inc_zp,
            0xF6 => Insn.inc_zpx,
            0xEE => Insn.inc_abs,
            0xFE => Insn.inc_absx,

            // Control instructions
            0xEA => Insn.nop,
            0x18 => Insn.clc,
            0x38 => Insn.sec,
            0x58 => Insn.cli,
            0x78 => Insn.sei,
            0xD8 => Insn.cld,
            0xF8 => Insn.sed,
            0xB8 => Insn.clv,

            // Math instructions
            0x69 => Insn.adc_imm,
            0x65 => Insn.adc_zp,
            0x75 => Insn.adc_zpx,
            0x6D => Insn.adc_abs,
            0x7D => Insn.adc_absx,
            0x79 => Insn.adc_absy,
            0x61 => Insn.adc_indx,
            0x71 => Insn.adc_indy,
            0xE9 => Insn.sbc_imm,
            0xE5 => Insn.sbc_zp,
            0xF5 => Insn.sbc_zpx,
            0xED => Insn.sbc_abs,
            0xFD => Insn.sbc_absx,
            0xF9 => Insn.sbc_absy,
            0xE1 => Insn.sbc_indx,
            0xF1 => Insn.sbc_indy,

            // Logic instructions
            0x29 => Insn.and_imm,
            0x25 => Insn.and_zp,
            0x35 => Insn.and_zpx,
            0x2D => Insn.and_abs,
            0x3D => Insn.and_absx,
            0x39 => Insn.and_absy,
            0x21 => Insn.and_indx,
            0x31 => Insn.and_indy,
            0x09 => Insn.ora_imm,
            0x05 => Insn.ora_zp,
            0x15 => Insn.ora_zpx,
            0x0D => Insn.ora_abs,
            0x1D => Insn.ora_absx,
            0x19 => Insn.ora_absy,
            0x01 => Insn.ora_indx,
            0x11 => Insn.ora_indy,
            0x49 => Insn.eor_imm,
            0x45 => Insn.eor_zp,
            0x55 => Insn.eor_zpx,
            0x4D => Insn.eor_abs,
            0x5D => Insn.eor_absx,
            0x59 => Insn.eor_absy,
            0x41 => Insn.eor_indx,
            0x51 => Insn.eor_indy,
            0x24 => Insn.bit_zp,
            0x2C => Insn.bit_abs,

            // Compare instructions
            0xC9 => Insn.cmp_imm,
            0xC5 => Insn.cmp_zp,
            0xD5 => Insn.cmp_zpx,
            0xCD => Insn.cmp_abs,
            0xDD => Insn.cmp_absx,
            0xD9 => Insn.cmp_absy,
            0xC1 => Insn.cmp_indx,
            0xD1 => Insn.cmp_indy,
            0xE0 => Insn.cpx_imm,
            0xE4 => Insn.cpx_zp,
            0xEC => Insn.cpx_abs,
            0xC0 => Insn.cpy_imm,
            0xC4 => Insn.cpy_zp,
            0xCC => Insn.cpy_abs,

            // Shift instructions
            0x0A => Insn.asl_a,
            0x06 => Insn.asl_zp,
            0x16 => Insn.asl_zpx,
            0x0E => Insn.asl_abs,
            0x1E => Insn.asl_absx,
            0x4A => Insn.lsr_a,
            0x46 => Insn.lsr_zp,
            0x56 => Insn.lsr_zpx,
            0x4E => Insn.lsr_abs,
            0x5E => Insn.lsr_absx,
            0x2A => Insn.rol_a,
            0x26 => Insn.rol_zp,
            0x36 => Insn.rol_zpx,
            0x2E => Insn.rol_abs,
            0x3E => Insn.rol_absx,
            0x6A => Insn.ror_a,
            0x66 => Insn.ror_zp,
            0x76 => Insn.ror_zpx,
            0x6E => Insn.ror_abs,
            0x7E => Insn.ror_absx,

            // Stack instructions
            0x48 => Insn.pha,
            0x68 => Insn.pla,
            0x08 => Insn.php,
            0x28 => Insn.plp,

            // Transfer instructions
            0xAA => Insn.tax,
            0xA8 => Insn.tay,
            0x8A => Insn.txa,
            0x98 => Insn.tya,
            0xBA => Insn.tsx,
            0x9A => Insn.txs,
            0xCA => Insn.dex,
            0x88 => Insn.dey,
            0xE8 => Insn.inx,
            0xC8 => Insn.iny,

            // Unknown opcode fallback
            else => Opcode{
                .value = opcode_value,
                .mnemonic = "???",
                .addr_mode = .implied,
                .group = .control,
                .operand_type = .none,
                .operand_size = .none,
                .access_type = AccessType.none,
                .operand = Operand.none,
            },
        };
    }

    pub fn getInsnSize(insn: Opcode) u8 {
        return switch (insn.addr_mode) {
            .implied => 1,
            .immediate, .zero_page, .zero_page_x, .zero_page_y, .indexed_indirect_x, .indirect_indexed_y => 2,
            .absolute, .absolute_x, .absolute_y, .indirect => 3,
        };
    }

    pub fn disassembleOpcode(buffer: []u8, pc: u16, opcode_value: u8, byte2: u8, byte3: u8) ![]const u8 {
        switch (opcode_value) {
            Insn.brk.value => return "BRK",
            Insn.rti.value => return "RTI",
            Insn.rts.value => return "RTS",
            Insn.jsr.value => return std.fmt.bufPrint(buffer, "JSR ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.jmp_abs.value => return std.fmt.bufPrint(buffer, "JMP ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.jmp_ind.value => return std.fmt.bufPrint(
                buffer,
                "JMP (${X:0>4})",
                .{(@as(u16, byte2) | (@as(u16, byte3) << 8))},
            ),

            Insn.beq.value => return std.fmt.bufPrint(buffer, "BEQ ${X:0>4}", .{
                pc +% 2 +% if (byte2 < 128) @as(u16, byte2) else @as(u16, byte2) -% 256,
            }),
            Insn.bne.value => return std.fmt.bufPrint(buffer, "BNE ${X:0>4}", .{
                pc +% 2 +% if (byte2 < 128) @as(u16, byte2) else @as(u16, byte2) -% 256,
            }),
            Insn.bcs.value => return std.fmt.bufPrint(buffer, "BCS ${X:0>4}", .{
                pc +% 2 +% if (byte2 < 128) @as(u16, byte2) else @as(u16, byte2) -% 256,
            }),
            Insn.bcc.value => return std.fmt.bufPrint(buffer, "BCC ${X:0>4}", .{
                pc +% 2 +% if (byte2 < 128) @as(u16, byte2) else @as(u16, byte2) -% 256,
            }),
            Insn.bmi.value => return std.fmt.bufPrint(buffer, "BMI ${X:0>4}", .{
                pc +% 2 +% if (byte2 < 128) @as(u16, byte2) else @as(u16, byte2) -% 256,
            }),
            Insn.bpl.value => return std.fmt.bufPrint(buffer, "BPL ${X:0>4}", .{
                pc +% 2 +% if (byte2 < 128) @as(u16, byte2) else @as(u16, byte2) -% 256,
            }),
            Insn.bvc.value => return std.fmt.bufPrint(buffer, "BVC ${X:0>4}", .{
                pc +% 2 +% if (byte2 < 128) @as(u16, byte2) else @as(u16, byte2) -% 256,
            }),
            Insn.bvs.value => return std.fmt.bufPrint(buffer, "BVS ${X:0>4}", .{
                pc +% 2 +% if (byte2 < 128) @as(u16, byte2) else @as(u16, byte2) -% 256,
            }),

            Insn.lda_imm.value => return std.fmt.bufPrint(buffer, "LDA #${X:0>2}", .{
                byte2,
            }),
            Insn.lda_zp.value => return std.fmt.bufPrint(buffer, "LDA ${X:0>2}", .{
                byte2,
            }),
            Insn.lda_zpx.value => return std.fmt.bufPrint(buffer, "LDA ${X:0>2},X", .{
                byte2,
            }),
            Insn.lda_abs.value => return std.fmt.bufPrint(buffer, "LDA ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.lda_absx.value => return std.fmt.bufPrint(buffer, "LDA ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.lda_absy.value => return std.fmt.bufPrint(buffer, "LDA ${X:0>4},Y", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.lda_indx.value => return std.fmt.bufPrint(buffer, "LDA (${X:0>2},X)", .{
                byte2,
            }),
            Insn.lda_indy.value => return std.fmt.bufPrint(buffer, "LDA (${X:0>2}),Y", .{
                byte2,
            }),
            Insn.ldx_imm.value => return std.fmt.bufPrint(buffer, "LDX #${X:0>2}", .{
                byte2,
            }),
            Insn.ldx_zp.value => return std.fmt.bufPrint(buffer, "LDX ${X:0>2}", .{
                byte2,
            }),
            Insn.ldx_zpy.value => return std.fmt.bufPrint(buffer, "LDX ${X:0>2},Y", .{
                byte2,
            }),
            Insn.ldx_abs.value => return std.fmt.bufPrint(buffer, "LDX ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.ldx_absy.value => return std.fmt.bufPrint(buffer, "LDX ${X:0>4},Y", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.ldy_imm.value => return std.fmt.bufPrint(buffer, "LDY #${X:0>2}", .{
                byte2,
            }),
            Insn.ldy_zp.value => return std.fmt.bufPrint(buffer, "LDY ${X:0>2}", .{
                byte2,
            }),
            Insn.ldy_zpx.value => return std.fmt.bufPrint(buffer, "LDY ${X:0>2},X", .{
                byte2,
            }),
            Insn.ldy_abs.value => return std.fmt.bufPrint(buffer, "LDY ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.ldy_absx.value => return std.fmt.bufPrint(buffer, "LDY ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.sta_zp.value => return std.fmt.bufPrint(buffer, "STA ${X:0>2}", .{
                byte2,
            }),
            Insn.sta_zpx.value => return std.fmt.bufPrint(buffer, "STA ${X:0>2},X", .{
                byte2,
            }),
            Insn.sta_abs.value => return std.fmt.bufPrint(buffer, "STA ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.sta_absx.value => return std.fmt.bufPrint(buffer, "STA ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.sta_absy.value => return std.fmt.bufPrint(buffer, "STA ${X:0>4},Y", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.sta_indx.value => return std.fmt.bufPrint(buffer, "STA (${X:0>2},X)", .{
                byte2,
            }),
            Insn.sta_indy.value => return std.fmt.bufPrint(buffer, "STA (${X:0>2}),Y", .{
                byte2,
            }),
            Insn.stx_zp.value => return std.fmt.bufPrint(buffer, "STX ${X:0>2}", .{
                byte2,
            }),
            Insn.stx_zpy.value => return std.fmt.bufPrint(buffer, "STX ${X:0>2},Y", .{
                byte2,
            }),
            Insn.stx_abs.value => return std.fmt.bufPrint(buffer, "STX ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.sty_zp.value => return std.fmt.bufPrint(buffer, "STY ${X:0>2}", .{
                byte2,
            }),
            Insn.sty_zpx.value => return std.fmt.bufPrint(buffer, "STY ${X:0>2},X", .{
                byte2,
            }),
            Insn.sty_abs.value => return std.fmt.bufPrint(buffer, "STY ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.dec_zp.value => return std.fmt.bufPrint(buffer, "DEC ${X:0>2}", .{
                byte2,
            }),
            Insn.dec_zpx.value => return std.fmt.bufPrint(buffer, "DEC ${X:0>2},X", .{
                byte2,
            }),
            Insn.dec_abs.value => return std.fmt.bufPrint(buffer, "DEC ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.dec_absx.value => return std.fmt.bufPrint(buffer, "DEC ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.inc_zp.value => return std.fmt.bufPrint(buffer, "INC ${X:0>2}", .{
                byte2,
            }),
            Insn.inc_zpx.value => return std.fmt.bufPrint(buffer, "INC ${X:0>2},X", .{
                byte2,
            }),
            Insn.inc_abs.value => return std.fmt.bufPrint(buffer, "INC ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.inc_absx.value => return std.fmt.bufPrint(buffer, "INC ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.nop.value => return "NOP",
            Insn.clc.value => return "CLC",
            Insn.sec.value => return "SEC",
            Insn.cli.value => return "CLI",
            Insn.sei.value => return "SEI",
            Insn.cld.value => return "CLD",
            Insn.sed.value => return "SED",
            Insn.clv.value => return "CLV",
            Insn.adc_imm.value => return std.fmt.bufPrint(buffer, "ADC #${X:0>2}", .{
                byte2,
            }),
            Insn.adc_zp.value => return std.fmt.bufPrint(buffer, "ADC ${X:0>2}", .{
                byte2,
            }),
            Insn.adc_zpx.value => return std.fmt.bufPrint(buffer, "ADC ${X:0>2},X", .{
                byte2,
            }),
            Insn.adc_abs.value => return std.fmt.bufPrint(buffer, "ADC ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.adc_absx.value => return std.fmt.bufPrint(buffer, "ADC ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.adc_absy.value => return std.fmt.bufPrint(buffer, "ADC ${X:0>4},Y", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.adc_indx.value => return std.fmt.bufPrint(buffer, "ADC (${X:0>2},X)", .{
                byte2,
            }),
            Insn.adc_indy.value => return std.fmt.bufPrint(buffer, "ADC (${X:0>2}),Y", .{
                byte2,
            }),
            Insn.sbc_imm.value => return std.fmt.bufPrint(buffer, "SBC #${X:0>2}", .{
                byte2,
            }),
            Insn.sbc_zp.value => return std.fmt.bufPrint(buffer, "SBC ${X:0>2}", .{
                byte2,
            }),
            Insn.sbc_zpx.value => return std.fmt.bufPrint(buffer, "SBC ${X:0>2},X", .{
                byte2,
            }),
            Insn.sbc_abs.value => return std.fmt.bufPrint(buffer, "SBC ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.sbc_absx.value => return std.fmt.bufPrint(buffer, "SBC ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.sbc_absy.value => return std.fmt.bufPrint(buffer, "SBC ${X:0>4},Y", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.sbc_indx.value => return std.fmt.bufPrint(buffer, "SBC (${X:0>2},X)", .{
                byte2,
            }),
            Insn.sbc_indy.value => return std.fmt.bufPrint(buffer, "SBC (${X:0>2}),Y", .{
                byte2,
            }),
            Insn.and_imm.value => return std.fmt.bufPrint(buffer, "AND #${X:0>2}", .{
                byte2,
            }),
            Insn.and_zp.value => return std.fmt.bufPrint(buffer, "AND ${X:0>2}", .{
                byte2,
            }),
            Insn.and_zpx.value => return std.fmt.bufPrint(buffer, "AND ${X:0>2},X", .{
                byte2,
            }),
            Insn.and_abs.value => return std.fmt.bufPrint(buffer, "AND ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.and_absx.value => return std.fmt.bufPrint(buffer, "AND ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.and_absy.value => return std.fmt.bufPrint(buffer, "AND ${X:0>4},Y", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.and_indx.value => return std.fmt.bufPrint(buffer, "AND (${X:0>2},X)", .{
                byte2,
            }),
            Insn.and_indy.value => return std.fmt.bufPrint(buffer, "AND (${X:0>2}),Y", .{
                byte2,
            }),
            Insn.ora_imm.value => return std.fmt.bufPrint(buffer, "ORA #${X:0>2}", .{
                byte2,
            }),
            Insn.ora_zp.value => return std.fmt.bufPrint(buffer, "ORA ${X:0>2}", .{
                byte2,
            }),
            Insn.ora_zpx.value => return std.fmt.bufPrint(buffer, "ORA ${X:0>2},X", .{
                byte2,
            }),
            Insn.ora_abs.value => return std.fmt.bufPrint(buffer, "ORA ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.ora_absx.value => return std.fmt.bufPrint(buffer, "ORA ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.ora_absy.value => return std.fmt.bufPrint(buffer, "ORA ${X:0>4},Y", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.ora_indx.value => return std.fmt.bufPrint(buffer, "ORA (${X:0>2},X)", .{
                byte2,
            }),
            Insn.ora_indy.value => return std.fmt.bufPrint(buffer, "ORA (${X:0>2}),Y", .{
                byte2,
            }),
            Insn.eor_imm.value => return std.fmt.bufPrint(buffer, "EOR #${X:0>2}", .{
                byte2,
            }),
            Insn.eor_zp.value => return std.fmt.bufPrint(buffer, "EOR ${X:0>2}", .{
                byte2,
            }),
            Insn.eor_zpx.value => return std.fmt.bufPrint(buffer, "EOR ${X:0>2},X", .{
                byte2,
            }),
            Insn.eor_abs.value => return std.fmt.bufPrint(buffer, "EOR ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.eor_absx.value => return std.fmt.bufPrint(buffer, "EOR ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.eor_absy.value => return std.fmt.bufPrint(buffer, "EOR ${X:0>4},Y", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.eor_indx.value => return std.fmt.bufPrint(buffer, "EOR (${X:0>2},X)", .{
                byte2,
            }),
            Insn.eor_indy.value => return std.fmt.bufPrint(buffer, "EOR (${X:0>2}),Y", .{
                byte2,
            }),
            Insn.bit_zp.value => return std.fmt.bufPrint(buffer, "BIT ${X:0>2}", .{
                byte2,
            }),
            Insn.bit_abs.value => return std.fmt.bufPrint(buffer, "BIT ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.cmp_imm.value => return std.fmt.bufPrint(buffer, "CMP #${X:0>2}", .{
                byte2,
            }),
            Insn.cmp_zp.value => return std.fmt.bufPrint(buffer, "CMP ${X:0>2}", .{
                byte2,
            }),
            Insn.cmp_zpx.value => return std.fmt.bufPrint(buffer, "CMP ${X:0>2},X", .{
                byte2,
            }),
            Insn.cmp_abs.value => return std.fmt.bufPrint(buffer, "CMP ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.cmp_absx.value => return std.fmt.bufPrint(buffer, "CMP ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.cmp_absy.value => return std.fmt.bufPrint(buffer, "CMP ${X:0>4},Y", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.cmp_indx.value => return std.fmt.bufPrint(buffer, "CMP (${X:0>2},X)", .{
                byte2,
            }),
            Insn.cmp_indy.value => return std.fmt.bufPrint(buffer, "CMP (${X:0>2}),Y", .{
                byte2,
            }),
            Insn.cpx_imm.value => return std.fmt.bufPrint(buffer, "CPX #${X:0>2}", .{
                byte2,
            }),
            Insn.cpx_zp.value => return std.fmt.bufPrint(buffer, "CPX ${X:0>2}", .{
                byte2,
            }),
            Insn.cpx_abs.value => return std.fmt.bufPrint(buffer, "CPX ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.cpy_imm.value => return std.fmt.bufPrint(buffer, "CPY #${X:0>2}", .{
                byte2,
            }),
            Insn.cpy_zp.value => return std.fmt.bufPrint(buffer, "CPY ${X:0>2}", .{
                byte2,
            }),
            Insn.cpy_abs.value => return std.fmt.bufPrint(buffer, "CPY ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.asl_a.value => return "ASL A",
            Insn.asl_zp.value => return std.fmt.bufPrint(buffer, "ASL ${X:0>2}", .{
                byte2,
            }),
            Insn.asl_zpx.value => return std.fmt.bufPrint(buffer, "ASL ${X:0>2},X", .{
                byte2,
            }),
            Insn.asl_abs.value => return std.fmt.bufPrint(buffer, "ASL ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.asl_absx.value => return std.fmt.bufPrint(buffer, "ASL ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.lsr_a.value => return "LSR A",
            Insn.lsr_zp.value => return std.fmt.bufPrint(buffer, "LSR ${X:0>2}", .{
                byte2,
            }),
            Insn.lsr_zpx.value => return std.fmt.bufPrint(buffer, "LSR ${X:0>2},X", .{
                byte2,
            }),
            Insn.lsr_abs.value => return std.fmt.bufPrint(buffer, "LSR ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.lsr_absx.value => return std.fmt.bufPrint(buffer, "LSR ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.rol_a.value => return "ROL A",
            Insn.rol_zp.value => return std.fmt.bufPrint(buffer, "ROL ${X:0>2}", .{
                byte2,
            }),
            Insn.rol_zpx.value => return std.fmt.bufPrint(buffer, "ROL ${X:0>2},X", .{
                byte2,
            }),
            Insn.rol_abs.value => return std.fmt.bufPrint(buffer, "ROL ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.rol_absx.value => return std.fmt.bufPrint(buffer, "ROL ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.ror_a.value => return "ROR A",
            Insn.ror_zp.value => return std.fmt.bufPrint(buffer, "ROR ${X:0>2}", .{
                byte2,
            }),
            Insn.ror_zpx.value => return std.fmt.bufPrint(buffer, "ROR ${X:0>2},X", .{
                byte2,
            }),
            Insn.ror_abs.value => return std.fmt.bufPrint(buffer, "ROR ${X:0>4}", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.ror_absx.value => return std.fmt.bufPrint(buffer, "ROR ${X:0>4},X", .{
                (@as(u16, byte2) | (@as(u16, byte3) << 8)),
            }),
            Insn.pha.value => return "PHA",
            Insn.pla.value => return "PLA",
            Insn.php.value => return "PHP",
            Insn.plp.value => return "PLP",
            Insn.tax.value => return "TAX",
            Insn.tay.value => return "TAY",
            Insn.txa.value => return "TXA",
            Insn.tya.value => return "TYA",
            Insn.tsx.value => return "TSX",
            Insn.txs.value => return "TXS",
            Insn.dex.value => return "DEX",
            Insn.dey.value => return "DEY",
            Insn.inx.value => return "INX",
            Insn.iny.value => return "INY",
            else => return "???",
        }
    }
};
