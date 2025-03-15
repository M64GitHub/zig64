const std = @import("std");
const stdout = std.io.getStdOut().writer();

const C64 = @This();

cpu: Cpu,
mem: Ram64k,
vic: Vic,
sid: Sid,
resid: ?*opaque {}, // optional resid integration
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

    if (c64.vic.model == Vic.Model.pal) cycles_max = Vic.Timing.cyclesVsyncPal;
    if (c64.vic.model == Vic.Model.ntsc) cycles_max = Vic.Timing.cyclesVsyncNtsc;

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
        stdout.print("[vic] RL {X:0>4} | VSYNC: {} | HSYNC: {} | BL: {} | RL-CHG: {} | FRM: {d}", .{
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
    sid_reg_written: bool,
    ext_sid_reg_written: bool,
    c64: *C64,

    const CpuFlags = struct {
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
            .sid_reg_written = false,
            .ext_sid_reg_written = false,
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
        stdout.print("[cpu] PC: {X:0>4} | A: {X:0>2} | X: {X:0>2} | Y: {X:0>2} | Last Opc: {X:0>2} | Last Cycl: {d} | Cycl-TT: {d} | ", .{
            cpu.pc,
            cpu.a,
            cpu.x,
            cpu.y,
            cpu.opcode_last,
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
        cpu.cycles_executed +%= 1;
        return cpu.c64.mem.data[addr];
    }

    pub fn readWord(cpu: *Cpu, addr: u16) u16 {
        const LoByte: u8 = cpu.readByte(addr);
        const HiByte: u8 = cpu.readByte(addr + 1);
        return @as(u16, LoByte) | (@as(u16, HiByte) << 8);
    }

    pub fn writeByte(cpu: *Cpu, val: u8, addr: u16) void {
        const sid_base = cpu.c64.sid.base_address;
        if ((addr >= sid_base) and (addr <= (sid_base + 25))) {
            cpu.sid_reg_written = true;
            // ext flag only when value changed
            if (cpu.c64.mem.data[addr] != val) {
                cpu.c64.sid.registers[addr - sid_base] = val;
                cpu.ext_sid_reg_written = true;
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
        cpu.flags.unused = @intFromBool((cpu.status & @intFromEnum(Cpu.FlagBit.unused)) != 0);
        cpu.flags.c = @intFromBool((cpu.status & @intFromEnum(Cpu.FlagBit.carry)) != 0);
        cpu.flags.z = @intFromBool((cpu.status & @intFromEnum(Cpu.FlagBit.zero)) != 0);
        cpu.flags.i = @intFromBool((cpu.status & @intFromEnum(Cpu.FlagBit.intDisable)) != 0);
        cpu.flags.d = @intFromBool((cpu.status & @intFromEnum(Cpu.FlagBit.decimal)) != 0);
        cpu.flags.b = @intFromBool((cpu.status & @intFromEnum(Cpu.FlagBit.brk)) != 0);
        cpu.flags.v = @intFromBool((cpu.status & @intFromEnum(Cpu.FlagBit.overflow)) != 0);
        cpu.flags.n = @intFromBool((cpu.status & @intFromEnum(Cpu.FlagBit.negative)) != 0);
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

    fn pushW(cpu: *Cpu, val: u16) void {
        cpu.writeByte(@truncate(val >> 8), spToAddr(cpu));
        cpu.sp -%= 1;
        cpu.writeByte(@truncate(val & 0xff), spToAddr(cpu));
        cpu.sp -%= 1;
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

    fn popW(cpu: *Cpu) u16 {
        const val_stack: u16 = cpu.readWord(spToAddr(cpu) + 1);
        cpu.sp +%= 2;
        cpu.cycles_executed +%= 1;
        return val_stack;
    }

    fn updateFlags(cpu: *Cpu, reg: u8) void {
        cpu.flags.z = 0;
        if (reg == 0) cpu.flags.z = 1;
        cpu.flags.n = 0;
        if ((reg & @intFromEnum(Cpu.FlagBit.negative)) != 0) cpu.flags.n = 1;
    }

    fn loadReg(cpu: *Cpu, addr: u16, reg: *u8) void {
        reg.* = cpu.readByte(addr);
        cpu.updateFlags(reg.*);
    }

    fn bitAnd(cpu: *Cpu, addr: u16) void {
        cpu.a &= cpu.readByte(addr);
        cpu.updateFlags(cpu.a);
    }

    fn bitOra(cpu: *Cpu, addr: u16) void {
        cpu.a |= cpu.readByte(addr);
        cpu.updateFlags(cpu.a);
    }

    fn bitXor(cpu: *Cpu, addr: u16) void {
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

    pub fn sbc(cpu: *Cpu, op: u8) void {
        const old_sign: bool = (cpu.a &
            @as(u8, @intFromEnum(Cpu.FlagBit.negative))) != 0;

        const result: i16 =
            @as(i16, cpu.a) -
            @as(i16, op) -
            @as(i16, 1 - cpu.flags.c);

        if (cpu.a > op) cpu.flags.c = 1;
        cpu.a = @as(u8, @truncate(@as(u16, @bitCast(result & 0xFF))));

        const new_sign: bool = (cpu.a &
            @as(u8, @intFromEnum(Cpu.FlagBit.negative))) != 0;

        cpu.flags.v = @intFromBool(old_sign != new_sign);

        cpu.updateFlags(cpu.a);
    }

    fn asl(cpu: *Cpu, op: u8) u8 {
        cpu.flags.c = @as(u1, @intFromBool(op &
            @intFromEnum(Cpu.FlagBit.negative) > 0));
        const res: u8 = op << 1;
        cpu.updateFlags(res);
        cpu.cycles_executed +%= 1;
        return res;
    }

    fn lsr(cpu: *Cpu, op: u8) u8 {
        cpu.flags.c = @as(u1, @intFromBool(op &
            @intFromEnum(Cpu.FlagBit.carry) > 0));
        const res: u8 = op >> 1;
        cpu.updateFlags(res);
        cpu.cycles_executed +%= 1;
        return res;
    }

    fn rol(cpu: *Cpu, op: u8) u8 {
        const old_carry: u8 = cpu.flags.c;
        cpu.flags.c = @intFromBool((op &
            @intFromEnum(Cpu.FlagBit.negative)) != 0); // Store bit 7 in carry flag
        const res: u8 = (op << 1) | old_carry; // Rotate left, inserting old carry
        cpu.updateFlags(res);
        cpu.cycles_executed +%= 1;
        return res;
    }

    fn ror(cpu: *Cpu, op: u8) u8 {
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
        const abs_addr_x: u16 = abs_addr + cpu.x;
        const pg_boundary: u16 = (abs_addr ^ abs_addr_x) >> 8;
        if (pg_boundary != 0) {
            cpu.cycles_executed +%= 1;
        }
        return abs_addr_x;
    }

    fn addrAbsX5(cpu: *Cpu) u16 {
        const abs_addr: u16 = fetchWord(cpu);
        const abs_addr_x: u16 = abs_addr + cpu.x;
        cpu.cycles_executed +%= 1;
        return abs_addr_x;
    }

    fn addrAbsY(cpu: *Cpu) u16 {
        const abs_addr: u16 = fetchWord(cpu);
        const abs_addr_y: u16 = abs_addr + cpu.y;
        const pg_boundary: u16 = (abs_addr ^ abs_addr_y) >> 8;
        if (pg_boundary != 0) {
            cpu.cycles_executed +%= 1;
        }
        return abs_addr_y;
    }

    fn addrAbsY5(cpu: *Cpu) u16 {
        const abs_addr: u16 = fetchWord(cpu);
        const abs_addr_y: u16 = abs_addr + cpu.y;
        cpu.cycles_executed +%= 1;
        return abs_addr_y;
    }

    fn addrIndX(cpu: *Cpu) u16 {
        var zp_addr: u8 = fetchUByte(cpu);
        zp_addr +%= cpu.x;
        cpu.cycles_executed +%= 1;
        const eff_addr: u16 = cpu.readWord(zp_addr);
        return eff_addr;
    }

    fn addrIndY(cpu: *Cpu) u16 {
        const zp_addr: u8 = fetchUByte(cpu);
        const eff_addr: u16 = cpu.readWord(zp_addr);
        const eff_addr_y: u16 = eff_addr + cpu.y;
        const pg_boundary: u16 = (eff_addr ^ eff_addr_y) >> 8;
        if (pg_boundary != 0) {
            cpu.cycles_executed +%= 1;
        }
        return eff_addr_y;
    }

    fn addrIndY6(cpu: *Cpu) u16 {
        const zp_addr: u8 = fetchUByte(cpu);
        const eff_addr: u16 = cpu.readWord(zp_addr);
        const eff_addr_y: u16 = eff_addr + cpu.y;
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
        cpu.c64.vic.vsync_happened = false;
        cpu.c64.vic.hsync_happened = false;
        cpu.c64.vic.badline_happened = false;
        cpu.c64.vic.rasterline_changed = false;

        const cycles_now: u32 = cpu.cycles_executed;
        const old_pc = cpu.pc;
        const opcode: u8 = fetchUByte(cpu);
        cpu.opcode_last = opcode;

        if (cpu.c64.cpu_dbg_enabled)
            stdout.print("[cpu] runStep: {X:0>4}, opcode: {X:0>2}\n", .{
                old_pc,
                opcode,
            }) catch {};

        switch (opcode) {
            0x29 => {
                cpu.a &= fetchUByte(cpu);
                cpu.updateFlags(cpu.a);
            },
            0x9 => {
                cpu.a |= fetchUByte(cpu);
                cpu.updateFlags(cpu.a);
            },
            0x49 => {
                cpu.a ^= fetchUByte(cpu);
                cpu.updateFlags(cpu.a);
            },
            0x25 => {
                const addr: u16 = addrZp(cpu);
                cpu.bitAnd(addr);
            },
            0x5 => {
                const addr: u16 = addrZp(cpu);
                cpu.bitOra(addr);
            },
            0x45 => {
                const addr: u16 = addrZp(cpu);
                cpu.bitXor(addr);
            },
            0x35 => {
                const addr: u16 = addrZpX(cpu);
                cpu.bitAnd(addr);
            },
            0x15 => {
                const addr: u16 = addrZpX(cpu);
                cpu.bitOra(addr);
            },
            0x55 => {
                const addr: u16 = addrZpX(cpu);
                cpu.bitXor(addr);
            },
            0x2D => {
                const addr: u16 = addrAbs(cpu);
                cpu.bitAnd(addr);
            },
            0xD => {
                const addr: u16 = addrAbs(cpu);
                cpu.bitOra(addr);
            },
            0x4D => {
                const addr: u16 = addrAbs(cpu);
                cpu.bitXor(addr);
            },
            0x3D => {
                const addr: u16 = addrAbsX(cpu);
                cpu.bitAnd(addr);
            },
            0x1D => {
                const addr: u16 = addrAbsX(cpu);
                cpu.bitOra(addr);
            },
            0x5D => {
                const addr: u16 = addrAbsX(cpu);
                cpu.bitXor(addr);
            },
            0x39 => {
                const addr: u16 = addrAbsY(cpu);
                cpu.bitAnd(addr);
            },
            0x19 => {
                const addr: u16 = addrAbsY(cpu);
                cpu.bitOra(addr);
            },
            0x59 => {
                const addr: u16 = addrAbsY(cpu);
                cpu.bitXor(addr);
            },
            0x21 => {
                const addr: u16 = addrIndX(cpu);
                cpu.bitAnd(addr);
            },
            0x1 => {
                const addr: u16 = addrIndX(cpu);
                cpu.bitOra(addr);
            },
            0x41 => {
                const addr: u16 = addrIndX(cpu);
                cpu.bitXor(addr);
            },
            0x31 => {
                const addr: u16 = addrIndY(cpu);
                cpu.bitAnd(addr);
            },
            0x11 => {
                const addr: u16 = addrIndY(cpu);
                cpu.bitOra(addr);
            },
            0x51 => {
                const addr: u16 = addrIndY(cpu);
                cpu.bitXor(addr);
            },
            0x24 => {
                const addr: u16 = addrZp(cpu);
                const val: u8 = cpu.readByte(addr);
                cpu.flags.z = @intFromBool(!((cpu.a & val) != 0));
                cpu.flags.n = @intFromBool((val & 128) != 0);
                cpu.flags.v = @intFromBool((val & 64) != 0);
            },
            0x2C => {
                const addr: u16 = addrAbs(cpu);
                const val: u8 = cpu.readByte(addr);
                cpu.flags.z = @intFromBool(!((cpu.a & val) != 0));
                cpu.flags.n = @intFromBool((val & 128) != 0);
                cpu.flags.v = @intFromBool((val & 64) != 0);
            },
            0xA9 => {
                cpu.a = fetchUByte(cpu);
                cpu.updateFlags(cpu.a);
            },
            0xA2 => {
                cpu.x = fetchUByte(cpu);
                cpu.updateFlags(cpu.x);
            },
            0xA0 => {
                cpu.y = fetchUByte(cpu);
                cpu.updateFlags(cpu.y);
            },
            0xA5 => {
                const addr: u16 = addrZp(cpu);
                cpu.loadReg(addr, &cpu.a);
            },
            0xA6 => {
                const addr: u16 = addrZp(cpu);
                cpu.loadReg(addr, &cpu.x);
            },
            0xB6 => {
                const addr: u16 = addrZpY(cpu);
                cpu.loadReg(addr, &cpu.x);
            },
            0xA4 => {
                const addr: u16 = addrZp(cpu);
                cpu.loadReg(addr, &cpu.y);
            },
            0xB5 => {
                const addr: u16 = addrZpX(cpu);
                cpu.loadReg(addr, &cpu.a);
            },
            0xB4 => {
                const addr: u16 = addrZpX(cpu);
                cpu.loadReg(addr, &cpu.y);
            },
            0xAD => {
                const addr: u16 = addrAbs(cpu);
                cpu.loadReg(addr, &cpu.a);
            },
            0xAE => {
                const addr: u16 = addrAbs(cpu);
                cpu.loadReg(addr, &cpu.x);
            },
            0xAC => {
                const addr: u16 = addrAbs(cpu);
                cpu.loadReg(addr, &cpu.y);
            },
            0xBD => {
                const addr: u16 = addrAbsX(cpu);
                cpu.loadReg(addr, &cpu.a);
            },
            0xBC => {
                const addr: u16 = addrAbsX(cpu);
                cpu.loadReg(addr, &cpu.y);
            },
            0xB9 => {
                const addr: u16 = addrAbsY(cpu);
                cpu.loadReg(addr, &cpu.a);
            },
            0xBE => {
                const addr: u16 = addrAbsY(cpu);
                cpu.loadReg(addr, &cpu.x);
            },
            0xA1 => {
                const addr: u16 = addrIndX(cpu);
                cpu.loadReg(addr, &cpu.a);
            },
            0x81 => {
                const addr: u16 = addrIndX(cpu);
                cpu.writeByte(cpu.a, addr);
            },
            0xB1 => {
                const addr: u16 = addrIndY(cpu);
                cpu.loadReg(addr, &cpu.a);
            },
            0x91 => {
                const addr: u16 = addrIndY6(cpu);
                cpu.writeByte(cpu.a, addr);
            },
            0x85 => {
                const addr: u16 = addrZp(cpu);
                cpu.writeByte(cpu.a, addr);
            },
            0x86 => {
                const addr: u16 = addrZp(cpu);
                cpu.writeByte(cpu.x, addr);
            },
            0x96 => {
                const addr: u16 = addrZpY(cpu);
                cpu.writeByte(cpu.x, addr);
            },
            0x84 => {
                const addr: u16 = addrZp(cpu);
                cpu.writeByte(cpu.y, addr);
            },
            0x8D => {
                const addr: u16 = addrAbs(cpu);
                cpu.writeByte(cpu.a, addr);
            },
            0x8E => {
                const addr: u16 = addrAbs(cpu);
                cpu.writeByte(cpu.x, addr);
            },
            0x8C => {
                const addr: u16 = addrAbs(cpu);
                cpu.writeByte(cpu.y, addr);
            },
            0x95 => {
                const addr: u16 = addrZpX(cpu);
                cpu.writeByte(cpu.a, addr);
            },
            0x94 => {
                const addr: u16 = addrZpX(cpu);
                cpu.writeByte(cpu.y, addr);
            },
            0x9D => {
                const addr: u16 = addrAbsX5(cpu);
                cpu.writeByte(cpu.a, addr);
            },
            0x99 => {
                const addr: u16 = addrAbsY5(cpu);
                cpu.writeByte(cpu.a, addr);
            },
            0x20 => {
                const jsr_addr: u16 = fetchWord(cpu);
                const ret_addr: u16 = cpu.pc - 1;
                cpu.pushW(cpu.pc - 1);
                cpu.pc = jsr_addr;
                cpu.cycles_executed +%= 1;
                if (cpu.c64.cpu_dbg_enabled) {
                    stdout.print("[cpu] Calling {X:0>4}, return to {X:0>4}\n", .{
                        jsr_addr,
                        ret_addr,
                    }) catch {};
                }
            },
            0x60 => {
                const ret_addr: u16 = popW(cpu);
                cpu.pc = ret_addr + 1;
                cpu.cycles_executed +%= 2;
                if (cpu.c64.cpu_dbg_enabled) {
                    stdout.print("[cpu] Return to {X:0>4}\n", .{
                        ret_addr,
                    }) catch {};
                }
                if (ret_addr == 0x0000) {
                    if (cpu.c64.cpu_dbg_enabled) {
                        stdout.print("[cpu] Return EXIT!\n", .{}) catch {};
                    }
                    cpu.cycles_last_step =
                        @as(u8, @truncate(cpu.cycles_executed -% cycles_now));

                    // skip vic timing on exit

                    return 0;
                }
            },
            0x4C => {
                const addr: u16 = addrAbs(cpu);
                cpu.pc = addr;
            },
            0x6C => {
                var addr: u16 = addrAbs(cpu);
                addr = cpu.readWord(addr);
                cpu.pc = addr;
            },
            0xBA => {
                cpu.x = cpu.sp;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.x);
            },
            0x9A => {
                cpu.sp = cpu.x;
                cpu.cycles_executed +%= 1;
            },
            0x48 => {
                cpu.pushB(cpu.a);
            },
            0x68 => {
                cpu.a = popB(cpu);
                cpu.updateFlags(cpu.a);
                cpu.cycles_executed +%= 1;
            },
            0x8 => {
                pushPs(cpu);
            },
            0x28 => {
                popPs(cpu);
                cpu.cycles_executed +%= 1;
            },
            0xAA => {
                cpu.x = cpu.a;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.x);
            },
            0xA8 => {
                cpu.y = cpu.a;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.y);
            },
            0x8A => {
                cpu.a = cpu.x;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.a);
            },
            0x98 => {
                cpu.a = cpu.y;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.a);
            },
            0xE8 => {
                cpu.x +%= 1;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.x);
            },
            0xC8 => {
                cpu.y +%= 1;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.y);
            },
            0xCA => {
                cpu.x -%= 1;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.x);
            },
            0x88 => {
                cpu.y -%= 1;
                cpu.cycles_executed +%= 1;
                cpu.updateFlags(cpu.y);
            },
            0xC6 => {
                const addr: u16 = addrZp(cpu);
                var val: u8 = cpu.readByte(addr);
                val -%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            0xD6 => {
                const addr: u16 = addrZpX(cpu);
                var val: u8 = cpu.readByte(addr);
                val -%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            0xCE => {
                const addr: u16 = addrAbs(cpu);
                var val: u8 = cpu.readByte(addr);
                val -%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            0xDE => {
                const addr: u16 = addrAbsX5(cpu);
                var val: u8 = cpu.readByte(addr);
                val -%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            0xE6 => {
                const addr: u16 = addrZp(cpu);
                var val: u8 = cpu.readByte(addr);
                val +%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            0xF6 => {
                const addr: u16 = addrZpX(cpu);
                var val: u8 = cpu.readByte(addr);
                val +%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            0xEE => {
                const addr: u16 = addrAbs(cpu);
                var val: u8 = cpu.readByte(addr);
                val +%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            0xFE => {
                const addr: u16 = addrAbsX5(cpu);
                var val: u8 = cpu.readByte(addr);
                val +%= 1;
                cpu.cycles_executed +%= 1;
                cpu.writeByte(val, addr);
                cpu.updateFlags(val);
            },
            0xF0 => {
                cpu.branch(@as(u8, cpu.flags.z), 1);
            },
            0xD0 => {
                cpu.branch(@as(u8, cpu.flags.z), 0);
            },
            0xB0 => {
                cpu.branch(@as(u8, cpu.flags.c), 1);
            },
            0x90 => {
                cpu.branch(@as(u8, cpu.flags.c), 0);
            },
            0x30 => {
                cpu.branch(@as(u8, cpu.flags.n), 1);
            },
            0x10 => {
                cpu.branch(@as(u8, cpu.flags.n), 0);
            },
            0x50 => {
                cpu.branch(@as(u8, cpu.flags.v), 0);
            },
            0x70 => {
                cpu.branch(@as(u8, cpu.flags.v), 1);
            },
            0x18 => {
                cpu.flags.c = 0;
                cpu.cycles_executed +%= 1;
            },
            0x38 => {
                cpu.flags.c = 1;
                cpu.cycles_executed +%= 1;
            },
            0xD8 => {
                cpu.flags.d = 0;
                cpu.cycles_executed +%= 1;
            },
            0xF8 => {
                cpu.flags.d = 1;
                cpu.cycles_executed +%= 1;
            },
            0x58 => {
                cpu.flags.i = 0;
                cpu.cycles_executed +%= 1;
            },
            0x78 => {
                cpu.flags.i = 1;
                cpu.cycles_executed +%= 1;
            },
            0xB8 => {
                cpu.flags.v = 0;
                cpu.cycles_executed +%= 1;
            },
            0xEA => {
                cpu.cycles_executed +%= 1;
            },
            0x6D => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.adc(op);
            },
            0x7D => {
                const addr: u16 = addrAbsX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.adc(op);
            },
            0x79 => {
                const addr: u16 = addrAbsY(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.adc(op);
            },
            0x65 => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.adc(op);
            },
            0x75 => {
                const addr: u16 = addrZpX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.adc(op);
            },
            0x61 => {
                const addr: u16 = addrIndX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.adc(op);
            },
            0x71 => {
                const addr: u16 = addrIndY(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.adc(op);
            },
            0x69 => {
                const op: u8 = fetchUByte(cpu);
                cpu.adc(op);
            },
            0xE9 => {
                const op: u8 = fetchUByte(cpu);
                cpu.sbc(op);
            },
            0xED => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.sbc(op);
            },
            0xE5 => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.sbc(op);
            },
            0xF5 => {
                const addr: u16 = addrZpX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.sbc(op);
            },
            0xFD => {
                const addr: u16 = addrAbsX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.sbc(op);
            },
            0xF9 => {
                const addr: u16 = addrAbsY(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.sbc(op);
            },
            0xE1 => {
                const addr: u16 = addrIndX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.sbc(op);
            },
            0xF1 => {
                const addr: u16 = addrIndY(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.sbc(op);
            },
            0xE0 => {
                const op: u8 = fetchUByte(cpu);
                cpu.cmpReg(op, cpu.x);
            },
            0xC0 => {
                const op: u8 = fetchUByte(cpu);
                cpu.cmpReg(op, cpu.y);
            },
            0xE4 => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.x);
            },
            0xC4 => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.y);
            },
            0xEC => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.x);
            },
            0xCC => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.y);
            },
            0xC9 => {
                const op: u8 = fetchUByte(cpu);
                cpu.cmpReg(op, cpu.a);
            },
            0xC5 => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.a);
            },
            0xD5 => {
                const addr: u16 = addrZpX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.a);
            },
            0xCD => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.a);
            },
            0xDD => {
                const addr: u16 = addrAbsX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.a);
            },
            0xD9 => {
                const addr: u16 = addrAbsY(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.a);
            },
            0xC1 => {
                const addr: u16 = addrIndX(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.a);
            },
            0xD1 => {
                const addr: u16 = addrIndY(cpu);
                const op: u8 = cpu.readByte(addr);
                cpu.cmpReg(op, cpu.a);
            },
            0xA => {
                cpu.a = cpu.asl(cpu.a);
            },
            0x6 => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.asl(op);
                cpu.writeByte(res, addr);
            },
            0x16 => {
                const addr: u16 = addrZpX(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.asl(op);
                cpu.writeByte(res, addr);
            },
            0xE => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.asl(op);
                cpu.writeByte(res, addr);
            },
            0x1E => {
                const addr: u16 = addrAbsX5(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.asl(op);
                cpu.writeByte(res, addr);
            },
            0x4A => {
                cpu.a = cpu.lsr(cpu.a);
            },
            0x46 => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.lsr(op);
                cpu.writeByte(res, addr);
            },
            0x56 => {
                const addr: u16 = addrZpX(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.lsr(op);
                cpu.writeByte(res, addr);
            },
            0x4E => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.lsr(op);
                cpu.writeByte(res, addr);
            },
            0x5E => {
                const addr: u16 = addrAbsX5(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.lsr(op);
                cpu.writeByte(res, addr);
            },
            0x2A => {
                cpu.a = cpu.rol(cpu.a);
            },
            0x26 => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.rol(op);
                cpu.writeByte(res, addr);
            },
            0x36 => {
                const addr: u16 = addrZpX(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.rol(op);
                cpu.writeByte(res, addr);
            },
            0x2E => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.rol(op);
                cpu.writeByte(res, addr);
            },
            0x3E => {
                const addr: u16 = addrAbsX5(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.rol(op);
                cpu.writeByte(res, addr);
            },
            0x6A => {
                cpu.a = cpu.ror(cpu.a);
            },
            0x66 => {
                const addr: u16 = addrZp(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.ror(op);
                cpu.writeByte(res, addr);
            },
            0x76 => {
                const addr: u16 = addrZpX(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.ror(op);
                cpu.writeByte(res, addr);
            },
            0x6E => {
                const addr: u16 = addrAbs(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.ror(op);
                cpu.writeByte(res, addr);
            },
            0x7E => {
                const addr: u16 = addrAbsX5(cpu);
                const op: u8 = cpu.readByte(addr);
                const res: u8 = cpu.ror(op);
                cpu.writeByte(res, addr);
            },
            0x0 => {
                cpu.pushW(cpu.pc + 1);
                pushPs(cpu);
                cpu.pc = cpu.readWord(65534);
                cpu.flags.b = 1;
                cpu.flags.i = 1;
                return 0;
            },
            0x40 => {
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

        // dbg output
        if (cpu.c64.cpu_dbg_enabled) {
            cpu.printStatus();
        }

        if (cpu.c64.vic_dbg_enabled) {
            cpu.c64.vic.printStatus();
        }

        if (cpu.c64.sid_dbg_enabled and cpu.sid_reg_written) {
            cpu.c64.sid.printRegisters();
        }

        return cpu.cycles_last_step;
    }
};
