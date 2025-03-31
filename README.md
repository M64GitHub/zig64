# Commodore 64 MOS 6510 Emulator Core

![Tests](https://github.com/M64GitHub/zig64/actions/workflows/test.yml/badge.svg)
![Version](https://img.shields.io/badge/version-0.4.0-007bff?style=flat)
![Status](https://img.shields.io/badge/status-active-00cc00?style=flat)
![License](https://img.shields.io/badge/license-MIT-brightgreen?style=flat)
![Zig](https://img.shields.io/badge/Zig-0.14.0-orange?style=flat)
 
A **Commodore 64 MOS 6510 emulator core** implemented in **Zig**, engineered for precision, flexibility, and seamless integration into C64-focused projects. This emulator delivers cycle-accurate CPU execution, detailed raster beam emulation for PAL and NTSC video synchronization, and advanced SID register tracking with change decoding, making it an ideal foundation for C64 software analysis, dissecting SID player routines, analyzing register manipulations, and debugging.

Built as the **computational backbone** of a virtual C64 system, it powers a range of applications—from tracing and debugging 6510 assembly with rich CPU state insights to dissecting SID register manipulations for tools like 🎧 [zigreSID](https://github.com/M64GitHub/zigreSID). Leveraging Zig’s modern features, it offers a clean, extensible platform with enhanced debugging capabilities, including step-by-step CPU traces and detailed SID change analysis.

This project **sparked from a passion for Commodore 64 SID music**, aiming to recreate and elevate that experience across platforms. As a musician tweaking SID tunes and `.sid` files—archives embedding 6510 assembly for player routines—I needed a core to execute these, trace SID register changes with cycle precision, to enable custom sound tools. That vision grew into this emulator, blending nostalgia with cutting-edge emulation tech.

**A key goal** is to **lower the barriers** to C64 emulation, offering an accessible entry point for developers and enthusiasts alike. With intuitive Zig tooling, robust CPU debugging, and SID state tracking, it simplifies analyzing intricate C64 programs, decoding SID behavior, and testing software—empowering users to explore, experiment, and create with ease.

## 🚀 Key Features
- 🎮 **Cycle-Accurate 6510 CPU Emulation**  
  Implements all documented MOS 6502/6510 instructions and addressing modes with exact timing and behavior, ensuring faithful program execution down to the cycle.

- 🎞 **Video Synchronization**  
  Aligns CPU cycles with PAL and NTSC video timings, featuring full raster beam emulation and precise bad line handling for authentic raster interrupt behavior.

- 🎵 **Advanced SID Register Tracking & Decoding**  
  Monitors all SID register writes with cycle precision, decoding changes into detailed structs (e.g., waveforms, envelopes), perfect for analyzing player routines and sound interactions.

- 💾 **Program Loading Capabilities**  
  Loads `.prg` files directly into memory, streamlining execution and integration of C64 programs and `.sid` player codebases.

- 🛠 **Powerful Debugging Tools**  
  Offers step-by-step CPU tracing, rich state inspection (registers, flags, memory, VIC-II, SID), and SID change logging, empowering precise control and deep analysis.

- 🔍 **Robust Disassembler & Instruction Metadata**  
  Transforms 6502/6510 opcodes into readable mnemonics with metadata (size, group, addressing mode, operand type/size/access), ideal for code tracing and reverse-engineering.

- 🧪 **Testing C64 Programs with Zig**  
  Seamlessly integrates with Zig’s testing framework, enabling developers to write unit tests for C64 code and verify emulator behavior with ease.

## Quick Start Demo

Example loading, running, and disassembling a `.prg` file:

```zig
const std = @import("std");
const C64 = @import("zig64");
const Asm = C64.Asm;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    var c64 = try C64.init(allocator, C64.Vic.Model.pal, 0x0000);
    defer c64.deinit(allocator);

    // Enable debug output
    c64.dbg_enabled = true;
    c64.cpu.dbg_enabled = true;

    // Load and disassemble a .prg file
    const load_address = try c64.loadPrg(allocator, "example.prg", true);
    try stdout.print("Loaded 'example.prg' at ${X:0>4}\n", .{load_address});
    try Asm.disassembleForward(&c64.mem.data, load_address, 10);

    // Run the program
    try stdout.print("\nRunning...\n", .{});
    c64.run();
}
```
Output
```
[c64] loading file: 'example.prg'
[c64] file load address: $C000
[c64] writing mem: C000 offs: 0002 data: 78
...
Loaded 'example.prg' at $C000
C000:  78        SEI
C001:  A9 00     LDA #$00
C003:  85 01     STA $01
C005:  A2 FF     LDX #$FF
C007:  9A        TXS
C008:  A0 00     LDY #$00
C00A:  A9 41     LDA #$41
C00C:  99 00 04  STA $0400,Y
C00F:  A9 01     LDA #$01
C011:  99 00 D8  STA $D800,Y
...
Running...
[cpu] PC: C000 | 78       | SEI          | A: 00 | X: 00 | Y: 00 | SP: FF | Cycl: 00 | Cycl-TT: 0 | FL: 00100100
[cpu] PC: C001 | A9 00    | LDA #$00     | A: 00 | X: 00 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 2 | FL: 00100100
[cpu] PC: C003 | 85 01    | STA $01      | A: 00 | X: 00 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 4 | FL: 00100110
[cpu] PC: C005 | A2 FF    | LDX #$FF     | A: 00 | X: 00 | Y: 00 | SP: FF | Cycl: 03 | Cycl-TT: 7 | FL: 00100110
[cpu] PC: C007 | 9A       | TXS          | A: 00 | X: FF | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 9 | FL: 10100100
[cpu] PC: C008 | A0 00    | LDY #$00     | A: 00 | X: FF | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 11 | FL: 10100100
[cpu] PC: C00A | A9 41    | LDA #$41     | A: 00 | X: FF | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 13 | FL: 00100110
[cpu] PC: C00C | 99 00 04 | STA $0400,Y  | A: 41 | X: FF | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 15 | FL: 00100100
[cpu] PC: C00F | A9 01    | LDA #$01     | A: 41 | X: FF | Y: 00 | SP: FF | Cycl: 04 | Cycl-TT: 19 | FL: 00100100
```

## Overview

This emulator is structured as a set of modular components, forming the foundation of the virtual C64 system. These building blocks include:

- `C64`: The central emulator struct and component container, managing program loading and execution.
- `Cpu`: Executes 6510 instructions.
- `Ram64k`: Manages 64KB of memory.
- `Vic`: Controls video timing.
- `Sid`: Holds register values and tracks register writes.
- `Asm`: Provides assembly metadata decoding and disassembly.

Each component features its own `dbg_enabled` flag—e.g., `c64.dbg_enabled` for emulator logs, `cpu.dbg_enabled` for execution details—enabling targeted debugging. The `Cpu` powers the system, running code and tracking SID register writes, while `Vic` ensures cycle-accurate timing.  
The `Asm` struct enhances this core with a powerful disassembler and metadata decoder, offering detailed instruction analysis.  
The sections below outline their mechanics, API, and examples to guide you in using this emulator core effectively.

## Component Interactions

**C64: Emulator Core**  
The `C64` struct serves as the main struct, initializing components like `Cpu`, `Sid`, `Vic`, and `Ram64k`, and loading `.prg` files into `Ram64k` with `loadPrg()`. It directs `Cpu` execution through `run()`, `runFrames()`, or `call()`, the latter resetting CPU state and tracking SID register changes during subroutine execution via flags like `sid.ext_reg_written` and `sid.ext_reg_changed`. For advanced SID analysis, `callSidTrace()` executes subroutines while capturing every register change with cycle precision into an array of `RegisterChange` structs, which can be aggregated across multiple calls using `appendSidChanges()`—ideal for debugging `.sid` files or custom sound routines.

**Cpu: Execution Engine**  
The `Cpu` struct drives the emulator as the 6502 execution core, fetching instructions from `Ram64k` and stepping through them with `runStep()`. It orchestrates cycle-accurate execution, managing registers (`pc`, `a`, `x`, `y`, `sp`), status flags, and memory operations while coordinating with `Vic` for timing and `Sid` for register writes. Integrated with `Asm`, it leverages decoded `Instruction` metadata to execute opcodes and supports debugging with detailed trace output.

- **Execution Flow**: `runStep()` fetches each opcode, executes it (e.g., `LDA`, `AND`, `JMP`), and updates cycle counters (`cycles_executed`, `cycles_last_step`). It resets tracking flags for `Sid` and `Vic` per step, ensuring fresh state tracking.
- **Memory & I/O**: Reads and writes via `readByte()` and `writeByte()`, routing SID register updates to `sid.writeRegisterCycle()` for addresses `$D400`–`$D419` (`sid.base_address`). Cycle counts increment with each operation, reflecting 6502 timing.
- **Timing Sync**: Tracks cycles since vsync/hsync (`cycles_since_vsync`, `cycles_since_hsync`) and delegates raster beam emulation to `Vic.emulateD012()`, which adjusts these counters for events like bad lines.
- **Debugging**: When `dbg_enabled` is true, `printStatus()` and `printTrace()` provide snapshots of registers, flags, and disassembled instructions (via `Asm`), making execution transparent.
- **Flexibility**: Supports resets (`reset()`, `hardReset()`), manual memory writes (`writeMem()`), and stack operations (`pushW()`, `popW()`), offering full control for emulation and testing.

**Ram64k: System RAM**  
`Ram64k` acts as the central memory pool, accepting writes from `C64.loadPrg()` and `Cpu.writeByte()`. It feeds instruction data to `Cpu` and register values to `Vic` and `Sid`, ensuring system-wide consistency.

**Vic: Video Timing / Raster Beamer**  
The `Vic` struct emulates the VIC-II chip’s timing behavior, focusing on raster line advancement and CPU synchronization without generating video output. Timing is driven by the `Cpu` during instruction execution, where the number of cycles taken increments `Vic` counters. The `emulateD012()` function then advances the virtual raster beam, updating the raster line counter (`$D012`) and tracking events like vsync, hsync, and bad lines. These events adjust specific `Cpu` fields based on the `model` (PAL or NTSC), ensuring accurate timing and raster interrupt emulation.

- **Raster Tracking**: Advances `rasterline` and sets flags (`vsync_happened`, `hsync_happened`, `badline_happened`, `rasterline_changed`) to reflect timing events. Vsync resets the raster line to 0, while bad lines (every 8th line at offset 3) trigger cycle adjustments.
- **Memory Integration**: Updates `$D011` and `$D012` in `Ram64k` to mimic VIC-II register changes, supporting raster interrupt logic without rendering.
- **Timing Precision**: Relies on CPU cycle counts (e.g., 63 cycles per PAL raster line, 40 cycles stolen on bad lines) to align execution. On bad lines, `Vic` updates `cpu.cycles_executed`, `cpu.cycles_last_step`, `cpu.cycles_since_hsync`, and `cpu.cycles_since_vsync` by adding stolen cycles.

**Sid: Register Management and Analysis**  
The `Sid` struct emulates the SID chip’s register state, mapped into C64 memory at `base_address` (typically `$D400`), offering a powerful interface for tracking, decoding, and analyzing writes from the `Cpu`. Register updates are handled via `writeRegister(reg: usize, val: u8)` for general writes and `writeRegisterCycle(reg: usize, val: u8, cycle: usize)` for cycle tracking, maintaining the internal `[25]u8` register array accessible through `getRegisters()`.

- **Write Tracking**: Each write sets `reg_written` to `true`, storing the register index in `reg_written_idx` and value in `reg_written_val`. The `ext_reg_written` flag signals external systems (persistent until cleared, e.g., by `call()`), while `writeRegisterCycle()` logs the CPU cycle in `last_write_cycle`.
- **Change Detection**: On value changes, `reg_changed` and `ext_reg_changed` flags activate, capturing state in `reg_changed_idx`, `reg_changed_from`, and `reg_changed_to`. The `last_change` field records a `RegisterChange` struct with the register’s meaning (e.g., `osc1_control`, `filter_mode_volume`), old and new values, and decoded details (e.g., waveform flags or envelope settings).
- **Register Decoding**: Maps all 25 registers to `RegisterMeaning`, decoding bitfields for waveforms (`WaveformControl`), filters (`FilterResControl`, `FilterModeVolume`), and envelopes (`AttackDecay`, `SustainRelease`). Utility functions like `volumeChanged()`, `oscFreqChanged(osc: u2)`, and `oscWaveformChanged(osc: u2)` identify specific changes, with oscillator-specific checks using a 1–3 index.
- **Debugging**: When `dbg_enabled` is true, detailed logs break down changes (e.g., “Osc1 waveform: Pulse on” or “Filter volume: 7”), leveraging bitfield structs for clarity.
- **Integration**: The `Cpu` delegates writes via `writeRegisterCycle()`, offloading state management to `Sid` for seamless tracking and analysis.

**Asm: Instruction Decoder, Disassembler and Assembly Support**  
The `Asm` struct serves as a powerful tool for decoding, analyzing, and disassembling 6502 instructions from `Ram64k` bytes, while also enabling manual assembly with predefined `Instruction` metadata. It processes opcodes into detailed `Instruction` structs via `decodeInstruction()`, categorizing them by group (e.g., `branch`, `load_store`) and addressing mode (e.g., `immediate`, `absolute`). This supports complex code analysis for the `Cpu` and human-readable output through `disassembleCodeLine()`. Additionally, its structured constants (e.g., `Asm.lda_imm`) double as an assembly interface with IDE autocomplete support.

- **Decoding & Analysis**: `decodeInstruction()` transforms raw bytes into `Instruction` structs, capturing opcode, mnemonic, addressing mode, operand details (type, size, access), and group. This metadata enables abstract analysis, such as tracking register usage or memory access patterns.
- **Disassembly**: `disassembleCodeLine()` and `disassembleForward()` format instructions into readable strings (e.g., `LDA #$0A` or `JMP $1234`), adjusting for addressing modes and branch offsets, ideal for debugging or code inspection.
- **Manual Assembly**: Predefined `Instruction` constants (e.g., `Asm.lda_abs`, `Asm.jmp_ind`) expose opcodes and metadata for direct use. For example, `c64.cpu.writeByte(Asm.lda_imm.opcode, 0x0800)` followed by `c64.cpu.writeByte(0x0A, 0x0801)` assembles `LDA #$0A` at address `$0800`, with autocomplete enhancing usability in editors.
- **Flexibility**: Supports all 6502 addressing modes and operand types, with optional second operands (e.g., for indexed modes), making it a versatile bridge between emulation and development.

## API Reference

Please see [API Reference](API.md)


## Example Code

Below are practical examples to demonstrate using the zig64 emulator core. Starting with short snippets for specific tasks, followed by examples showcasing SID register analysis  a complete example of manually programming and stepping through a routine.

### Single-Step CPU Execution
```zig
var c64 = try C64.init(allocator, C64.Vic.Model.pal, 0xC000);
defer c64.deinit(allocator);

const cycles = c64.cpu.runStep();
std.debug.print("Executed one step, took {} cycles\n", .{cycles});
```
Runs a single CPU instruction and prints the cycle count.

### Reading SID Registers
```zig
var c64 = try C64.init(allocator, C64.Vic.Model.pal, 0x0000);
defer c64.deinit(allocator);

const regs = c64.sid.getRegisters();
std.debug.print("SID register 0: {X:0>2}\n", .{regs[0]});
```
Retrieves and prints the first SID register value.

### Disassembling a Memory Range
```zig
var c64 = try C64.init(allocator, C64.Vic.Model.pal, 0xC000);
defer c64.deinit(allocator);

try C64.Asm.disassembleForward(&c64.mem.data, 0xC000, 5);
```
Disassembles five instructions starting at address `$C000`.

### Detecting SID Volume Changes
```zig
var c64 = try C64.init(allocator, C64.Vic.Model.pal, 0xC000);
defer c64.deinit(allocator);

c64.sid.writeRegister(24, 0x0F); // Set volume to 15, no filters
c64.sid.writeRegister(24, 0x47); // Change to volume 7, high-pass on
if (c64.sid.last_change) |change| {
    if (change.volumeChanged()) {
        const old_vol = Sid.FilterModeVolume.fromValue(change.old_value).volume;
        const new_vol = Sid.FilterModeVolume.fromValue(change.new_value).volume;
        std.debug.print("Volume changed from {d} to {d}!\n", .{ old_vol, new_vol });
    }
}
```
Writes to the SID volume/filter register and checks for volume changes, printing the old and new values.

### Monitoring Oscillator Frequency Updates
```zig
var c64 = try C64.init(allocator, C64.Vic.Model.pal, 0xC000);
defer c64.deinit(allocator);

c64.sid.writeRegister(0, 0x12); // Osc1 freq lo
if (c64.sid.last_change) |change| {
    if (change.oscFreqChanged(1)) {
        std.debug.print("Osc1 frequency changed: {X:02} => {X:02}!\n", 
            .{ change.old_value, change.new_value });
    }
}
```
Updates an oscillator 1 frequency register and detects the change.

### Analyzing Oscillator Frequency and Envelope Adjustments
```zig
  const stdout = std.io.getStdOut().writer();
  sid.writeRegisterCycle(0, 0x42, 50);  // Set osc1_freq_lo to 0x42 at cycle 50
  if (sid.last_change) |change| {
      if (change.oscFreqChanged(1)) {
          try stdout.print("Osc1 freq updated: {X:02} => {X:02}\n",
              .{ change.old_value, change.new_value });
          // Expected output: "Osc1 freq updated: 00 => 42"
      }
      if (change.oscAttackDecayChanged(1)) {
          const ad = Sid.AttackDecay.fromValue(change.new_value);
          try stdout.print("Osc1 attack/decay: A={d}, D={d}\n",
              .{ ad.attack, ad.decay });
          // (No output here since it’s not osc1_attack_decay)
      }
  }
  sid.writeRegisterCycle(5, 0x53, 60);  // Set osc1_attack_decay to 0x53 at cycle 60
  if (sid.last_change) |change| {
      if (change.oscFreqChanged(1)) {
          try stdout.print("Osc1 freq updated: {X:02} => {X:02}\n",
              .{ change.old_value, change.new_value });
          // (No output here since it’s not a freq change)
      }
      if (change.oscAttackDecayChanged(1)) {
          const ad = Sid.AttackDecay.fromValue(change.new_value);
          try stdout.print("Osc1 attack/decay: A={d}, D={d}\n",
              .{ ad.attack, ad.decay });
          // Expected output: "Osc1 attack/decay: A=5, D=3"
      }
  }
```
Modifies an oscillator 1 attack/decay register and prints the new envelope settings.

### Manually Programming and Stepping a SID Sweep Routine
```zig
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
```
This program writes a small routine to sweep through SID registers `$D400`–`$D418`, incrementing a value and storing it with an index. It runs step-by-step, using `last_change` and utility functions to detect and analyze specific SID updates (e.g., volume, oscillator 1 frequency, waveform, envelope).

Output:
```
CPU start address: $0800
VIC model: pal
SID base address: $D400
Writing SID sweep program to $0800...
Executing SID sweep step-by-step...
[cpu] PC: 0800 | A9 0A    | LDA #$0A     | A: 00 | X: 00 | Y: 00 | SP: FF | Cycl: 00 | Cycl-TT: 14 | FL: 00100100
[cpu] PC: 0802 | AA       | TAX          | A: 0A | X: 00 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 16 | FL: 00100100
[cpu] PC: 0803 | 69 1E    | ADC #$1E     | A: 0A | X: 0A | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 18 | FL: 00100100
[cpu] PC: 0805 | 9D 00 D4 | STA $D400,X  | A: 28 | X: 0A | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 20 | FL: 00100100
[sid] reg changed: D40A : 00 => 28
[sid] osc2_pw_hi changed: D40A : 00 => 28
SID register osc2_pw_hi changed!
[cpu] PC: 0808 | E8       | INX          | A: 28 | X: 0A | Y: 00 | SP: FF | Cycl: 04 | Cycl-TT: 24 | FL: 00100100
[cpu] PC: 0809 | E0 19    | CPX #$19     | A: 28 | X: 0B | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 26 | FL: 00100100
[cpu] PC: 080B | D0 F6    | BNE $0803    | A: 28 | X: 0B | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 28 | FL: 10100100
[cpu] PC: 0803 | 69 1E    | ADC #$1E     | A: 28 | X: 0B | Y: 00 | SP: FF | Cycl: 03 | Cycl-TT: 31 | FL: 10100100
[cpu] PC: 0805 | 9D 00 D4 | STA $D400,X  | A: 46 | X: 0B | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 33 | FL: 00100100
[sid] reg changed: D40B : 00 => 46
[sid] osc2_control changed: D40B : 00 => 46 (Gate: false, Sync: true, Ring: true, Test: false, Tri: false, Saw: false, Pulse: true, Noise: false)
SID register osc2_control changed!
[cpu] PC: 0808 | E8       | INX          | A: 46 | X: 0B | Y: 00 | SP: FF | Cycl: 04 | Cycl-TT: 37 | FL: 00100100
[cpu] PC: 0809 | E0 19    | CPX #$19     | A: 46 | X: 0C | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 39 | FL: 00100100
[cpu] PC: 080B | D0 F6    | BNE $0803    | A: 46 | X: 0C | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 41 | FL: 10100100
[cpu] PC: 0803 | 69 1E    | ADC #$1E     | A: 46 | X: 0C | Y: 00 | SP: FF | Cycl: 03 | Cycl-TT: 44 | FL: 10100100
[cpu] PC: 0805 | 9D 00 D4 | STA $D400,X  | A: 64 | X: 0C | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 46 | FL: 00100100
[sid] reg changed: D40C : 00 => 64
[sid] osc2_attack_decay changed: D40C : 00 => 64 (Attack: 6, Decay: 4)
SID register osc2_attack_decay changed!
...
[cpu] PC: 0808 | E8       | INX          | A: AE | X: 17 | Y: 00 | SP: FF | Cycl: 04 | Cycl-TT: 193 | FL: 10100100
[cpu] PC: 0809 | E0 19    | CPX #$19     | A: AE | X: 18 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 195 | FL: 00100100
[cpu] PC: 080B | D0 F6    | BNE $0803    | A: AE | X: 18 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 197 | FL: 10100100
[cpu] PC: 0803 | 69 1E    | ADC #$1E     | A: AE | X: 18 | Y: 00 | SP: FF | Cycl: 03 | Cycl-TT: 200 | FL: 10100100
[cpu] PC: 0805 | 9D 00 D4 | STA $D400,X  | A: CC | X: 18 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 202 | FL: 10100100
[sid] reg changed: D418 : 00 => CC
[sid] filter_mode_volume changed: D418 : 00 => CC (Vol: 12, LP: false, BP: false, HP: true, Osc3 Off: true)
SID register filter_mode_volume changed!
Volume changed: 0 => 12
[cpu] PC: 0808 | E8       | INX          | A: CC | X: 18 | Y: 00 | SP: FF | Cycl: 44 | Cycl-TT: 246 | FL: 10100100
[cpu] PC: 0809 | E0 19    | CPX #$19     | A: CC | X: 19 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 248 | FL: 00100100
[cpu] PC: 080B | D0 F6    | BNE $0803    | A: CC | X: 19 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 250 | FL: 00100111
[cpu] PC: 080D | 60       | RTS          | A: CC | X: 19 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 252 | FL: 00100111
[cpu] RTS EXIT!
Final SID registers:
[sid] registers: 00 00 00 00 00 00 00 00 00 00 28 46 64 82 A0 BE DC FA 18 36 54 72 90 AE CC 
```

## Building the Project
#### Requirements
![Zig](https://img.shields.io/badge/Zig-0.14.0-orange?style=flat)

#### Build
```sh
zig build
```


#### Run CPU Tests:
```sh
zig build test
```

<br>

## Using zig64 In Your Project
To add `zig64` as a dependency, use:
```sh
zig fetch --save https://github.com/M64GitHub/zig64/archive/refs/tags/v0.4.0.tar.gz
```
This will add the dependency to your `build.zig.zon`:
```zig
.dependencies = .{
    .zig64 = .{
        .url = "https://github.com/M64GitHub/zig64/archive/refs/tags/v0.4.0.tar.gz",
        .hash = "zig64-0.4.0-v6Fnevh-BADQQLrOWxSwFPI_uzYK_c75MpZtAyP2zosT",
    },
},
```

In your `build.zig`, add the module as follows:
```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = std.builtin.OptimizeMode.ReleaseFast;

    const dep_zig64 = b.dependency("zig64", .{}); // define the dependeny
    const mod_zig64 = dep_zig64.module("zig64");  // define the module

    // ...

    // add to an example executable:
    const exe = b.addExecutable(.{
        .name = "loadPrg-example",
        .root_source_file = b.path("src/examples/loadprg_example.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zig64", mod_zig64); // add the module

    // ...
}
```

## 🔓 License
This emulator is released under the **MIT License**, allowing free modification and distribution.

## 🌐 Related Projects  
- 🎧 **[zigreSID](https://github.com/M64GitHub/zigreSID)** – A SID sound emulation library for Zig, integrating with this emulator for `.sid` file playback.


Developed with ❤️ by M64  

## 🚀 Get Started Now!
Clone the repository and start experimenting:
```sh
git clone https://github.com/M64GitHub/zig64.git
cd zig64
zig build
```
Enjoy bringing the **C64 CPU to life in Zig!** 🕹🔥






