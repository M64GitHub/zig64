const std = @import("std");
const C64 = @import("zig64");
const Sid = C64.Sid;
const Asm = C64.Asm;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();

    // Initialize the C64 emulator at $0800 with PAL VIC
    var c64 = try C64.init(allocator, C64.Vic.Model.pal, 0x0800);
    defer c64.deinit(allocator);

    // Print initial emulator state
    try stdout.print("CPU start address: ${X:0>4}\n", .{c64.cpu.pc});
    try stdout.print("VIC model: {s}\n", .{@tagName(c64.vic.model)});
    try stdout.print("SID base address: ${X:0>4}\n", .{c64.sid.base_address});

    // Write a SID register sweep program to $0800
    try stdout.print("\nWriting SID sweep program to $0800...\n", .{});
    c64.cpu.writeByte(Asm.lda_imm.opcode, 0x0800); //  LDA #$0A     ; Load initial value 10
    c64.cpu.writeByte(0x0A, 0x0801);
    c64.cpu.writeByte(Asm.tax.opcode, 0x0802); //      TAX          ; X = A (index for SID regs)
    c64.cpu.writeByte(Asm.adc_imm.opcode, 0x0803); //  ADC #$1E     ; Add 30 to A
    c64.cpu.writeByte(0x1E, 0x0804);
    c64.cpu.writeByte(Asm.sta_absx.opcode, 0x0805); // STA $D400,X  ; Store A to SID reg X
    c64.cpu.writeByte(0x00, 0x0806);
    c64.cpu.writeByte(0xD4, 0x0807);
    c64.cpu.writeByte(Asm.inx.opcode, 0x0808); //      INX          ; Increment X
    c64.cpu.writeByte(Asm.cpx_imm.opcode, 0x0809); //  CPX #$19     ; Compare X with 25
    c64.cpu.writeByte(0x19, 0x080A);
    c64.cpu.writeByte(Asm.bne.opcode, 0x080B); //      BNE $0803    ; Loop back if X < 25
    c64.cpu.writeByte(0xF6, 0x080C);
    c64.cpu.writeByte(Asm.rts.opcode, 0x080D); //      RTS          ; Return

    // Enable debugging for CPU and SID
    c64.cpu.dbg_enabled = true;
    c64.sid.dbg_enabled = true;

    // Step through the program, analyzing SID changes
    try stdout.print("\nExecuting SID sweep step-by-step...\n", .{});
    while (c64.cpu.runStep() != 0) {
        if (c64.sid.last_change) |change| {
            try stdout.print(
                "SID register {s} changed!\n",
                .{@tagName(change.meaning)},
            );

            // Check specific changes using static Sid functions
            if (change.volumeChanged()) {
                const old_vol =
                    Sid.FilterModeVolume.fromValue(change.old_value).volume;
                const new_vol =
                    Sid.FilterModeVolume.fromValue(change.new_value).volume;
                try stdout.print(
                    "Volume changed: {d} => {d}\n",
                    .{ old_vol, new_vol },
                );
            }
            if (change.oscWaveformChanged(1)) {
                const wf = Sid.WaveformControl.fromValue(change.new_value);
                try stdout.print(
                    "Osc1 waveform updated: Pulse={}\n",
                    .{wf.pulse},
                );
            }
            if (change.oscFreqChanged(1)) {
                try stdout.print(
                    "Osc1 freq updated: {X:02} => {X:02}\n",
                    .{ change.old_value, change.new_value },
                );
            }
            if (change.oscAttackDecayChanged(1)) {
                const ad = Sid.AttackDecay.fromValue(change.new_value);
                try stdout.print(
                    "Osc1 attack/decay: A={d}, D={d}\n",
                    .{ ad.attack, ad.decay },
                );
            }
        }
    }

    // Final SID state
    try stdout.print("\nFinal SID registers:\n", .{});
    c64.sid.printRegisters();
}
