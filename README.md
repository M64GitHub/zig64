# C64 Emulator Core in Zig  
![Tests](https://github.com/M64GitHub/flagZ/actions/workflows/test.yml/badge.svg)
![License](https://img.shields.io/badge/license-MIT-brightgreen?style=flat)
![Zig](https://img.shields.io/badge/Zig-0.14.0-orange?style=flat)

A **Commodore 64 MOS6510 emulator core** written in **Zig**, designed for accuracy, efficiency, and seamless integration into C64-based projects.  
This emulator delivers cycle-accurate execution, precise rasterbeam emulation for PAL and NTSC video synchronization, and SID register tracking. Designed for C64 software analysis and program execution, it ensures faithful reproduction of C64 behavior with high precision.

It serves as the **computational core of a C64 system**, making it suitable for a range of applications, from testing and debugging C64 software to powering SID music playback engines like 🎧 [zigreSID](https://github.com/M64GitHub/zigreSID).  

**PRESS ANY KEY TO CONTINUE!** 🕹🔥  


**READY.**  
█  

<br>

## 🚀 Features  
- 🎮 **Fully Functional 6510 CPU Emulator** – Implements all legal `MOS 6502/6510` instructions and addressing modes with pinpoint accuracy.  
- 🎞 **Video Synchronization** – Executes CPU cycles in perfect harmony with PAL or NTSC, featuring full `rasterbeam` emulation and precise `bad line` handling.  
- 🎵 **SID Register Modification Detection** – Tracks every write to SID registers, ideal for debugging and analyzing SID interactions.  
- 💾 **Program Loading Support** – Seamlessly loads `.prg` files to run C64 programs like a real machine.  
- 🛠 **CPU Debugging** – Robust tools to inspect CPU registers, flags, memory, VIC state, and SID registers in real-time.  
- 🔍 **Disassembler / Instruction Metadata Decoder** – Decodes 6502/6510 opcodes into human-readable mnemonics, enriched with metadata like size, instruction group, addressing mode, operand type, size, access type, and more for seamless code tracing.
<br>

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
zig fetch --save https://github.com/M64GitHub/zig64/archive/refs/tags/v0.1.0-alpha.tar.gz
```
This will add the dependency to your `build.zig.zon`:
```zig
.dependencies = .{
    .zig64 = .{
        .url = "https://github.com/M64GitHub/zig64/archive/refs/tags/v0.1.0-alpha.tar.gz",
        .hash = "zig64-0.0.1-v6Fnep8yAQAjAZlp64lmwl3GNnMjO1wo5yY3IYWMse9p",
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
**Load a `.prg` file:**
```zig
// the second parameter (true) tells loadPrg() to set the Cpu.PC 
// to the load address, effectively jupming to program start.
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
// Load a .prg file into memory, returns the load address
// When pc_to_loadaddr is true, the CPU.PC is set to the load address
// This function utilizes the allocator set at CPU initialization
pub fn loadPrg(c64: *C64, file_name: []const u8, pc_to_loadaddr: bool) !u16

// Write a buffer containing a .prg to memory, 
// returns the load address of the .prg
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

// execute a single instruction, return number of used cycles
pub fn runStep(cpu: *Cpu) u8 

// run for specific amount of video frames, return number of frames executed
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

##### 📺 **VIC Rasterbeam Monitoring**
```zig
// struct Vic
// the following flags will be set by the Cpu on execution, after each step:
vsync_happened: bool,       // true when a vertical sync happened
hsync_happened: bool,       // true when a horizontal sync happened
badline_happened: bool,     // true when a badline happened (rasterline % 8 == 3)
rasterline_changed: bool,   // true when the current rasterline changed
rasterline: u16,            // number of the current rasterline
frame_ctr: usize,           // total number of video frames
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
Cpu.printStatus()
Cpu.printFlags()
Sid.printRegisters()
Vic.printStatus()
```

<br>

## 🕹️ Examples
Example code can be found in the folder `src/examples`.

### Loading and Executing a demo program, disassembler
The program `loadprg-example.zig` demonstrates how to load and run a `.prg`. 
It also shows how to disassemble code.


```zig
// zig64 - loadPrg() example
const std = @import("std");

const C64 = @import("zig64");
const flagz = @import("flagz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    const Args = struct {
        prg: []const u8,
    };

    const args = try flagz.parse(Args, allocator);
    defer flagz.deinit(args, allocator);

    try stdout.print("[EXE] initializing emulator\n", .{});
    var c64 = try C64.init(allocator, C64.Vic.Model.pal, 0x0000);
    defer c64.deinit(allocator);

    // full debug output
    c64.dbg_enabled = true;
    c64.cpu_dbg_enabled = true;
    c64.vic_dbg_enabled = true;
    c64.sid_dbg_enabled = true;

    // load a .prg file from disk
    try stdout.print("[EXE] Loading '{s}'\n", .{args.prg});
    const load_address = try c64.loadPrg(allocator, args.prg, true);
    try stdout.print("[EXE] Load address: {X:0>4}\n\n", .{load_address});

    // disassemble 31 instructions
    try stdout.print("[EXE] Disassembling from: {X:0>4}\n", .{load_address});
    c64.cpu.disassemble(load_address, 31);
    try stdout.print("\n\n", .{});

    try stdout.print("[EXE] RUN\n", .{});
    c64.run();
}
```


**Running the Example:**
```sh
zig build run-loadprg -- -f c64asm/test.prg
```

**Example Output:**
```
[EXE] initializing emulator
[EXE] Loading 'c64asm/test.prg'
[c64] loading file: 'c64asm/test.prg'
[c64] file load address: $C000
[c64] writing mem: C000 offs: 0002 data: 78
[c64] writing mem: C001 offs: 0003 data: A9
[c64] writing mem: C002 offs: 0004 data: 00
...
...
[EXE] Disassembling from: C000
$C000: SEI
$C001: LDA #$00
$C003: STA $01
$C005: LDX #$FF
$C007: TXS
$C008: LDY #$00
$C00A: LDA #$41
$C00C: STA $0400,Y
$C00F: LDA #$01
$C011: STA $D800,Y
$C014: INY
$C015: CPY #$FF
$C017: BNE $C00A
$C019: LDA #$05
$C01B: LDX #$03
$C01D: CLC
$C01E: ADC #$02
$C020: DEX
$C021: BNE $C01D
$C023: STA $D020
$C026: LDA #$00
$C028: CMP #$01
$C02A: BEQ $C02E
$C02C: BMI $C031
$C02E: JMP $C036
$C031: LDA #$FF
$C033: STA $D021
$C036: LDA #$37
$C038: STA $01
$C03A: CLI
$C03B: RTS
[cpu] PC: C001 | A: 00 | X: 00 | Y: 00 | Last Opc: 78 | Last Cycl: 2 | Cycl-TT: 2 | FL: 00100100
[vic] RL 0000 | VSYNC: false | HSYNC: false | BL: false | RL-CHG: false | FRM: 0
[cpu] PC: C003 | A: 00 | X: 00 | Y: 00 | Last Opc: A9 | Last Cycl: 2 | Cycl-TT: 4 | FL: 00100110
[vic] RL 0000 | VSYNC: false | HSYNC: false | BL: false | RL-CHG: false | FRM: 0
[cpu] PC: C005 | A: 00 | X: 00 | Y: 00 | Last Opc: 85 | Last Cycl: 3 | Cycl-TT: 7 | FL: 00100110
[vic] RL 0000 | VSYNC: false | HSYNC: false | BL: false | RL-CHG: false | FRM: 0
...
...
[cpu] PC: C03B | A: 37 | X: 00 | Y: FF | Last Opc: 58 | Last Cycl: 2 | Cycl-TT: 5863 | FL: 00100000
[vic] RL 0056 | VSYNC: false | HSYNC: false | BL: false | RL-CHG: false | FRM: 0
[cpu] Return to 0000
[cpu] Return EXIT!
```


### Manually writing a program into memory
The test program `writebytes-example.zig` writes a small routine into the memory, which executes a simple loop. Since it writes to `$D400,X`, the emulator will detect SID register changes:


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


```zig
c64.cpu.writeByte(0xa9, 0x0800); //  LDA,,
c64.cpu.writeByte(0x0a, 0x0801); //      #0A     ; 10
c64.cpu.writeByte(0xaa, 0x0802); //  TAX
c64.cpu.writeByte(0x69, 0x0803); //  ADC
c64.cpu.writeByte(0x1e, 0x0804); //      #$1E
c64.cpu.writeByte(0x9d, 0x0805); //  STA $
c64.cpu.writeByte(0x00, 0x0806); //         00
c64.cpu.writeByte(0xd4, 0x0807); //       D4
c64.cpu.writeByte(0xe8, 0x0808); //  INX
c64.cpu.writeByte(0xe0, 0x0809); //  CPX
c64.cpu.writeByte(0x19, 0x080A); //      #19
c64.cpu.writeByte(0xd0, 0x080B); //  BNE
c64.cpu.writeByte(0xf6, 0x080C); //      $0803 (-10)
c64.cpu.writeByte(0x60, 0x080D); //  RTS
```

**Running the Example:**
```sh
zig build run-writebyte
```

**Example Output:**
```
[EXE] initializing emulator
[EXE] cpu init address: 0800
[EXE] c64 vic type: pal
[EXE] c64 sid base address: D400
[EXE] cpu status:
[cpu] PC: 0800 | A: 00 | X: 00 | Y: 00 | Last Opc: 00 | Last Cycl: 0 | Cycl-TT: 0 | FL: 00100100
[EXE] Writing program ...
[cpu] PC: 0800 | A: 00 | X: 00 | Y: 00 | Last Opc: 00 | Last Cycl: 0 | Cycl-TT: 14 | FL: 00100100
[EXE] Executing program ...
[cpu] PC: 0802 | A: 0A | X: 00 | Y: 00 | Last Opc: A9 | Last Cycl: 2 | Cycl-TT: 16 | FL: 00100100
[cpu] PC: 0803 | A: 0A | X: 0A | Y: 00 | Last Opc: AA | Last Cycl: 2 | Cycl-TT: 18 | FL: 00100100
[cpu] PC: 0805 | A: 28 | X: 0A | Y: 00 | Last Opc: 69 | Last Cycl: 2 | Cycl-TT: 20 | FL: 00100100
[cpu] PC: 0808 | A: 28 | X: 0A | Y: 00 | Last Opc: 9D | Last Cycl: 5 | Cycl-TT: 25 | FL: 00100100
[EXE] sid register written!
...
...
[cpu] PC: 0808 | A: CC | X: 18 | Y: 00 | Last Opc: 9D | Last Cycl: 5 | Cycl-TT: 261 | FL: 10100100
[EXE] sid register written!
[sid] registers: 00 00 00 00 00 00 00 00 00 00 28 46 64 82 A0 BE DC FA 18 36 54 72 90 AE CC 
[EXE] sid volume changed: CC
```
In the main function it checks for the change of the SID volume register:
```zig
try stdout.print("[EXE] Executing program ...\n", .{});
var sid_volume_old = c64.sid.getRegisters()[24];
while (c64.cpu.runStep() != 0) {
    c64.cpu.printStatus();
    if (c64.cpu.sidRegWritten()) {
        try stdout.print("[EXE] sid register written!\n", .{});
        c64.sid.printRegisters();

        const sid_registers = c64.sid.getRegisters();
        if (sid_volume_old != sid_registers[24]) {
            try stdout.print("[EXE] sid volume changed: {X:0>2}\n", .{
                sid_registers[24],
            });
            sid_volume_old = sid_registers[24];
        }
    }
}
```

<br>

## 🔓 License
This emulator is released under the **MIT License**, allowing free modification and distribution.

<br>

## 🌐 Related Projects  
- 🎧 **[zigreSID](https://github.com/M64GitHub/zigreSID)** – A SID sound emulation library for Zig, integrating with this emulator for `.sid` file playback.

<br>

## 🏆 Credits
Developed with ❤️ by M64  
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






