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
  ) !void
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






