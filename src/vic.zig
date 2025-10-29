const std = @import("std");

const Ram64k = @import("mem.zig");
const Cpu = @import("cpu.zig");

pub const Vic = @This();

model: Model,
vsync_happened: bool,
hsync_happened: bool,
badline_happened: bool,
rasterline_changed: bool,
rasterline: u16,
frame_ctr: usize,
cycles_since_vsync: u16,
cycles_since_hsync: u8,
mem: *Ram64k,
cpu: *Cpu,
dbg_enabled: bool,

pub const Model = enum {
    pal,
    ntsc,
};

pub const Timing = struct {
    pub const cyclesVsyncPal = 19656; // 63 cycles x 312 rasterlines
    pub const cyclesVsyncNtsc = 17030;
    pub const cyclesRasterlinePal = 63;
    pub const cyclesRasterlineNtsc = 65;
    pub const cyclesBadlineStealing = 40; // cycles vic steals cpu on badline
};

pub fn init(cpu: *Cpu, mem: *Ram64k, vic_model: Model) Vic {
    const vic = Vic{
        .model = vic_model,
        .vsync_happened = true,
        .hsync_happened = true,
        .badline_happened = false,
        .rasterline_changed = false,
        .rasterline = 0,
        .frame_ctr = 0,
        .cycles_since_hsync = 0,
        .cycles_since_vsync = 0,
        .cpu = cpu,
        .mem = mem,
        .dbg_enabled = false,
    };

    return vic;
}

pub fn emulateD012(vic: *Vic) u8 {
    vic.rasterline += 1;
    vic.rasterline_changed = true;
    vic.hsync_happened = true;

    var rv: u8 = 0;

    vic.mem.data[0xD012] = vic.mem.data[0xD012] +% 1;
    if ((vic.mem.data[0xD012] == 0) or
        (((vic.mem.data[0xD011] & 0x80) != 0) and
            (vic.mem.data[0xD012] >= 0x38)))
    {
        vic.mem.data[0xD011] ^= 0x80;
        vic.mem.data[0xD012] = 0x00;
        vic.rasterline = 0;
        vic.vsync_happened = true;
    }

    // check badline
    if (vic.rasterline % 8 == 3) {
        vic.badline_happened = true;
        vic.cycles_since_hsync += Timing.cyclesBadlineStealing;
        vic.cycles_since_vsync += Timing.cyclesBadlineStealing;
        rv = Timing.cyclesBadlineStealing;
    }

    return rv;
}

pub fn emulate(vic: *Vic, cycles_last_step: u8) u8 {
    vic.cycles_since_vsync += cycles_last_step;
    vic.cycles_since_hsync += cycles_last_step;

    var rv: u8 = 0;

    // VIC vertical sync
    if (vic.model == .pal and
        vic.cycles_since_vsync >= Timing.cyclesVsyncPal)
    {
        vic.frame_ctr += 1;
        vic.cycles_since_vsync = 0;
    }

    if (vic.model == Vic.Model.ntsc and
        vic.cycles_since_vsync >= Timing.cyclesVsyncNtsc)
    {
        vic.frame_ctr += 1;
        vic.cycles_since_vsync = 0;
    }

    // VIC horizontal sync
    if (vic.model == Vic.Model.pal and
        vic.cycles_since_hsync >= Timing.cyclesRasterlinePal)
    {
        rv = vic.emulateD012();
        vic.cycles_since_hsync = 0;
    }

    if (vic.model == Vic.Model.ntsc and
        vic.cycles_since_hsync >= Timing.cyclesRasterlineNtsc)
    {
        rv = vic.emulateD012();
        vic.cycles_since_hsync = 0;
    }

    return rv;
}

pub fn printStatus(vic: *Vic) void {
    std.debug.print(
        "[vic] RL: {X:0>4} | VSYNC: {} | HSYNC: {} | BL: {} | RL-CHG: {} | FRM: {d}\n",
        .{
            vic.rasterline,
            vic.vsync_happened,
            vic.hsync_happened,
            vic.badline_happened,
            vic.rasterline_changed,
            vic.frame_ctr,
        },
    );
}
