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
- 🎵 **SID Register Monitoring**  
  Tracks all writes to SID registers, enabling detailed analysis and debugging of audio interactions.
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

### Component Interactions

**C64: Emulator Core**  
The `C64` struct serves as the main struct, initializing components and loading `.prg` files into `Ram64k` with `loadPrg()`. It directs `Cpu` execution through `run()`, `runFrames()`, or `call()`, the latter clearing and tracking SID register changes during subroutine execution (flag `ext_sid_reg_written`, see below).

**Cpu: Execution Engine**  
The `Cpu` drives execution by fetching instructions from `Ram64k` and stepping via `runStep()`, syncing cycles with `Vic`. It tracks `Sid` writes with `sidRegWritten()` (cleared each step) and `ext_sid_reg_written` (persistent until manually cleared), updating register states.

**Ram64k: System RAM**  
`Ram64k` acts as the central memory pool, accepting writes from `C64.loadPrg()` and `Cpu.writeByte()`. It feeds instruction data to `Cpu` and register values to `Vic` and `Sid`, ensuring system-wide consistency.

**Vic: Video Timing / Raster Beamer**  
`Vic` regulates timing by advancing raster lines with `emulateD012()`, notifying `Cpu` of vsync or bad line events. It adjusts `Cpu` cycle counts based on `model` (PAL/NTSC), maintaining accurate emulation timing.

**Sid: Register Management**
The `Sid` struct manages its register state, mapped into C64 memory at `base_address` (typically `$D400`), providing a robust interface for tracking and analyzing writes from the `Cpu`. Register updates are handled through two key functions: `writeRegister(reg: usize, val: u8)` for general-purpose writes and `writeRegisterCycle(reg: usize, val: u8, cycle: u64)` for cycle-specific tracking. Both functions maintain the internal `[25]u8` register array, accessible via `getRegisters()` for state inspection.

- **Write Tracking**: Each write sets `reg_written` to the target register index and `reg_written_val` to its value, with `ext_reg_written` signaling external systems of the update (persistent until manually cleared). The `writeRegisterCycle()` function additionally records the CPU cycle of the write in `last_write_cycle`, enabling precise tracking of when the write occurred.
- **Change Detection**: If a write alters a register’s value, `reg_changed` and `ext_reg_changed` flags are set, with detailed state (`reg_changed_idx`, `reg_changed_from`, `reg_changed_to`) recorded for debugging or hooking. Debug output, enabled via `dbg_enabled`, logs all writes and changes with register addresses (offset from `$D400`), values, and cycles (when applicable).
- **Integration**: The `Cpu` delegates SID register writes during execution, offloading state management to `Sid`. 

**Asm: Instruction Decoder**  
`Asm` processes `Ram64k` bytes into `Instruction` structs with `decodeInstruction()`, enabling `Cpu` code analysis. Its `disassembleCodeLine()` function format this data into readable output.

## API Reference
### C64
The main emulator struct, combining CPU, memory, VIC, and SID for a complete C64 system.

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
  ) !*C64
  ```
  Initializes a new heap-allocated C64 instance with default settings.

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
  Loads a `.prg` file into memory and returns the load address.

  ```zig
  pub fn run(
      c64: *C64
  ) void
  ```
  Executes the CPU until program termination (RTS).

  ```zig
  pub fn call(
      c64: *C64,
      address: u16
  ) void
  ```
  Calls a specific assembly subroutine, returning on RTS.

  ```zig
  pub fn runFrames(
      c64: *C64,
      frame_count: u32
  ) u32
  ```
  Runs the CPU for a specified number of frames, returning the number executed; frame timing adapts to PAL or NTSC VIC settings.


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
  sid_reg_changed: bool,     // Indicates SID register changes detected in current instructon
  sid_reg_written: bool,     // Flags SID register writes in current instruction
  ext_sid_reg_written: bool, // Flags SID register writes. To be manually cleared. Used for C64.call()
  ext_sid_reg_changed: bool, // Indicates SID register changes. Manually clear.
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
The placeholder component for SID register storage.

- **Fields**:
  ```zig
  base_address: u16,   // Base memory address for SID registers (typically 0xD400)
  registers: [25]u8,   // Array of 25 SID registers
  dbg_enabled: bool,   // Enables debug logging for SID register values
  ```

- **Functions**:
  ```zig
  pub fn init(
      base_address: u16
  ) Sid
  ```
  Initializes a new SID instance with the specified base address, zeroing all registers.

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

  ```zig
  pub fn disassembleInsn(
      buffer: []u8,
      pc: u16,
      insn: Instruction
  ) ![]const u8
  ```
  Converts an instruction into a human-readable string (e.g., `"LDA #$10"`).

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

## Example Code

Below are practical examples to demonstrate using the zig64 emulator core. Starting with short snippets for specific tasks, followed by a complete example of manually programming and stepping through a routine.

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

### Full Example: Programming and Stepping a SID Routine
```zig
const std = @import("std");
const C64 = @import("zig64");
const Asm = C64.Asm;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();

    // Initialize the C64 emulator
    var c64 = try C64.init(allocator, C64.Vic.Model.pal, 0x0800);
    defer c64.deinit(allocator);

    // Print initial emulator state
    try stdout.print("CPU init address: ${X:0>4}\n", .{c64.cpu.pc});
    try stdout.print("VIC type: {s}\n", .{@tagName(c64.vic.model)});
    try stdout.print("SID base address: ${X:0>4}\n", .{c64.sid.base_address});

    // Write a small program to memory (SID register sweep)
    try stdout.print("\nWriting program to $0800...\n", .{});
    c64.cpu.writeByte(Asm.lda_imm.opcode, 0x0800);    // LDA #$0A
    c64.cpu.writeByte(0x0A, 0x0801);
    c64.cpu.writeByte(Asm.tax.opcode, 0x0802);        // TAX
    c64.cpu.writeByte(Asm.adc_imm.opcode, 0x0803);    // ADC #$1E
    c64.cpu.writeByte(0x1E, 0x0804);
    c64.cpu.writeByte(Asm.sta_absx.opcode, 0x0805);   // STA $D400,X
    c64.cpu.writeByte(0x00, 0x0806);
    c64.cpu.writeByte(0xD4, 0x0807);
    c64.cpu.writeByte(Asm.inx.opcode, 0x0808);        // INX
    c64.cpu.writeByte(Asm.cpx_imm.opcode, 0x0809);    // CPX #$19
    c64.cpu.writeByte(0x19, 0x080A);
    c64.cpu.writeByte(Asm.bne.opcode, 0x080B);        // BNE $0803
    c64.cpu.writeByte(0xF6, 0x080C);
    c64.cpu.writeByte(Asm.rts.opcode, 0x080D);        // RTS

    // Step through the program, monitoring SID changes
    try stdout.print("\nExecuting program step-by-step...\n", .{});
    c64.cpu.dbg_enabled = true;
    var sid_volume_old = c64.sid.getRegisters()[24];
    while (c64.cpu.runStep() != 0) {
        if (c64.cpu.sidRegWritten()) {
            try stdout.print("SID register written!\n", .{});
            c64.sid.printRegisters();
            const sid_volume = c64.sid.getRegisters()[24];
            if (sid_volume_old != sid_volume) {
                try stdout.print("SID volume changed: ${X:0>2}\n", .{sid_volume});
                sid_volume_old = sid_volume;
            }
        }
    }
}
```
Manually writes a program to sweep SID registers, executes it step-by-step, and monitors volume changes.

Output:
```
[EXE] Executing program ...
[cpu] PC: 0800 | A9 0A    | LDA #$0A     | A: 00 | X: 00 | Y: 00 | SP: FF | Cycl: 00 | Cycl-TT: 14 | FL: 00100100
[cpu] PC: 0802 | AA       | TAX          | A: 0A | X: 00 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 16 | FL: 00100100
[cpu] PC: 0803 | 69 1E    | ADC #$1E     | A: 0A | X: 0A | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 18 | FL: 00100100
[cpu] PC: 0805 | 9D 00 D4 | STA $D400,X  | A: 28 | X: 0A | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 20 | FL: 00100100
[EXE] sid register written!
[sid] registers: 00 00 00 00 00 00 00 00 00 00 28 00 00 00 00 00 00 00 00 00 00 00 00 00 00 
[cpu] PC: 0808 | E8       | INX          | A: 28 | X: 0A | Y: 00 | SP: FF | Cycl: 04 | Cycl-TT: 24 | FL: 00100100
[cpu] PC: 0809 | E0 19    | CPX #$19     | A: 28 | X: 0B | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 26 | FL: 00100100
[cpu] PC: 080B | D0 F6    | BNE $0803    | A: 28 | X: 0B | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 28 | FL: 10100100
[cpu] PC: 0803 | 69 1E    | ADC #$1E     | A: 28 | X: 0B | Y: 00 | SP: FF | Cycl: 03 | Cycl-TT: 31 | FL: 10100100
[cpu] PC: 0805 | 9D 00 D4 | STA $D400,X  | A: 46 | X: 0B | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 33 | FL: 00100100
[EXE] sid register written!
[sid] registers: 00 00 00 00 00 00 00 00 00 00 28 46 00 00 00 00 00 00 00 00 00 00 00 00 00
...
[sid] registers: 00 00 00 00 00 00 00 00 00 00 28 46 64 82 A0 BE DC FA 18 36 54 72 90 AE 00 
[cpu] PC: 0808 | E8       | INX          | A: AE | X: 17 | Y: 00 | SP: FF | Cycl: 04 | Cycl-TT: 193 | FL: 10100100
[cpu] PC: 0809 | E0 19    | CPX #$19     | A: AE | X: 18 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 195 | FL: 00100100
[cpu] PC: 080B | D0 F6    | BNE $0803    | A: AE | X: 18 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 197 | FL: 10100100
[cpu] PC: 0803 | 69 1E    | ADC #$1E     | A: AE | X: 18 | Y: 00 | SP: FF | Cycl: 03 | Cycl-TT: 200 | FL: 10100100
[cpu] PC: 0805 | 9D 00 D4 | STA $D400,X  | A: CC | X: 18 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 202 | FL: 10100100
[EXE] sid register written!
[sid] registers: 00 00 00 00 00 00 00 00 00 00 28 46 64 82 A0 BE DC FA 18 36 54 72 90 AE CC 
[EXE] sid volume changed: CC
[cpu] PC: 0808 | E8       | INX          | A: CC | X: 18 | Y: 00 | SP: FF | Cycl: 44 | Cycl-TT: 246 | FL: 10100100
[cpu] PC: 0809 | E0 19    | CPX #$19     | A: CC | X: 19 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 248 | FL: 00100100
[cpu] PC: 080B | D0 F6    | BNE $0803    | A: CC | X: 19 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 250 | FL: 00100111
[cpu] PC: 080D | 60       | RTS          | A: CC | X: 19 | Y: 00 | SP: FF | Cycl: 02 | Cycl-TT: 252 | FL: 00100111
[cpu] RTS EXIT!
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






