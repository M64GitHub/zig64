const std = @import("std");
const C64 = @import("zig64");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var c64 = try C64.init(allocator, C64.Vic.Model.pal, 0x0800);
    defer c64.deinit(allocator);

    // Disassembly of SID Routines for Testing callSidTrace()
    //
    // Disassembly of SID Routine 1: Looping Oscillator Frequency and Envelope Sweep
    // Address: $0800
    // Length: 29 bytes
    // Purpose: Loops 10 times to sweep oscillator 1 frequency from $10 to $1A,
    //          sets envelope once
    // 0800: A2 00     LDX #$00      ; X = loop counter (0 to 9)
    // 0802: A9 10     LDA #$10      ; A = initial frequency ($10)
    // 0804: 8D 00 D4  STA $D400     ; Osc1 freq lo = $10
    // 0807: 8D 01 D4  STA $D401     ; Osc1 freq hi = $10
    // 080A: A9 41     LDA #$41      ; Pulse + Gate
    // 080C: 8D 04 D4  STA $D404     ; Osc1 control = $41
    // 080F: A9 53     LDA #$53      ; Attack=5, Decay=3
    // 0811: 8D 05 D4  STA $D405     ; Osc1 attack/decay = $53
    // 0814: E8        INX           ; X += 1
    // 0815: AD 00 D4  LDA $D400     ; Reload current freq lo (starts at $10)
    // 0818: 69 01     ADC #$01      ; Increment freq ($11, $12, ..., $1A)
    // 081A: 8D 00 D4  STA $D400     ; Update Osc1 freq lo
    // 081D: 8D 01 D4  STA $D401     ; Update Osc1 freq hi
    // 0820: E0 0A     CPX #$0A      ; Compare X with 10
    // 0822: D0 F0     BNE $0814     ; Loop back to INX if X < 10 (-16 bytes)
    // 0824: 60        RTS           ; Return
    //
    // Routine 2: Simple Melody on Oscillator 1
    // Address: $0900
    // Length: 45 bytes
    // Purpose: Plays C-E-G-C with gate toggling
    // 0900: A9 F5     LDA #$F5      ; Sustain=15, Release=5
    // 0902: 8D 06 D4  STA $D406     ; Osc1 sustain/release
    // 0905: A9 17     LDA #$17      ; C freq lo (~261 Hz)
    // 0907: 8D 00 D4  STA $D400     ; Osc1 freq lo
    // 090A: A9 01     LDA #$01      ; Freq hi
    // 090C: 8D 01 D4  STA $D401     ; Osc1 freq hi
    // 090F: A9 41     LDA #$41      ; Pulse + Gate on
    // 0911: 8D 04 D4  STA $D404     ; Osc1 control
    // 0914: A9 40     LDA #$40      ; Gate off
    // 0916: 8D 04 D4  STA $D404     ; Osc1 control
    // 0919: A9 47     LDA #$47      ; E freq lo (~329 Hz)
    // 091B: 8D 00 D4  STA $D400     ; Osc1 freq lo
    // 091E: A9 01     LDA #$01      ; Freq hi
    // 0920: 8D 01 D4  STA $D401     ; Osc1 freq hi
    // 0923: A9 41     LDA #$41      ; Gate on
    // 0925: 8D 04 D4  STA $D404     ; Osc1 control
    // 0928: A9 40     LDA #$40      ; Gate off
    // 092A: 8D 04 D4  STA $D404     ; Osc1 control
    // 092D: A9 8E     LDA #$8E      ; G freq lo (~392 Hz)
    // 092F: 8D 00 D4  STA $D400     ; Osc1 freq lo
    // 0932: A9 01     LDA #$01      ; Freq hi
    // 0934: 8D 01 D4  STA $D401     ; Osc1 freq hi
    // 0937: A9 41     LDA #$41      ; Gate on
    // 0939: 8D 04 D4  STA $D404     ; Osc1 control
    // 093C: A9 40     LDA #$40      ; Gate off
    // 093E: 8D 04 D4  STA $D404     ; Osc1 control
    // 0941: A9 2E     LDA #$2E      ; C freq lo (~523 Hz)
    // 0943: 8D 00 D4  STA $D400     ; Osc1 freq lo
    // 0946: A9 02     LDA #$02      ; Freq hi
    // 0948: 8D 01 D4  STA $D401     ; Osc1 freq hi
    // 094B: A9 41     LDA #$41      ; Gate on
    // 094D: 8D 04 D4  STA $D404     ; Osc1 control
    // 0950: A9 40     LDA #$40      ; Gate off
    // 0952: 8D 04 D4  STA $D404     ; Osc1 control
    // 0955: 60        RTS           ; Return
    //
    // Routine 3: Filter and Volume Sweep with Loop
    // Address: $0A00
    // Length: 17 bytes
    // Purpose: Loops 5 times, sweeping volume and filter freq
    // 0A00: A2 00     LDX #$00      ; X = loop counter
    // 0A02: A9 0F     LDA #$0F      ; Volume 15
    // 0A04: 8D 18 D4  STA $D418     ; Filter mode/volume
    // 0A07: A9 80     LDA #$80      ; Filter freq lo
    // 0A09: 8D 15 D4  STA $D415     ; Filter freq lo
    // 0A0C: CA        DEX           ; X -= 1 (underflow to 255 first)
    // 0A0D: 8E 16 D4  STX $D416     ; Filter freq hi (drops from FF)
    // 0A10: E0 FB     CPX #$FB      ; Stop after 5 loops (FF -> FB)
    // 0A12: D0 F1     BNE $0A02     ; Loop back to LDA #$0F
    // 0A14: 60        RTS           ; Return

    // Define the routines
    const freq_env_sweep = [_]u8{
        0xA2, 0x00, 0xA9, 0x10, 0x8D, 0x00, 0xD4, 0x8D, 0x01, 0xD4,
        0xA9, 0x41, 0x8D, 0x04, 0xD4, 0xA9, 0x53, 0x8D, 0x05, 0xD4,
        0xE8, 0xAD, 0x00, 0xD4, 0x69, 0x01, 0x8D, 0x00, 0xD4, 0x8D,
        0x01, 0xD4, 0xE0, 0x0A, 0xD0, 0xF0, 0x60,
    };

    const melody = [_]u8{
        0xA9, 0xF5, 0x8D, 0x06, 0xD4, 0xA9, 0x17, 0x8D, 0x00, 0xD4,
        0xA9, 0x01, 0x8D, 0x01, 0xD4, 0xA9, 0x41, 0x8D, 0x04, 0xD4,
        0xA9, 0x40, 0x8D, 0x04, 0xD4, 0xA9, 0x47, 0x8D, 0x00, 0xD4,
        0xA9, 0x01, 0x8D, 0x01, 0xD4, 0xA9, 0x41, 0x8D, 0x04, 0xD4,
        0xA9, 0x40, 0x8D, 0x04, 0xD4, 0xA9, 0x8E, 0x8D, 0x00, 0xD4,
        0xA9, 0x01, 0x8D, 0x01, 0xD4, 0xA9, 0x41, 0x8D, 0x04, 0xD4,
        0xA9, 0x40, 0x8D, 0x04, 0xD4, 0xA9, 0x2E, 0x8D, 0x00, 0xD4,
        0xA9, 0x02, 0x8D, 0x01, 0xD4, 0xA9, 0x41, 0x8D, 0x04, 0xD4,
        0xA9, 0x40, 0x8D, 0x04, 0xD4, 0x60,
    };
    const filter_volume_sweep = [_]u8{
        0xA2, 0x00, 0xA9, 0x0F, 0x8D, 0x18, 0xD4, 0xA9, 0x80, 0x8D,
        0x15, 0xD4, 0xCA, 0x8E, 0x16, 0xD4, 0xE0, 0xFB, 0xD0, 0xEE,
        0x60,
    };

    // Write routines to RAM
    c64.cpu.writeMem(&freq_env_sweep, 0x0800);
    c64.cpu.writeMem(&melody, 0x0900);
    c64.cpu.writeMem(&filter_volume_sweep, 0x0A00);

    c64.cpu.dbg_enabled = true;
    // Enable SID debugging
    c64.sid.dbg_enabled = true;

    // Master list for all changes
    var all_changes = std.ArrayList(C64.Sid.RegisterChange){};
    defer all_changes.deinit(allocator);

    // Run each routine with callSidTrace
    const routines = [_]u16{ 0x0800, 0x0900, 0x0A00 };
    for (routines) |addr| {
        c64.cpu.printStatus();
        std.debug.print("LALA!\n", .{});

        const changes = try c64.callSidTrace(addr, allocator);
        defer allocator.free(changes);

        try C64.appendSidChanges(&all_changes, changes, allocator);
        std.debug.print(
            "Traced {d} SID changes from ${X:0>4}\n",
            .{ changes.len, addr },
        );
    }

    // Print all collected changes
    std.debug.print("\nTotal SID changes: {d}\n", .{all_changes.items.len});
    for (all_changes.items) |change| {
        std.debug.print(
            "Cycle {d}: {s} changed {X:02} => {X:02}\n",
            .{
                change.cycle,
                @tagName(change.meaning),
                change.old_value,
                change.new_value,
            },
        );
    }
}
