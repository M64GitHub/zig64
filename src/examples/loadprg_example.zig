const std = @import("std");
const c64 = @import("mos6510");

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();

    try stdout.print("[MAIN] initializing emulator\n", .{});

    var emu = c64.init(gpa, c64.Vic.Type.pal, 0x0800);

    try stdout.print("[MAIN] cpu init address: {X:0>4}\n", .{
        emu.cpu.pc,
    });
    try stdout.print("[MAIN] emu vic type: {s}\n", .{
        @tagName(emu.vic.type),
    });
    try stdout.print("[MAIN] emu sid base address: {X:0>4}\n", .{
        emu.sid.base_address,
    });
    try stdout.print("[MAIN] cpu status:\n", .{});
    emu.cpu.printStatus();

    try stdout.print("\n", .{});

    // -- manually write a program into memory

    try stdout.print("[MAIN] Writing program ...\n", .{});

    // 0800: A9 0A                       LDA #$0A        ; 2
    // 0802: AA                          TAX             ; 2
    // 0803: 69 1E                       ADC #$1E        ; 2 loop start:
    // 0805: 9D 00 D4                    STA $D400,X     ; 5 write sid register X
    // 0808: E8                          INX             ; 2
    // 0809: E0 19                       CPX #$19        ; 2
    // 080B: D0 F6                       BNE $0803       ; 2/3 loop
    // 080D: 60                          RTS             ; 6

    emu.cpu.writeByte(0xa9, 0x0800); //         LDA,,
    emu.cpu.writeByte(0x0a, 0x0801); //             #0A     ; 10
    emu.cpu.writeByte(0xaa, 0x0802); //         TAX
    emu.cpu.writeByte(0x69, 0x0803); //         ADC
    emu.cpu.writeByte(0x1e, 0x0804); //             #$1E
    emu.cpu.writeByte(0x9d, 0x0805); //         STA $
    emu.cpu.writeByte(0x00, 0x0806); //                00
    emu.cpu.writeByte(0xd4, 0x0807); //              D4
    emu.cpu.writeByte(0xe8, 0x0808); //         INX
    emu.cpu.writeByte(0xe0, 0x0809); //         CPX
    emu.cpu.writeByte(0x19, 0x080A); //             #19
    emu.cpu.writeByte(0xd0, 0x080B); //         BNE
    emu.cpu.writeByte(0xf6, 0x080C); //             $0803 (-10)
    emu.cpu.writeByte(0x60, 0x080D); //         RTS
    emu.cpu.printStatus();

    // -- manually execute single steps, print cpu status
    //    and check sid register modifications

    try stdout.print("[MAIN] Executing program ...\n", .{});
    var sid_volume_old = emu.sid.getRegisters()[24];
    while (emu.cpu.runStep() != 0) {
        emu.cpu.printStatus();
        if (emu.cpu.sidRegWritten()) {
            try stdout.print("[MAIN] sid register written!\n", .{});
            emu.sid.printRegisters();

            const sid_registers = emu.sid.getRegisters();
            if (sid_volume_old != sid_registers[24]) {
                try stdout.print("[MAIN] sid volume changed: {X:0>2}\n", .{
                    sid_registers[24],
                });
                sid_volume_old = sid_registers[24];
            }
        }
    }
    try stdout.print("\n\n", .{});

    // --  reset cpu and clear memory

    try stdout.print("[MAIN] CPU hardreset\n", .{});
    emu.cpu.hardReset(); // clears memory

    // -- load a .prg file from disk
    //    this prg has the same opcodes, but a load address of 0x0801

    const file_name = "data/test1.prg";
    try stdout.print("[MAIN] Loading '{s}'\n", .{file_name});

    // emu.dbg_enabled = true;
    const load_address = try emu.loadPrg(file_name, false);
    try stdout.print("[MAIN] Load address: {X:0>4}\n", .{load_address});
    emu.cpu.dbg_enabled = true; // will call printStatus after each step
    emu.call(load_address);
}
