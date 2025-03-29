# Commodore 64 MOS 6510 Emulator Core

![Tests](https://github.com/M64GitHub/flagZ/actions/workflows/test.yml/badge.svg)
![License](https://img.shields.io/badge/license-MIT-brightgreen?style=flat)
![Version](https://img.shields.io/badge/version-0.2.0-8a2be2?style=flat)
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
    try stdout.print("Loaded 'example.prg' at ${X:0>4}\n\n", .{load_address});
    try Asm.disassembleForward(&c64.mem.data, load_address, 10);

    // Run the program
    try stdout.print("\nRunning...\n", .{});
    try c64.run();
}
```


## Overview

This emulator is structured as a set of modular components, forming the foundation of the virtual C64 system. These building blocks include:

- `C64`: The central emulator struct and component container, managing program loading and execution.
- `Cpu`: Executes 6510 instructions.
- `Ram64k`: Manages 64KB of memory.
- `Vic`: Controls video timing.
- `Sid`: Serves as a (for now) register placeholder.
- `Asm`: Provides assembly metadata decoding and disassembly.

Each component features its own `dbg_enabled` flag—e.g., `c64.dbg_enabled` for emulator logs, `cpu.dbg_enabled` for execution details—enabling targeted debugging. The `Cpu` powers the system, running code and tracking SID register writes, while `Vic` ensures cycle-accurate timing.  
The `Asm` struct enhances this core with a powerful disassembler and metadata decoder, offering detailed instruction analysis.  
The sections below outline their mechanics, API, and examples to guide you in using this emulator core effectively.

### Inner Workings

#### C64: System Coordinator
The `C64` struct initializes and links the emulator’s components, loading `.prg` files into `Ram64k` and directing `Cpu` execution via `call`, `run` or `runFrames`. It acts as the entry point, managing memory and timing interactions.

#### Cpu: Execution Engine
The `Cpu` fetches and executes 6510 instructions from `Ram64k`, updating registers and tracking SID register writes through `sidRegWritten`. It syncs with `Vic` for cycle accuracy, stepping through code with `runStep`.

#### Ram64k: Memory Backbone
`Ram64k` provides a 64KB memory array, serving as the shared storage for `Cpu` instructions, `Vic` registers, and `Sid` data. It supports direct writes from `C64.loadPrg` and `Cpu.writeByte`.

#### Vic: Timing Keeper
`Vic` emulates raster timing, advancing lines with `emulateD012` and signaling sync events like vsync or bad lines to `Cpu`. It uses `model` (PAL/NTSC) to adjust cycle counts, ensuring accurate interrupt timing.

#### Sid: Register Holder
The `Sid` struct stores register values at a configurable `base_address`, updated by `Cpu` writes. It offers `getRegisters` for inspection, with future potential for sound logic.

#### Asm: Instruction Decoder
`Asm` decodes raw bytes into `Instruction` structs via `decodeInsn`, providing metadata like addressing modes and operands. Functions like `disassembleCodeLine` format this data into readable output, aiding analysis.

## API Reference
### C64
The main emulator struct, combining CPU, memory, VIC, and SID for a complete C64 system.

- **Fields**:
  - `cpu: Cpu` - The 6510 CPU instance.
  - `mem: Ram64k` - 64KB memory.
  - `vic: Vic` - Video timing component.
  - `sid: Sid` - SID register tracker.
  - `dbg_enabled: bool` - Enables debug logging for the emulator.

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
  - `pc: u16` - Program counter.
  - `sp: u8` - Stack pointer.
  - `a: u8` - Accumulator register.
  - `x: u8` - X index register.
  - `y: u8` - Y index register.
  - `status: u8` - Status register (raw byte).
  - `flags: CpuFlags` - Structured status flags (e.g., carry, zero).
  - `opcode_last: u8` - Last executed opcode.
  - `cycles_executed: u32` - Total cycles run.
  - `cycles_since_vsync: u16` - Cycles since last vertical sync.
  - `cycles_since_hsync: u8` - Cycles since last horizontal sync.
  - `cycles_last_step: u8` - Cycles from the last step.
  - `sid_reg_changed: bool` - Indicates SID register changes detected in current instructon.
  - `sid_reg_written: bool` - Flags SID register writes in current instruction.
  - `ext_sid_reg_written: bool` - Flags SID register writes. To be manually cleared. Used for C64.call().
  - `ext_sid_reg_changed: bool` - Indicates SID register changes. Manually clear.
  - `mem: *Ram64k` - Pointer to the system’s 64KB memory.
  - `sid: *Sid` - Pointer to the SID / registers.
  - `vic: *Vic` - Pointer to the VIC timing component.
  - `dbg_enabled: bool` - Enables debug logging for CPU execution.

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
  - `data: [0x10000]u8` - Array holding 64KB of memory.

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
  - `base_address: u16` - Base memory address for SID registers (typically `0xD400`).
  - `registers: [25]u8` - Array of 25 SID registers.
  - `dbg_enabled: bool` - Enables debug logging for SID register values.

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
  - `model: Model` - VIC model (PAL or NTSC).
  - `vsync_happened: bool` - Flags vertical sync occurrence.
  - `hsync_happened: bool` - Flags horizontal sync occurrence.
  - `badline_happened: bool` - Indicates a bad line event.
  - `rasterline_changed: bool` - Marks raster line updates.
  - `rasterline: u16` - Current raster line number.
  - `frame_ctr: usize` - Frame counter.
  - `mem: *Ram64k` - Pointer to the system’s 64KB memory.
  - `cpu: *Cpu` - Pointer to the CPU instance (to update cycle counters).
  - `dbg_enabled: bool` - Enables debug logging for VIC timing.

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

- **Types**:
  - `Group` - Enumerates instruction categories (e.g., `branch`, `load_store`).
  - `AddrMode` - Defines addressing modes (e.g., `immediate`, `absolute_x`).
  - `OperandType` - Specifies operand kinds (e.g., `register`, `memory`).
  - `OperandSize` - Indicates operand sizes (e.g., `byte`, `word`).
  - `AccessType` - Tracks access modes (e.g., `read`, `write`).
  - `OperandId` - Identifies operands (e.g., `a` for accumulator, `memory`).
  - `Operand` - Combines operand details (id, type, size, access, bytes).
  - `Instruction` - Represents a decoded instruction with opcode, mnemonic, and operands.

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
  pub fn decodeInsn(
      bytes: []u8
  ) Instruction
  ```
  Decodes a byte slice into an `Instruction` struct with metadata.




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
zig fetch --save https://github.com/M64GitHub/zig64/archive/refs/tags/v0.2.0-alpha.tar.gz
```
This will add the dependency to your `build.zig.zon`:
```zig
.dependencies = .{
    .zig64 = .{
        .url = "https://github.com/M64GitHub/zig64/archive/refs/tags/v0.2.0-alpha.tar.gz",
        .hash = "zig64-0.2.0-v6FneuiXAwDZ6n7QNBVykEJsMxkbIyfHTNqdjy_ZZ_3l",
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






