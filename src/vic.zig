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
