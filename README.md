# Commodore 64 MOS 6510 Emulator Core

![Tests](https://github.com/M64GitHub/flagZ/actions/workflows/test.yml/badge.svg)
![License](https://img.shields.io/badge/license-MIT-brightgreen?style=flat)
![Version](https://img.shields.io/badge/version-0.3.0-8a2be2?style=flat)
![Zig](https://img.shields.io/badge/Zig-0.14.0-orange?style=flat)

A **Commodore 64 MOS 6510 emulator core** implemented in **Zig**, designed for precision, flexibility, and seamless integration into C64-focused projects. This emulator delivers cycle-accurate execution, detailed raster beam emulation for PAL and NTSC video synchronization, and SID register tracking, making it a robust foundation for C64 software analysis, execution, and development.

Built as the **computational backbone** of a virtual C64 system, it supports a variety of applications—from analyzing and debugging C64 programs to serving as the engine for SID sound emulation libraries like 🎧 [zigreSID](https://github.com/M64GitHub/zigreSID).  
Leveraging Zig’s modern features, it provides a clean and extensible platform for accurately emulating C64 behavior.

This project **began with a love for Commodore 64 SID music** and a desire to recreate and enhance that experience across platforms. As a musician using the C64, I aimed to tweak and modify SID tunes, which required working with `.sid` files—archives that embed 6510 CPU assembly code for player routines. To unlock this potential, I needed a CPU emulator to execute these routines, analyze how they manipulate SID registers over time, and build custom tools for sound experimentation, laying the groundwork for this emulator core.

**A goal** of this project is to **lower the barriers** to C64 emulation, providing an accessible entry point for developers and enthusiasts alike. With its straightforward design and Zig’s intuitive tooling, tasks like debugging intricate C64 programs, tracing execution paths, or testing software behavior are made approachable, empowering users to explore and experiment with minimal setup or complexity.



## 🚀 Key Features
- 🎮 **Cycle-Accurate 6510 CPU Emulation**  
  Implements all documented MOS 6502/6510 instructions and addressing modes with exact timing and behavior, ensuring faithful program execution.
- 🎞 **Video Synchronization**  
  Aligns CPU cycles with PAL and NTSC video timings, including full raster beam emulation and precise bad line handling for authentic raster interrupt behavior.
- 🎵 **SID Register Monitoring and Decoding**  
  Tracks all writes to SID registers and decodes them into meaningful structs, enabling detailed analysis and debugging of audio interactions.
- 💾 **Program Loading Capabilities**  
  Supports loading `.prg` files directly into memory, simplifying integration and execution of existing C64 programs and codebases.
- 🛠 **Comprehensive Debugging Tools**  
  Provides detailed inspection of CPU registers, flags, memory, VIC-II state, and SID registers, with single-step and full-run capabilities for precise control.
- 🔍 **Robust Disassembler & Instruction Metadata**  
  Decodes 6502/6510 opcodes into human-readable mnemonics, enriched with metadata (instruction size, group, addressing mode, operand details: type, size, access), ideal for code tracing and analysis.
- 🧪 **Testing C64 Programs with Zig**  
  Integrates seamlessly with Zig’s powerful testing infrastructure, enabling developers to write unit tests for C64 programs and verify emulator behavior with ease.

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
- **Memory & I/O**: Reads and writes via `readByte()` and `writeByte()`, routing SID register updates to `sid.writeRegisterCycle()` for addresses `$D400`–`$D419`. Cycle counts increment with each operation, reflecting 6502 timing.
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

### C64
The main emulator struct, combining CPU, memory, VIC, and SID for a complete C64 system, with advanced SID tracing capabilities.

- **Fields**:
  ```zig
  cpu: Cpu,          // The 6510 CPU instance
  mem: Ram64k,       // 64KB memory
  vic: Vic,          // Video Timing / Raster Beamer
  sid: Sid,          // SID registers
  dbg_enabled: bool, // Enables debug logging for the emulator
  ```

- **Functions**:
  ```zig
  pub fn init(
      allocator: std.mem.Allocator,
      vic_model: Vic.Model,
      init_addr: u16
  ) !C64
  ```
  Initializes a new C64 instance with default settings, allocating resources as needed.

  ```zig
  pub fn deinit(
      c64: *C64,
      allocator: std.mem.Allocator
  ) void
  ```
  Cleans up the C64 instance, freeing allocated memory.

  ```zig
  pub fn loadPrg(
      c64: *C64,
      allocator: std.mem.Allocator,
      file_name: []const u8,
      pc_to_loadaddr: bool
  ) !u16
  ```
  Loads a `.prg` file into `Ram64k` and returns the load address; if `pc_to_loadaddr` is true, sets the CPU’s program counter to the load address.

  ```zig
  pub fn run(
      c64: *C64
  ) void
  ```
  Executes the CPU continuously from the current program counter until program termination (RTS).

  ```zig
  pub fn call(
      c64: *C64,
      address: u16
  ) void
  ```
  Calls a specific assembly subroutine at the given address, resetting CPU state, tracking SID register changes via `sid.ext_reg_written` and `sid.ext_reg_changed`, and returning on RTS.

  ```zig
  pub fn runFrames(
      c64: *C64,
      frame_count: u32
  ) u32
  ```
  Runs the CPU for a specified number of frames, returning the number executed; frame timing adapts to PAL or NTSC VIC settings for accurate synchronization.

  ```zig
  pub fn callSidTrace(
      c64: *C64,
      address: u16,
      allocator: std.mem.Allocator
  ) ![]Sid.RegisterChange
  ```
  Executes a subroutine at the specified address, tracing all SID register changes into an array of `RegisterChange` structs with cycle information; returns the collected changes (caller must free with `allocator.free()`).

  - **Example**:
    ```zig
    const changes = try c64.callSidTrace(0x0800, allocator);
    defer allocator.free(changes);
    for (changes) |change| {
        std.debug.print("Cycle {d}: {s} changed {X:02} => {X:02}\n",
            .{ change.cycle, @tagName(change.meaning), change.old_value, change.new_value });
    }
    ```
    Traces SID changes from a subroutine at `$0800`, printing each change with cycle and register details.

  ```zig
  pub fn appendSidChanges(
      existing_changes: *std.ArrayList(Sid.RegisterChange),
      new_changes: []Sid.RegisterChange
  ) !void
  ```
  Static function to append new SID register changes to an existing `ArrayList`, enabling aggregation of changes across multiple `callSidTrace()` runs.
  - **Example**:
    ```zig
    var all_changes = std.ArrayList(Sid.RegisterChange).init(allocator);
    defer all_changes.deinit();
    const addresses = [_]u16{ 0x0800, 0x0900 };
    for (addresses) |addr| {
        const changes = try c64.callSidTrace(addr, allocator);
        defer allocator.free(changes);
        try C64.appendSidChanges(&all_changes, changes);
    }
    std.debug.print("Total SID changes: {d}\n", .{ all_changes.items.len });
    ```
    Traces SID changes from a subroutine at `$0800`, printing each change with cycle and register details.

### Cpu
The core component executing 6510 instructions, driving the virtual C64 system.

- **Fields**:
  ```zig
  pc: u16,                   // Program counter
  sp: u8,                    // Stack pointer
  a: u8,                     // Accumulator register
  x: u8,                     // X index register
  y: u8,                     // Y index register
  status: u8,                // Status register (raw byte)
  flags: CpuFlags,           // Structured status flags (e.g., carry, zero)
  opcode_last: u8,           // Last executed opcode
  cycles_executed: u32,      // Total cycles run
  cycles_since_vsync: u16,   // Cycles since last vertical sync
  cycles_since_hsync: u8,    // Cycles since last horizontal sync
  cycles_last_step: u8,      // Cycles from the last step
  mem: *Ram64k,              // Pointer to the system’s 64KB memory
  sid: *Sid,                 // Pointer to the SID / registers
  vic: *Vic,                 // Pointer to the VIC timing component
  dbg_enabled: bool,         // Enables debug logging for CPU execution
  ```
  
- **Types**:
  ```zig
  CpuFlags = struct {
      c: u1,      // Carry flag
      z: u1,      // Zero flag
      i: u1,      // Interrupt disable flag
      d: u1,      // Decimal mode flag
      b: u1,      // Break flag
      unused: u1, // Unused flag (always 1 in 6502)
      v: u1,      // Overflow flag
      n: u1,      // Negative flag
  }
  ```
  Represents the CPU status flags as individual bits.

  ```zig
  FlagBit = enum(u8) {
      negative   = 0b10000000, // Negative flag bit
      overflow   = 0b01000000, // Overflow flag bit
      unused     = 0b00100000, // Unused flag bit
      brk        = 0b00010000, // Break flag bit
      decimal    = 0b00001000, // Decimal mode flag bit
      intDisable = 0b00000100, // Interrupt disable flag bit
      zero       = 0b00000010, // Zero flag bit
      carry      = 0b00000001, // Carry flag bit
  }
  ```
  Enumerates bit masks for CPU status flags.

- **Functions**:
  ```zig
  pub fn init(
      mem: *Ram64k,
      sid: *Sid,
      vic: *Vic,
      pc_start: u16
  ) Cpu
  ```
  Initializes a new CPU instance with the given memory, SID, VIC, and starting program counter.

  ```zig
  pub fn reset(
      cpu: *Cpu
  ) void
  ```
  Resets the CPU state (registers, flags) without altering memory.

  ```zig
  pub fn hardReset(
      cpu: *Cpu
  ) void
  ```
  Performs a full reset, clearing both CPU state and memory.

  ```zig
  pub fn writeMem(
      cpu: *Cpu,
      data: []const u8,
      addr: u16
  ) void
  ```
  Writes a byte slice to memory starting at the specified address.
  - **Example**:
    ```zig
    const code = [_]u8{ 0xA9, 0x42, 0x8D, 0x00, 0xD4 }; // LDA #$42, STA $D400
    cpu.writeMem(&code, 0x0800);
    ```
    Loads a simple SID register write (osc1_freq_lo = 0x42) into memory at `$0800`.

  ```zig
  pub fn printStatus(
      cpu: *Cpu
  ) void
  ```
  Prints the current CPU status (instruction, opcodes, registers and flags).

  ```zig
  pub fn printTrace(
      cpu: *Cpu
  ) void
  ```
  Outputs a trace of the last executed instruction / simpler, more compact format than printStatus()

  ```zig
  pub fn printFlags(
      cpu: *Cpu
  ) void
  ```
  Prints the CPU’s status flags.

  ```zig
  pub fn readByte(
      cpu: *Cpu,
      addr: u16
  ) u8
  ```
  Reads a byte from memory at the given address.

  ```zig
  pub fn readWord(
      cpu: *Cpu,
      addr: u16
  ) u16
  ```
  Reads a 16-bit word from memory at the given address.

  ```zig
  pub fn readWordZP(
      cpu: *Cpu,
      addr: u8
  ) u16
  ```
  Reads a 16-bit word from zero-page memory at the given address.

  ```zig
  pub fn writeByte(
      cpu: *Cpu,
      val: u8,
      addr: u16
  ) void
  ```
  Writes a byte to memory at the specified address.

  ```zig
  pub fn writeWord(
      cpu: *Cpu,
      val: u16,
      addr: u16
  ) void
  ```
  Writes a 16-bit word to memory at the specified address (little endian).

  ```zig
  pub fn sidRegWritten(
      cpu: *Cpu
  ) bool
  ```
  Returns true if a SID register was written in the last instruction (runStep()).

  ```zig
  pub fn runStep(
      cpu: *Cpu
  ) u8
  ```
  Executes one CPU instruction, returning the number of cycles taken. The main execution function.
  - **Example**:
    ```zig
    cpu.dbg_enabled = true;
    while (cpu.runStep() != 0) {
        cpu.printTrace(); // Logs each step’s instruction and state
    }
    ```
    Runs the CPU step-by-step, printing a trace of each instruction executed.

### Ram64k
The memory component managing the C64’s 64KB address space.

- **Fields**:
  ```zig
  data: [0x10000]u8 // Array holding 64KB of memory.
  ```

- **Functions**:
  ```zig
  pub fn init() Ram64k
  ```
  Initializes a new 64KB memory instance, zero-filled.

  ```zig
  pub fn clear(
      self: *Ram64k
  ) void
  ```
  Resets all memory to zero.

### Sid
Emulates the SID chip’s register state, providing advanced tracking, decoding, and analysis of register writes.

- **Fields**:
  ```zig
  base_address: u16,       // Base memory address for SID registers (typically 0xD400)
  registers: [25]u8,       // Array of 25 SID registers
  dbg_enabled: bool,       // Enables debug logging for SID register writes and changes
  reg_written: bool,       // True if a register write occurred in the last operation
  reg_written_idx: usize,  // Index of the last written register
  reg_written_val: u8,     // Value written to the last register
  reg_changed: bool,       // True if a register value changed in the last write
  reg_changed_idx: usize,  // Index of the last changed register
  reg_changed_from: u8,    // Previous value of the last changed register
  reg_changed_to: u8,      // New value of the last changed register
  ext_reg_written: bool,   // Persistent flag for external systems, set on any write (cleared manually)
  ext_reg_changed: bool,   // Persistent flag for external systems, set on any change (cleared manually)
  last_write_cycle: usize, // CPU cycle of the last write (tracked by writeRegisterCycle)
  last_change: ?RegisterChange, // Details of the last register change, if any
  ```

- **Types**:
  ```zig
  pub const RegisterMeaning = enum(usize) {
      osc1_freq_lo = 0, osc1_freq_hi, osc1_pw_lo, osc1_pw_hi, osc1_control,
      osc1_attack_decay, osc1_sustain_release, osc2_freq_lo, osc2_freq_hi,
      osc2_pw_lo, osc2_pw_hi, osc2_control, osc2_attack_decay, osc2_sustain_release,
      osc3_freq_lo, osc3_freq_hi, osc3_pw_lo, osc3_pw_hi, osc3_control,
      osc3_attack_decay, osc3_sustain_release, filter_freq_lo, filter_freq_hi,
      filter_res_control, filter_mode_volume,
  } // Maps register indices to their SID functions
  ```
  ```zig
  pub const WaveformControl = packed struct(u8) {
      gate: bool, sync: bool, ring_mod: bool, test_bit: bool,
      triangle: bool, sawtooth: bool, pulse: bool, noise: bool,
      pub fn fromValue(val: u8) WaveformControl // Converts a value to bitfields
  } // Decodes oscillator control registers (e.g., $D404)
  ```
  ```zig
  pub const FilterResControl = packed struct(u8) {
      osc1: bool, osc2: bool, osc3: bool, ext: bool, resonance: u4,
      pub fn fromValue(val: u8) FilterResControl // Converts a value to bitfields
  } // Decodes filter resonance/routing ($D417)
  ```
  ```zig
  pub const FilterModeVolume = packed struct(u8) {
      volume: u4, low_pass: bool, band_pass: bool, high_pass: bool, osc3_off: bool,
      pub fn fromValue(val: u8) FilterModeVolume // Converts a value to bitfields
  } // Decodes filter mode and volume ($D418)
  ```
  ```zig
  pub const AttackDecay = packed struct(u8) {
      decay: u4, attack: u4,
      pub fn fromValue(val: u8) AttackDecay // Converts a value to bitfields
  } // Decodes attack/decay envelope settings (e.g., $D405)
  ```
  ```zig
  pub const SustainRelease = packed struct(u8) {
      release: u4, sustain: u4,
      pub fn fromValue(val: u8) SustainRelease // Converts a value to bitfields
  } // Decodes sustain/release envelope settings (e.g., $D406)
  ```
  ```zig
  pub const RegisterChange = struct {
      meaning: RegisterMeaning,    // Register that changed
      old_value: u8,              // Value before the change
      new_value: u8,              // Value after the change
      details: union(enum) {      // Decoded details of the new value
          waveform: WaveformControl,
          filter_res: FilterResControl,
          filter_mode: FilterModeVolume,
          attack_decay: AttackDecay,
          sustain_release: SustainRelease,
          raw: u8,
      },
  } // Captures the full context of a register change
  ```

- **Functions**:
  ```zig
  pub fn init(
      base_address: u16
  ) Sid
  ```
  Initializes a new SID instance with the specified base address, zeroing all registers and resetting tracking fields.

  ```zig
  pub fn getRegisters(
      sid: *Sid
  ) [25]u8
  ```
  Returns a copy of the current SID register values.

  ```zig
  pub fn printRegisters(
      sid: *Sid
  ) void
  ```
  Prints the current SID register values in hexadecimal format.

  ```zig
  pub fn writeRegister(
      sid: *Sid,
      reg: usize,
      val: u8
  ) void
  ```
  Writes a value to the specified SID register, updates tracking fields, sets `last_change` if altered, and logs detailed changes if `dbg_enabled` is true.
  - **Example**:
    ```zig
    sid.writeRegister(0, 0x42); // Set osc1_freq_lo to 0x42
    if (sid.reg_changed) {
        std.debug.print("Osc1 freq lo changed from {X:02} to {X:02}\n",
            .{ sid.reg_changed_from, sid.reg_changed_to });
    }
    ```
    Writes to oscillator 1’s frequency low register and checks for a change.

  ```zig
  pub fn writeRegisterCycle(
      sid: *Sid,
      reg: usize,
      val: u8,
      cycle: usize
  ) void
  ```
  Writes a value to the specified SID register, records the CPU cycle in `last_write_cycle`, updates tracking fields, sets `last_change` if altered, and logs changes if `dbg_enabled` is true.
  - **Example**:
    ```zig
    sid.dbg_enabled = true;
    sid.writeRegisterCycle(4, 0x41, 100); // Set osc1_control to Pulse+Gate at cycle 100
    if (sid.last_change) |change| {
        std.debug.print("Cycle {d}: {s} set to {X:02}\n",
            .{ change.cycle, @tagName(change.meaning), change.new_value });
        // Expected output: "Cycle 100: osc1_control set to 41"
    }
    ```
  Writes to oscillator 1’s control register with cycle info and logs the change.

  ```zig
  pub fn volumeChanged(
      change: RegisterChange
  ) bool
  ```
  Returns true if the change affects the volume register (`filter_mode_volume`, `$D418`).

  ```zig
  pub fn filterModeChanged(
      change: RegisterChange
  ) bool
  ```
  Returns true if the change affects the filter mode register (`filter_mode_volume`, `$D418`).

  ```zig
  pub fn filterFreqChanged(
      change: RegisterChange
  ) bool
  ```
  Returns true if the change affects the filter frequency registers (`filter_freq_lo` or `filter_freq_hi`, `$D415`–`$D416`).

  ```zig
  pub fn filterResChanged(
      change: RegisterChange
  ) bool
  ```
  Returns true if the change affects the filter resonance/routing register (`filter_res_control`, `$D417`).

  ```zig
  pub fn oscFreqChanged(
      change: RegisterChange,
      osc: u2
  ) bool
  ```
  Returns true if the change affects the frequency registers (`freq_lo` or `freq_hi`) of the specified oscillator (1–3).
  - **Example**:
    ```zig
    const stdout = std.io.getStdOut().writer();
    sid.writeRegisterCycle(0, 0x42, 50);  // Set osc1_freq_lo to 0x42 at cycle 50
    if (sid.last_change) |change| {
        if (Sid.oscFreqChanged(1, change)) {
            try stdout.print("Osc1 freq updated: {X:02} => {X:02}\n",
                .{ change.old_value, change.new_value });
            // Expected output: "Osc1 freq updated: 00 => 42"
        }
    }
    ```
    Checks if oscillator 1’s frequency changed after a register write, printing the update.
  

  ```zig
  pub fn oscPulseWidthChanged(
      change: RegisterChange,
      osc: u2
  ) bool
  ```
  Returns true if the change affects the pulse width registers (`pw_lo` or `pw_hi`) of the specified oscillator (1–3).

  ```zig
  pub fn oscWaveformChanged(
      change: RegisterChange,
      osc: u2
  ) bool
  ```
  Returns true if the change affects the waveform control register (`control`) of the specified oscillator (1–3).

  ```zig
  pub fn oscAttackDecayChanged(
      change: RegisterChange,
      osc: u2
  ) bool
  ```
  Returns true if the change affects the attack/decay register of the specified oscillator (1–3).
  - **Example**:
    ```zig
    const stdout = std.io.getStdOut().writer();
    sid.writeRegisterCycle(5, 0x53, 60);  // Set osc1_attack_decay to 0x53 at cycle 60
    if (sid.last_change) |change| {
        if (Sid.oscAttackDecayChanged(1, change)) {
            const ad = Sid.AttackDecay.fromValue(change.new_value);
            try stdout.print("Osc1 attack/decay: A={d}, D={d}\n",
                .{ ad.attack, ad.decay });
            // Expected output: "Osc1 attack/decay: A=5, D=3"
        }
    }
    ```
    Checks if oscillator 1’s attack/decay changed, decoding and printing the new values.

  ```zig
  pub fn oscSustainReleaseChanged(
      change: RegisterChange,
      osc: u2
  ) bool
  ```
  Returns true if the change affects the sustain/release register of the specified oscillator (1–3).

### Vic
The video timing component synchronizing CPU cycles with C64 raster behavior.

- **Fields**:
  ```zig
  model: Model,             // VIC model (PAL or NTSC)
  vsync_happened: bool,     // Flags vertical sync occurrence
  hsync_happened: bool,     // Flags horizontal sync occurrence
  badline_happened: bool,   // Indicates a bad line event
  rasterline_changed: bool, // Marks raster line updates
  rasterline: u16,          // Current raster line number
  frame_ctr: usize,         // Frame counter
  mem: *Ram64k,             // Pointer to the system’s 64KB memory
  cpu: *Cpu,                // Pointer to the CPU instance (to update cycle counters)
  dbg_enabled: bool,        // Enables debug logging for VIC timing
  ```

- **Types**:
  ```zig
  Model = enum {
      pal,    // PAL video timing
      ntsc,   // NTSC video timing
  }
  ```
  Specifies the VIC video timing model.

  ```zig
  Timing = struct {
      pub const cyclesVsyncPal = 19656,       // 63 cycles x 312 rasterlines
      pub const cyclesVsyncNtsc = 17030,      // NTSC vsync cycle count
      pub const cyclesRasterlinePal = 63,     // PAL rasterline cycles
      pub const cyclesRasterlineNtsc = 65,    // NTSC rasterline cycles
      pub const cyclesBadlineStealing = 40,   // Cycles VIC steals from CPU on badline
  }
  ```
  Defines VIC timing constants for PAL and NTSC models.

- **Functions**:
  ```zig
  pub fn init(
      cpu: *Cpu,
      mem: *Ram64k,
      vic_model: Model
  ) Vic
  ```
  Initializes a new VIC instance with the specified CPU, memory, and model (PAL/NTSC).

  ```zig
  pub fn emulateD012(
      vic: *Vic
  ) void
  ```
  Advances the raster line, updates VIC registers (e.g., `0xD011`, `0xD012`), and handles bad line timing.

  ```zig
  pub fn printStatus(
      vic: *Vic
  ) void
  ```
  Prints the current VIC status, including raster line, sync flags, and frame count.

### Asm
The assembly metadata decoder and disassembler, providing detailed instruction analysis.

- **Fields**: None — acts as a namespace for disassembly functions and types.

- **Types** Overview:
  - `Group` - Enumerates instruction categories (e.g., `branch`, `load_store`).
  - `AddrMode` - Defines addressing modes (e.g., `immediate`, `absolute_x`).
  - `OperandType` - Specifies operand kinds (e.g., `register`, `memory`).
  - `OperandSize` - Indicates operand sizes (e.g., `byte`, `word`).
  - `AccessType` - Tracks access modes (e.g., `read`, `write`).
  - `OperandId` - Identifies operands (e.g., `a` for accumulator, `memory`).
  - `Operand` - Combines operand details (id, type, size, access, bytes).
  - `Instruction` - Represents a decoded instruction with opcode, mnemonic, and operands.

- **Types**:
  ```zig
  Group = enum {
      branch,       // Jumps and branches (e.g., JSR, BEQ)
      load_store,   // Load/store ops (e.g., LDA, STA)
      control,      // CPU control (e.g., NOP, CLI)
      math,         // Arithmetic (e.g., ADC, SBC)
      logic,        // Bitwise (e.g., AND, ORA)
      compare,      // Comparisons (e.g., CMP, CPX)
      shift,        // Bit shifts (e.g., ASL, ROR)
      stack,        // Stack ops (e.g., PHA, PHP)
      transfer,     // Register transfers (e.g., TAX, TSX)
  }
  ```
  Enumerates instruction categories.

  ```zig
  AddrMode = enum {
      implied,              // No explicit operand (e.g., NOP)
      immediate,            // Literal value (e.g., LDA #$10)
      zero_page,            // Zero-page address (e.g., LDA $50)
      zero_page_x,          // Zero-page with X offset (e.g., LDA $50,X)
      zero_page_y,          // Zero-page with Y offset (e.g., LDX $50,Y)
      absolute,             // Full 16-bit address (e.g., LDA $1234)
      absolute_x,           // Absolute with X offset (e.g., STA $1234,X)
      absolute_y,           // Absolute with Y offset (e.g., LDA $1234,Y)
      indirect,             // Indirect addressing (e.g., JMP ($1234))
      indexed_indirect_x,   // Indexed indirect with X (e.g., LDA ($50,X))
      indirect_indexed_y,   // Indirect indexed with Y (e.g., LDA ($50),Y)
  }
  ```
  Defines addressing modes for instructions.

  ```zig
  OperandType = enum {
      none,       // No operand source/target (e.g., NOP)
      register,   // Direct register ops (e.g., TAX)
      memory,     // Memory access (e.g., STA)
      immediate,  // Literal value (e.g., LDA #$xx)
  }
  ```
  Specifies the type of an instruction’s operand.

  ```zig
  OperandSize = enum {
      none,   // No operand bytes
      byte,   // 8-bit operand (e.g., LDA #$10)
      word,   // 16-bit operand (e.g., LDA $1234)
  }
  ```
  Indicates the size of an operand.

  ```zig
  AccessType = struct {
      pub const none: u2 = 0x00,        // No access
      pub const read: u2 = 0x01,        // Read-only (e.g., LDA)
      pub const write: u2 = 0x02,       // Write-only (e.g., STA)
      pub const read_write: u2 = 0x03,  // Read and write (e.g., INC)
  }
  ```
  Defines operand access modes as 2-bit flags.

  ```zig
  OperandId = struct {
      pub const none: u8 = 0x00,      // No operand
      pub const a: u8 = 0x01,         // Accumulator
      pub const x: u8 = 0x02,         // X register
      pub const y: u8 = 0x04,         // Y register
      pub const sp: u8 = 0x08,        // Stack pointer
      pub const memory: u8 = 0x10,    // Memory location
      pub const constant: u8 = 0x20,  // Immediate value (e.g., #$10)
  }
  ```
  Identifies specific operands with bit flags (combinable, e.g., `memory | x`).

  ```zig
  Operand = struct {
      id: u8,             // Operand identifier (e.g., OperandId.a)
      type: OperandType,  // Operand kind (e.g., register)
      size: OperandSize,  // Operand size (e.g., byte)
      access: u2,         // Access mode (e.g., AccessType.read)
      bytes: [2]u8 = [_]u8{0, 0},  // Up to 2 bytes of operand data
      len: u8 = 0,        // Number of valid bytes in `bytes`
  }
  ```
  Describes an instruction operand.

  ```zig
  Instruction = struct {
      opcode: u8,             // Instruction opcode (e.g., 0xA9 for LDA immediate)
      mnemonic: []const u8,   // Instruction name (e.g., "LDA")
      addr_mode: AddrMode,    // Addressing mode (e.g., .immediate)
      group: Group,           // Instruction category (e.g., .load_store)
      operand1: Operand,      // Primary operand (e.g., accumulator for LDA)
      operand2: ?Operand = null,  // Optional secondary operand (e.g., X for TAX)
  }
  ```
  Represents a fully decoded 6510 instruction.
      
- **Functions**:
  ```zig
  pub fn getInstructionSize(
      insn: Instruction
  ) u8
  ```
  Returns the size of an instruction in bytes (1, 2, or 3) based on its addressing mode.

  ```zig
  pub fn disassembleForward(
      mem: []u8,
      pc_start: u16,
      count: usize
  ) !void
  ```
  Disassembles and prints `count` instructions from memory starting at `pc_start`.
  - **Example**:
    ```zig
    const mem = [_]u8{ 0xA9, 0x42, 0x8D, 0x00, 0xD4 }; // LDA #$42, STA $D400
    try Asm.disassembleForward(&mem, 0x0800, 2);
    // Prints:
    // 0800:  A9 42      LDA #$42
    // 0802:  8D 00 D4   STA $D400
    ```

  ```zig
  pub fn disassembleInsn(
      buffer: []u8,
      pc: u16,
      insn: Instruction
  ) ![]const u8
  ```
  Converts an instruction into a human-readable string (e.g., `"LDA #$10"`).
  - **Example**:
    ```zig
    const mem = [_]u8{ 0xA9, 0x42, 0x8D, 0x00, 0xD4 }; // LDA #$42, STA $D400
    try Asm.disassembleForward(&mem, 0x0800, 2);
    // Prints:
    // 0800: A9 42     LDA #$42
    // 0802: 8D 00 D4  STA $D400
    ```

  ```zig
  pub fn disassembleCodeLine(
      buffer: []u8,
      pc: u16,
      insn: Instruction
  ) ![]const u8
  ```
  Formats a full disassembly line with address, bytes, and mnemonic (e.g., `"C00C: A9 10 LDA #$10"`).

  ```zig
  pub fn decodeInstruction(
      bytes: []u8
  ) Instruction
  ```
  Decodes a byte slice into an `Instruction` struct with metadata.
  - **Example**:
    ```zig
    const bytes = [_]u8{ 0x8D, 0x00, 0xD4 }; // STA $D400
    const insn = Asm.decodeInstruction(&bytes);
    std.debug.print("{s} addr_mode: {s}\n",
        .{ insn.mnemonic, @tagName(insn.addr_mode) });
    // Prints: "STA addr_mode: absolute"
    ```

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
    if (Sid.volumeChanged(change)) {
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
    if (Sid.oscFreqChanged(change, 1)) {
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
      if (Sid.oscFreqChanged(1, change)) {
          try stdout.print("Osc1 freq updated: {X:02} => {X:02}\n",
              .{ change.old_value, change.new_value });
          // Expected output: "Osc1 freq updated: 00 => 42"
      }
      if (Sid.oscAttackDecayChanged(1, change)) {
          const ad = Sid.AttackDecay.fromValue(change.new_value);
          try stdout.print("Osc1 attack/decay: A={d}, D={d}\n",
              .{ ad.attack, ad.decay });
          // (No output here since it’s not osc1_attack_decay)
      }
  }
  sid.writeRegisterCycle(5, 0x53, 60);  // Set osc1_attack_decay to 0x53 at cycle 60
  if (sid.last_change) |change| {
      if (Sid.oscFreqChanged(1, change)) {
          try stdout.print("Osc1 freq updated: {X:02} => {X:02}\n",
              .{ change.old_value, change.new_value });
          // (No output here since it’s not a freq change)
      }
      if (Sid.oscAttackDecayChanged(1, change)) {
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
    c64.cpu.writeByte(Asm.lda_imm.opcode, 0x0800); // LDA #$0A     ; Load initial value 10
    c64.cpu.writeByte(0x0A, 0x0801);
    c64.cpu.writeByte(Asm.tax.opcode, 0x0802); // TAX          ; X = A (index for SID regs)
    c64.cpu.writeByte(Asm.adc_imm.opcode, 0x0803); // ADC #$1E     ; Add 30 to A
    c64.cpu.writeByte(0x1E, 0x0804);
    c64.cpu.writeByte(Asm.sta_absx.opcode, 0x0805); // STA $D400,X  ; Store A to SID reg X
    c64.cpu.writeByte(0x00, 0x0806);
    c64.cpu.writeByte(0xD4, 0x0807);
    c64.cpu.writeByte(Asm.inx.opcode, 0x0808); // INX          ; Increment X
    c64.cpu.writeByte(Asm.cpx_imm.opcode, 0x0809); // CPX #$19     ; Compare X with 25
    c64.cpu.writeByte(0x19, 0x080A);
    c64.cpu.writeByte(Asm.bne.opcode, 0x080B); // BNE $0803    ; Loop back if X < 25
    c64.cpu.writeByte(0xF6, 0x080C); // (offset -10)
    c64.cpu.writeByte(Asm.rts.opcode, 0x080D); // RTS          ; Return

    // Enable debugging for CPU and SID
    c64.cpu.dbg_enabled = true;
    c64.sid.dbg_enabled = true;

    // Step through the program, analyzing SID changes
    try stdout.print("\nExecuting SID sweep step-by-step...\n", .{});
    while (c64.cpu.runStep() != 0) {
        if (c64.sid.last_change) |change| {
            try stdout.print("SID register {s} changed!\n", .{@tagName(change.meaning)});

            // Check specific changes using static Sid functions
            if (Sid.volumeChanged(change)) {
                const old_vol = Sid.FilterModeVolume.fromValue(change.old_value).volume;
                const new_vol = Sid.FilterModeVolume.fromValue(change.new_value).volume;
                try stdout.print("Volume changed: {d} => {d}\n", .{ old_vol, new_vol });
            }
            if (Sid.oscWaveformChanged(change, 1)) {
                const wf = Sid.WaveformControl.fromValue(change.new_value);
                try stdout.print("Osc1 waveform updated: Pulse={}\n", .{wf.pulse});
            }
            if (Sid.oscFreqChanged(change, 1)) {
                try stdout.print("Osc1 freq updated: {X:02} => {X:02}\n", .{ change.old_value, change.new_value });
            }
            if (Sid.oscAttackDecayChanged(change, 1)) {
                const ad = Sid.AttackDecay.fromValue(change.new_value);
                try stdout.print("Osc1 attack/decay: A={d}, D={d}\n", .{ ad.attack, ad.decay });
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
zig fetch --save https://github.com/M64GitHub/zig64/archive/refs/tags/v0.3.0-alpha.tar.gz
```
This will add the dependency to your `build.zig.zon`:
```zig
.dependencies = .{
    .zig64 = .{
        .url = "https://github.com/M64GitHub/zig64/archive/refs/tags/v0.3.0-alpha.tar.gz",
        .hash = "zig64-0.3.0-v6FneuzIAwDe6e7JVVAlVQVpPveNACUk5xOI-Q1mwHR-",
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






