pub const version = "0.5.0";
const std = @import("std");

pub const Cpu = @import("cpu.zig");
pub const Ram64k = @import("mem.zig");
pub const Sid = @import("sid.zig");
pub const Vic = @import("vic.zig");
pub const Asm = @import("asm.zig");

pub const C64 = @This();

cpu: Cpu,
mem: Ram64k,
vic: Vic,
sid: Sid,
resid: ?*opaque {}, // optional resid integration  TODO: tbd
dbg_enabled: bool,

pub fn init(
    allocator: std.mem.Allocator,
    vic_model: Vic.Model,
    init_addr: u16,
) !*C64 {
    var c64 = try allocator.create(C64);

    c64.mem = Ram64k.init();
    c64.cpu = Cpu.init(&c64.mem, &c64.sid, &c64.vic, init_addr);
    c64.vic = Vic.init(&c64.cpu, &c64.mem, vic_model);
    c64.sid = Sid.init(Sid.std_base);
    c64.resid = null;
    c64.dbg_enabled = false;

    // default startup value: BASIC ROM, KERNAL ROM, and I/O
    c64.mem.data[0x01] = 0x37;
    return c64;
}

pub fn deinit(c64: *C64, allocator: std.mem.Allocator) void {
    allocator.destroy(c64);
}

pub fn call(c64: *C64, address: u16) void {
    c64.cpu.status = 0x00;
    c64.cpu.psToFlags();
    c64.cpu.sp = 0xFF;

    c64.sid.ext_reg_written = false;
    c64.cpu.pc = address;
    if (c64.dbg_enabled) {
        std.debug.print("[c64] calling address: {X:0>4}\n", .{
            address,
        });
    }
    while (c64.cpu.runStep() != 0) {}
    c64.sid.reg_written = c64.sid.ext_reg_written;
    c64.sid.reg_changed = c64.sid.ext_reg_changed;
}

pub fn callSidTrace(
    c64: *C64,
    address: u16,
    allocator: std.mem.Allocator,
) ![]Sid.RegisterChange {
    c64.cpu.status = 0x00;
    c64.cpu.psToFlags();
    c64.cpu.sp = 0xFF;

    c64.sid.ext_reg_written = false;
    c64.cpu.pc = address;

    if (c64.dbg_enabled) {
        std.debug.print("[c64] tracing SID from address: {X:0>4}\n", .{address});
    }

    // ArrayList to collect RegisterChange instances
    var changes = std.ArrayList(Sid.RegisterChange){};
    defer changes.deinit(allocator); // Frees the list memory, not the items

    // Run the program, collecting SID changes
    while (c64.cpu.runStep() != 0) {
        if (c64.sid.last_change) |change| {
            try changes.append(allocator, change); // Add the change to the array
        }
    }

    c64.sid.reg_written = c64.sid.ext_reg_written;
    c64.sid.reg_changed = c64.sid.ext_reg_changed;

    // Return the owned slice of changes
    return changes.toOwnedSlice(allocator);
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
        std.debug.print("[c64] loading file: '{s}'\n", .{
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
            std.debug.print("[c64] file load address: ${X:0>4}\n", .{
                load_address,
            });
        }

        var i: u16 = load_address;
        while (i < (load_address +% program.len -% 2)) : (i +%= 1) {
            c64.mem.data[i] = program[offs];
            if (c64.dbg_enabled)
                std.debug.print(
                    "[c64] writing mem: {X:0>4} offs: {X:0>4} data: {X:0>2}\n",
                    .{
                        i,
                        offs,
                        program[offs],
                    },
                );
            offs += 1;
        }
    }
    if (pc_to_loadaddr) c64.cpu.pc = load_address;
    return load_address;
}

pub fn appendSidChanges(
    existing_changes: *std.ArrayList(Sid.RegisterChange),
    new_changes: []Sid.RegisterChange,
    allocator: std.mem.Allocator,
) !void {
    try existing_changes.appendSlice(allocator, new_changes);
}
