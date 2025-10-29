// zig64 - loadPrg() example
const std = @import("std");

const C64 = @import("zig64");
const flagz = @import("flagz");

const Asm = C64.Asm;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Args = struct {
        prg: []const u8,
    };

    const args = try flagz.parse(Args, allocator);
    defer flagz.deinit(args, allocator);

    std.debug.print("[EXE] initializing emulator\n", .{});
    var c64 = try C64.init(allocator, C64.Vic.Model.pal, 0x0000);
    defer c64.deinit(allocator);

    // full debug output
    c64.dbg_enabled = true;
    c64.cpu.dbg_enabled = true;
    // c64.vic.dbg_enabled = true;
    // c64.sid.dbg_enabled = true;

    // load a .prg file from disk
    std.debug.print("[EXE] Loading '{s}'\n", .{args.prg});
    const load_address = try c64.loadPrg(allocator, args.prg, true);
    std.debug.print("[EXE] Load address: {X:0>4}\n\n", .{load_address});

    std.debug.print("[EXE] Disassembling from: {X:0>4}\n", .{load_address});
    try Asm.disassembleForward(&c64.mem.data, load_address, 31);
    std.debug.print("\n\n", .{});

    std.debug.print("[EXE] RUN\n", .{});
    c64.run();
}
