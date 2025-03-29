# C64 Emulator Core in Zig  
![Tests](https://github.com/M64GitHub/flagZ/actions/workflows/test.yml/badge.svg)
![License](https://img.shields.io/badge/license-MIT-brightgreen?style=flat)
![Version](https://img.shields.io/badge/version-0.2.0-8a2be2?style=flat)
![Zig](https://img.shields.io/badge/Zig-0.14.0-orange?style=flat)

A **Commodore 64 MOS6510 emulator core** written in **Zig**, designed for accuracy, efficiency, and seamless integration into C64-based projects.  
This emulator delivers cycle-accurate execution, precise rasterbeam emulation for PAL and NTSC video synchronization, and SID register tracking. Designed for C64 software analysis and program execution, it ensures faithful reproduction of C64 behavior with high precision.

It serves as the **computational core of a C64 system**, making it suitable for a range of applications, from testing and debugging C64 software to powering SID music playback engines like 🎧 [zigreSID](https://github.com/M64GitHub/zigreSID).  

<br>

## 🚀 Features  
- 🎮 **Fully Functional 6510 CPU Emulator** – Implements all legal `MOS 6502/6510` instructions and addressing modes with pinpoint accuracy.  
- 🎞 **Video Synchronization** – Executes CPU cycles in perfect harmony with PAL or NTSC, featuring full `rasterbeam` emulation and precise `bad line` handling.  
- 🎵 **SID Register Modification Detection** – Tracks every write to SID registers, ideal for debugging and analyzing SID interactions.  
- 💾 **Program Loading Support** – Seamlessly loads `.prg` files to run C64 programs like a real machine.  
- 🛠 **CPU Debugging** – Robust tools to inspect CPU registers, flags, memory, VIC state, and SID registers in real-time.  
- 🔍 **Disassembler / Instruction Metadata Decoder** – Decodes 6502/6510 opcodes into human-readable mnemonics, enriched with metadata like size, instruction group, addressing mode, operand, operand-type, operand-size, access type (read/write), and more for seamless code tracing.

<br>


## 🔓 License
This emulator is released under the **MIT License**, allowing free modification and distribution.

<br>

## 🌐 Related Projects  
- 🎧 **[zigreSID](https://github.com/M64GitHub/zigreSID)** – A SID sound emulation library for Zig, integrating with this emulator for `.sid` file playback.

<br>


Developed with ❤️ by M64  

<br>

## 🚀 Get Started Now!
Clone the repository and start experimenting:
```sh
git clone https://github.com/M64GitHub/zig64.git
cd zig64
zig build
```
Enjoy bringing the **C64 CPU to life in Zig!** 🕹🔥






