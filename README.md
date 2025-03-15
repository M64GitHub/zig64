# C64 MOS6510 Emulator Core in Zig  

A **Commodore 64 MOS6510 emulator core** written in **Zig**, designed for accuracy, efficiency, and seamless integration into C64-based projects.  
This emulator provides cycle-accurate execution, video synchronization for PAL and NTSC systems via rasterbeam emulation, and SID register monitoring, making it ideal for analysis of SID interacting programs, and the execution of C64 programs in general.  

It serves as the **computational core of a C64 system**, making it suitable for a range of applications, from testing and debugging C64 software to powering SID music playback engines like [zigreSID](https://github.com/M64GitHub/zigreSID).  

**PRESS ANY KEY TO CONTINUE!** 🕹🔥  


**READY.**  
█  


🎧 Check out [zigreSID](https://github.com/M64GitHub/zigreSID) for SID sound emulation in Zig!  

<br>

## 🚀 Features  
- 🎮 **Fully Functional 6510 CPU Emulator** – Implements all legal `MOS 6502/6510` instructions and addressing modes.  
- 🎞 **Video Synchronization** – Execute CPU cycles in sync with PAL or NTSC, full `rasterbeam` emulation, exactly handling `bad lines`.  
- 🎵 **SID Register Modification Detection** – Detects when SID registers are written to, perfect for tracking SID interaction.  
- 💾 **Program Loading Support** – Load PRG files and execute C64 programs.  
- 🛠 **CPU Debugging** – Functions for inspecting CPU registers, flags, memory, VIC state, and SID registers.

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

## Using zig64 In Your Project
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

## API Reference
### 💡 Quick Start
**To integrate the emulator into a Zig project, simply import it and initialize:**
```zig
const C64 = @import("zig64");
// initialize the cpu with the PC set to address 0x0800
// and emulate PAL system behaviour (set to NTSC if required)
const gpa = std.heap.page_allocator;
var c64 = C64.init(gpa, C64.Vic.Type.pal, 0x0800);
```
**Load a program `.prg` file:**
```zig
// the second parameter (true) tells loadPrg() to set the PC to the load address,
// effectively jupming to program start.
const file_name = "data/test1.prg";
const load_address = try c64.loadPrg(gpa, file_name, true);
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
c64.cpu_dbg_enabled = true; // will call printStatus() after each step
var frames_executed = c64.runFrames(1);
```

<br>


The `C64` struct defines the execution environment for the CPU emulation:

```zig

pub const C64 = struct {
    allocator: std.mem.Allocator,
    cpu: Cpu,
    mem: Ram64k,
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
    opcode_last: u8,
    cycles_executed: u32,
    cycles_since_vsync: u16,
    cycles_since_hsync: u8,
    cycles_last_step: u8,
    sid_reg_written: bool,
    ext_sid_reg_written: bool,
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

    pub fn init(c64: *C64, pc_start: u16) Cpu
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

The Cpu can access `c64.mem` which is defined as struct `Ram64k`:

```zig
pub const Ram64k = struct {
    data: [0x10000]u8,

    pub fn init() Ram64k
    pub fn clear(self: *Ram64k) void
};
```

The Cpu can also access a virtual SID, the `Sid` structure, and tell if register writes to the SID chip have happened during execution.

```zig
const Sid = struct {
    base_address: u16,
    registers: [25]u8,
    c64: *C64,

    pub const std_base = 0xD400;

    pub fn init(c64: *C64, base_address: u16) Sid
    pub fn getRegisters(sid: *Sid) [25]u8 
    pub fn printRegisters(sid: *Sid) void
};
```

A virtual VIC is defined as struct `Vic`:
```zig
pub const Vic = struct {
    model: Model,
    vsync_happened: bool,
    hsync_happened: bool,
    badline_happened: bool,
    rasterline_changed: bool,
    rasterline: u16,
    frame_ctr: usize,
    c64: *C64,

    pub const Model = enum {
        pal,
        ntsc,
    };

    pub const Timing = struct {
        const cyclesVsyncPal = 19656; // 63 cycles x 312 rasterlines
        const cyclesVsyncNtsc = 17030;
        const cyclesRasterlinePal = 63;
        const cyclesRasterlineNtsc = 65;
        const cyclesBadlineStealing = 40; // cycles vic steals cpu on badline
    };

    pub fn init(c64: *C64, vic_model: Model) Vic
    pub fn emulateD012(vic: *Vic) void // rasterbeam emulation
    pub fn printStatus(vic: *Vic) void
}
```

<br>

### 📜 Emulator API

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

#### 🖥 **CPU Control**
```zig
// struct Cpu
pub fn init(c64: *C64, pc_start: u16) Cpu // init with start address
pub fn reset(cpu: *Cpu) void // reset CPU registers and PC (0xFFFC)
pub fn hardReset(cpu: *Cpu) void // reset and clear memory
pub fn runStep(cpu: *Cpu) u8 // execute a single instruction, return number of used cycles
```
##### 🎞 **Frame-Based Execution** (PAL & NTSC Timing)
```zig
// struct C64
// The following function executes until a number of PAL or NTSC frames is reached
// The number of frames executed is returned
pub fn runFrames(c64: *C64, frame_count: u32) u32
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

##### 🎶 **VIC Rasterbeam Handling**
```zig

    vsync_happened: bool,
    hsync_happened: bool,
    badline_happened: bool,
    rasterline_changed: bool,
    rasterline: u16,
    frame_ctr: usize,
```



##### 🔍 **Debugging**
```zig
// enable specific debugging on struct C64
// struct C64
c64.dbg_enabled = true; // enable debug messages for the emulator
c64.cpu_dbg_enabled = true; // enable debug messages for the cpu
c64.sid_dbg_enabled = true; // enable debug messages for the sid
c64.vic_dbg_enabled = true; // enable debug messages for the vic

// or manually call the functions
// struct Cpu
pub fn printStatus(cpu: *Cpu) void
pub fn printFlags(cpu: *Cpu) void

// struct Sid
pub fn printRegisters(sid: *Sid) void {

//struct Vic
pub fn printStatus(vic: *Vic) void {
```

<br>

## 🕹️ Test Run
The test program `writebytes-example.zig` writes a small routine into the memory, which executes a simple loop:
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
...
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






