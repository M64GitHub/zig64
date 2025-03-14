// zig64 - loadPrg example
const std = @import("std");
const C64 = @import("zig64");

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();

    try stdout.print("[MAIN] initializing c64lator\n", .{});
    var c64 = C64.init(gpa, C64.Vic.Model.pal, 0x0000);

    // -- load a .prg file from disk

    const file_name = "c64asm/test.prg";
    try stdout.print("[MAIN] Loading '{s}'\n", .{file_name});

    // c64.dbg_enabled = true;
    const load_address = try c64.loadPrg(gpa, file_name, true);
    try stdout.print("[MAIN] Load address: {X:0>4}\n", .{load_address});
    c64.cpu.dbg_enabled = true; // will call printStatus after each step
    c64.run();
    c64.call(load_address);
}
