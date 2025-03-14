# C64 MOS6510 Emulator Core in Zig  

A **Commodore 64 MOS6510 emulator core** written in **Zig**, designed for accuracy, efficiency, and seamless integration into C64-based projects.  
This emulator provides cycle-accurate execution, video synchronization for PAL and NTSC, and SID register monitoring, making it ideal for real-time SID interaction, analysis, and execution of C64 programs.  

It serves as the **computational core of a C64 system**, making it suitable for a range of applications, from testing and debugging C64 software to powering SID music playback engines like [zigreSID](https://github.com/M64GitHub/zigreSID).  

**PRESS ANY KEY TO CONTINUE!** 🕹🔥  


**READY.**  
█  


🎧 Check out [zigreSID](https://github.com/M64GitHub/zigreSID) for SID sound emulation in Zig!  

<br>

## 🚀 Features  
- 🎮 **Fully Functional 6510 CPU Emulator** – Implements all legal 6502/6510 instructions and addressing modes.  
- 🎞 **Video Synchronization** – Execute CPU cycles in sync with PAL (19,656 cycles/frame) or NTSC (17,734 cycles/frame).  
- 🎵 **SID Register Modification Detection** – Detects when SID registers (`0xD400-0xD418`) are written to, perfect for tracking SID interaction.  
- 💾 **Program Loading Support** – Load PRG files and execute C64 programs.  
- 🛠 **CPU Debugging** – Functions for inspecting CPU registers, flags, memory, and SID states.


<br>

## Use zig64 In Your Project
```sh
zig fetch --save https://github.com/M64GitHub/6510-emulator-zig/archive/refs/tags/v0.0.1-alpha.tar.gz
```
This will add a dependency to your `build.zig.zon`:
```zig
.dependencies = .{
    .zig64 = .{
        .url = "https://github.com/M64GitHub/zig64/archive/refs/tags/v0.0.0-alpha.tar.gz",
        .hash = "122055389b1be9d6cd4e60e08ee096f130ff737b7992984305576c14a51a79ebe50a",
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
    b.installArtifact(exe);

    // ...
}
```

<br>

## Building the Project
#### Requirements:
- ⚡ **Zig** (Latest stable version)

#### Building the Example Executable:
```sh
zig build
```

#### Running the Example Executable:
```sh
zig build run
```

#### Run CPU Tests:
```sh
zig build test
```

<br>

## API Reference
### 💡 Quick Start
**To integrate the emulator into a Zig project, simply import it and initialize:**
```zig
const C64 = @import("zig64");
// initialize the cpu with the PC set to address 0x0800
// and emulate PAL system behaviour (set to NTSC if required)
var c64 = C64.init(gpa, C64.Vic.Type.pal, 0x0800);
```
**Load a program `.prg` file:**
```zig
// The second parameter (true) tells loadPrg() to set the PC to the load address,
// effectively jupming to program start. loadPrg() is currently the only function
// utilizing the allocator we set above.

const file_name = "data/test1.prg";
const load_address = try c64.loadPrg(file_name, true);
```
**Run the CPU until program end:**  
```zig
c64.run(); // returns on RTS
```
Or have more control and execute instruction by instruction:
`runStep()` returns the number of cycles executed
```zig
while (c64.cpu.runStep() != 0) {
    c64.cpu.printStatus();
}
```
**Or run the CPU a specific amount of virtual video frames:**  
`runFrames()` returns the number of frames executed.
```zig
c64.cpu.dbg_enabled = true; // will call printStatus() after each step
var frames_executed = c64.runFrames(1);
```

<br>


The `C64` struct defines the execution environment for the CPU emulation:

```zig

pub const C64 = struct {
    allocator: std.mem.Allocator,
    cpu: Cpu,
    mem: Ram64K,
    vic: Vic,
    sid: Sid,
    resid: ?*opaque {}, // optional resid integration
    dbg_enabled: bool,

    pub fn call(c64: *C64, address: u16) void {
    pub fn loadPrg(c64: *C64, file_name: []const u8, pc_to_loadaddr: bool) !u16
    pub fn runFrames(c64: *C64, frame_count: u32) u32
    pub fn setPrg(c64: *C64, program: []const u8, pc_to_loadaddr: bool) u16
    // ... ...
};

pub fn init(allocator: std.mem.Allocator, vic: Vic.Type, init_addr: u16) *C64
```

The real emulation happens in the struct `Cpu`:  
(it contains a pointer to the `C64` struct - to access the full environment)

```zig
pub const Cpu = struct {
    pc: u16,
    sp: u8,
    a: u8,
    x: u8,
    y: u8,
    status: u8,
    flags: CpuFlags,
    cycles_executed: u32,
    cycles_last_step: u32,
    opcode_last: u8,
    frame_ctr: u32,
    sid_reg_written: bool,
    ext_sid_reg_written: bool,
    dbg_enabled: bool,
    sid_dbg_enabled: bool,
    c64: *C64,

    const CpuFlags = struct {
        c: u1,
        z: u1,
        i: u1,
        d: u1,
        b: u1,
        unused: u1,
        v: u1,
        n: u1,
    };

    pub const FlagBit = enum(u8) {
        negative = 0b10000000,
        overflow = 0b01000000,
        unused = 0b000100000,
        brk = 0b000010000,
        decimal = 0b000001000,
        intDisable = 0b000000100,
        zero = 0b000000010,
        carry = 0b000000001,
    };

    pub fn init(pc_start: u16) Cpu 
    pub fn reset(cpu: *Cpu) void
    pub fn hardReset(cpu: *Cpu) void
    pub fn printStatus(cpu: *Cpu) void
    pub fn printFlags(cpu: *Cpu) void
    pub fn readByte(cpu: *Cpu, addr: u16) u8
    pub fn readWord(cpu: *Cpu, addr: u16) u16
    pub fn writeByte(cpu: *Cpu, val: u8, addr: u16) void
    pub fn writeWord(cpu: *Cpu, val: u16, addr: u16) void
    pub fn writeMem(cpu: *Cpu, data: []const u8, addr: u16) void
    pub fn sidRegWritten(cpu: *Cpu) bool
    // ... ...
};
```

The Cpu can access `c64.mem` which is defined as struct `Ram64K`:

```zig
pub const Ram64K = struct {
    data: [0x10000]u8,

    pub fn init() Ram64K
    pub fn clear(self: *Ram64K) void
};
```

The Cpu can also access a virtual SID, the `Sid` structure, and tell if register writes to the SID chip have happened during execution.

```zig
const Sid = struct {
    base_address: u16,
    registers: [25]u8,

    pub const std_base = 0xD400;

    pub fn init(base_address: u16) Sid 
    pub fn getRegisters(sid: *Sid) [25]u8 
    pub fn printRegisters(sid: *Sid) void
};
```

A virtual VIC is defined as struct `Vic`:
```zig
pub const Vic = struct {
    type: Type,

    pub const Type = enum {
        pal,
        ntsc,
    };

    pub const Timing = struct {
        const cyclesVsyncPAL = 19656;
        const cyclesVsyncNTSC = 17734;
    };

    pub fn init(victype: Type) Vic
}
```

<br>

### 📜 Emulator API

#### 🖥 **CPU Control**
```zig
// struct Cpu
pub fn init(pc_start: u16) Cpu // Initialize CPU with a start PC
pub fn reset(cpu: *Cpu) void // Reset CPU registers and PC (0xFFFC)
pub fn hardReset(cpu: *Cpu) void // Reset and clear memory
pub fn runStep(cpu: *Cpu) u8 // Execute a single instruction, return number of used cycles
```
##### 📝 **Memory Read/Write**
```zig
// struct Cpu
pub fn readByte(cpu: *Cpu, addr: u16) u8
pub fn readWord(cpu: *Cpu, addr: u16) u16
pub fn writeByte(cpu: *Cpu, val: u8, addr: u16) void
pub fn writeWord(cpu: *Cpu, val: u16, addr: u16) void
pub fn writeMem(cpu: *Cpu, data: []const u8, addr: u16) void
```
##### 🎶 **SID Register Monitoring**
```zig
// struct Cpu
pub fn sidRegWritten(cpu: *Cpu) bool

// struct Sid
pub fn getRegisters(sid: *Sid) [25]u8
pub fn printRegisters(sid: *Sid) void
```

#### ⚡ **Emulator Control**
```zig
// struct C64
// Load a .prg file into memory. Returns the load address.
// When setPC is true, the CPU.PC is set to the load address.
// This function utilizes the allocator set at CPU initialization
pub fn loadPrg(c64: *C64, file_name: []const u8, pc_to_loadaddr: bool) !u16

// Write a buffer containing a .prg to memory. Returns the load address of the .prg.
pub fn setPrg(c64: *C64, program: []const u8, pc_to_loadaddr: bool) u16

// call a subroutine (ie sid_init, sid_play) and return on RTS
pub fn call(c64: *C64, address: u16) void

pub fn run(c64: *C64) void // start execution at current PC, return on RTS
```

##### 🎞 **Frame-Based Execution** (PAL & NTSC Timing)
```zig
// struct C64
// The following function executes until a number of PAL or NTSC frames is reached
// The number of frames executed is returned
pub fn runFrames(c64: *C64, frame_count: u32) u32
```

##### 🔍 **Debugging**
```zig
// struct Cpu
pub fn printStatus(cpu: *Cpu) void
pub fn printFlags(cpu: *Cpu) void

cpu.dbg_enabled = true; // enable debug messages

// struct C64
c64.dbg_enabled = true; // enable debug messages
```

<br>

## 🕹️ Test Run
The test program `main.zig` writes a small routine into the memory, which executes a simple loop:
```
0800: A9 0A                       LDA #$0A        ; 2
0802: AA                          TAX             ; 2
0803: 69 1E                       ADC #$1E        ; 2  loop start
0805: 9D 00 D4                    STA $D400,X     ; 5  write sid register X
0808: E8                          INX             ; 2
0809: E0 19                       CPX #$19        ; 2
080B: D0 F6                       BNE $0804       ; 2/3 loop
080D: 60                          RTS             ; 6
```

It also demonstrates loading a `.prg` file via `c64.loadPrg()`, containing the same instructions.

Test Output:
```
[MAIN] Initializing CPU
[CPU ] PC: 0800 | A: 00 | X: 00 | Y: 00 | Last Opc: 00 | Last Cycl: 0 | Cycl-TT: 0 | F: 00100100
[MAIN] Writing program ...
[CPU ] PC: 0800 | A: 00 | X: 00 | Y: 00 | Last Opc: 00 | Last Cycl: 0 | Cycl-TT: 14 | F: 00100100
[MAIN] Executing program ...
[CPU ] PC: 0802 | A: 0A | X: 00 | Y: 00 | Last Opc: A9 | Last Cycl: 2 | Cycl-TT: 16 | F: 00100100
[CPU ] PC: 0803 | A: 0A | X: 0A | Y: 00 | Last Opc: AA | Last Cycl: 2 | Cycl-TT: 18 | F: 00100100
[CPU ] PC: 0805 | A: 28 | X: 0A | Y: 00 | Last Opc: 69 | Last Cycl: 2 | Cycl-TT: 20 | F: 00100100
[CPU ] PC: 0808 | A: 28 | X: 0A | Y: 00 | Last Opc: 9D | Last Cycl: 5 | Cycl-TT: 25 | F: 00100100
[MAIN] SID register written!
[CPU ] SID Registers: 00 00 00 00 00 00 00 00 00 00 28 00 00 00 00 00 00 00 00 00 00 00 00 00 00 
[CPU ] PC: 0809 | A: 28 | X: 0B | Y: 00 | Last Opc: E8 | Last Cycl: 2 | Cycl-TT: 27 | F: 00100100
[CPU ] PC: 080B | A: 28 | X: 0B | Y: 00 | Last Opc: E0 | Last Cycl: 2 | Cycl-TT: 29 | F: 00100100
[CPU ] PC: 0803 | A: 28 | X: 0B | Y: 00 | Last Opc: D0 | Last Cycl: 3 | Cycl-TT: 32 | F: 00100100
[CPU ] PC: 0805 | A: 46 | X: 0B | Y: 00 | Last Opc: 69 | Last Cycl: 2 | Cycl-TT: 34 | F: 00100100
[CPU ] PC: 0808 | A: 46 | X: 0B | Y: 00 | Last Opc: 9D | Last Cycl: 5 | Cycl-TT: 39 | F: 00100100
[MAIN] SID register written!
[CPU ] SID Registers: 00 00 00 00 00 00 00 00 00 00 28 46 00 00 00 00 00 00 00 00 00 00 00 00 00 
...
[CPU ] PC: 0809 | A: AE | X: 18 | Y: 00 | Last Opc: E8 | Last Cycl: 2 | Cycl-TT: 209 | F: 00100100
[CPU ] PC: 080B | A: AE | X: 18 | Y: 00 | Last Opc: E0 | Last Cycl: 2 | Cycl-TT: 211 | F: 00100100
[CPU ] PC: 0803 | A: AE | X: 18 | Y: 00 | Last Opc: D0 | Last Cycl: 3 | Cycl-TT: 214 | F: 00100100
[CPU ] PC: 0805 | A: CC | X: 18 | Y: 00 | Last Opc: 69 | Last Cycl: 2 | Cycl-TT: 216 | F: 00100100
[CPU ] PC: 0808 | A: CC | X: 18 | Y: 00 | Last Opc: 9D | Last Cycl: 5 | Cycl-TT: 221 | F: 00100100
[MAIN] SID register written!
[CPU ] SID Registers: 00 00 00 00 00 00 00 00 00 00 28 46 64 82 A0 BE DC FA 18 36 54 72 90 AE CC 
[MAIN] SID volume changed: CC
[CPU ] PC: 0809 | A: CC | X: 19 | Y: 00 | Last Opc: E8 | Last Cycl: 2 | Cycl-TT: 223 | F: 00100100
[CPU ] PC: 080B | A: CC | X: 19 | Y: 00 | Last Opc: E0 | Last Cycl: 2 | Cycl-TT: 225 | F: 00100100
[CPU ] PC: 080D | A: CC | X: 19 | Y: 00 | Last Opc: D0 | Last Cycl: 2 | Cycl-TT: 227 | F: 00100100
[CPU ] PC: 0001 | A: CC | X: 19 | Y: 00 | Last Opc: 60 | Last Cycl: 6 | Cycl-TT: 233 | F: 00100100
...
```

<br>

## 🔓 License
This emulator is released under the **MIT License**, allowing free modification and distribution.

<br>

## 🌐 Related Projects  
- 🎧 **[zigreSID](https://github.com/M64GitHub/zigreSID)** – A SID sound emulation library for Zig, integrating with this emulator for `.sid` file playback.

<br>

## 🏆 Credits
Developed with ❤️ by **M64**  
### Hall Of Fame
- **Commodore Business Machines (CBM)** – `The OGs of retro computing!`
  Engineers of the C64, MOS 6510/6581/8580,  sparked the 8-bit uprising! 🔥🔥🔥  
- **Zig Team** – `Forger of the ultimate language` 
  where low-level control meets modern simplicity! ⚡ No GC, no nonsense, just raw POWER! ⚡  
- **C64 Demo Scene** – `The demigods of 8-bit artistry!`
  Code, SID music, and pixel art, pushed beyond all limits! 👾👾 👾  

SAVE "RESPECT.",8,1 💾


**READY.**  
█

<br>

## 🚀 Get Started Now!
Clone the repository and start experimenting:
```sh
git clone https://github.com/M64GitHub/zig64.git
cd zig64
zig build
```
Enjoy bringing the **C64 CPU to life in Zig!** 🕹🔥






