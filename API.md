
# API Reference

## C64
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
        // Expected output (example from $0800 routine):
        // "Cycle 9: osc1_freq_lo changed 00 => 10"
        // "Cycle 15: osc1_freq_hi changed 00 => 11"
        // "Cycle 21: osc1_control changed 00 => 41"
        // "Cycle 27: osc1_attack_decay changed 00 => 53"
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

## Cpu
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

## Ram64k
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

## Sid
Emulates the SID chip’s register state, providing advanced tracking, decoding, and analysis of register writes.

- **Fields**:
  ```zig
  base_address: u16,       // Base memory address for SID registers (typically 0xD400)
  registers: [25]u8,       // Array of 25 SID registers
  dbg_enabled: bool,       // Enables debug logging for SID operations
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
  RegisterChange = struct {
      cycle: usize,          // CPU cycle of the change
      meaning: RegisterMeaning, // Semantic meaning (e.g., osc1_freq_lo)
      old_value: u8,         // Previous register value
      new_value: u8,         // New register value
      details: union {       // Decoded details of the change
          none: void,
          waveform: WaveformControl,
          filter_res: FilterResControl,
          filter_mode: FilterModeVolume,
          attack_decay: AttackDecay,
          sustain_release: SustainRelease,
      },

      // Volume change ($D418)
      pub fn volumeChanged(self: RegisterChange) bool 
          
      // Filter mode change ($D418 - low-pass, band-pass, high-pass, osc3_off)
      pub fn filterModeChanged(self: RegisterChange) bool 

      // Filter frequency change ($D415-$D416)
      pub fn filterFreqChanged(self: RegisterChange) bool 

      // Filter resonance/routing change ($D417)
      pub fn filterResChanged(self: RegisterChange) bool 

      // Oscillator frequency change (osc = 1, 2, or 3)
      pub fn oscFreqChanged(self: RegisterChange, osc: u2) bool 

      // Oscillator pulse width change (osc = 1, 2, or 3)
      pub fn oscPulseWidthChanged(self: RegisterChange, osc: u2) bool 

      // Oscillator waveform/control change (osc = 1, 2, or 3)
      pub fn oscWaveformChanged(self: RegisterChange, osc: u2) bool 

      // Oscillator attack/decay change (osc = 1, 2, or 3)
      pub fn oscAttackDecayChanged(self: RegisterChange, osc: u2) bool 

      // Oscillator sustain/release change (osc = 1, 2, or 3)
      pub fn oscSustainReleaseChanged(self: RegisterChange, osc: u2) bool
  }
  ```
  Captures details of a SID register change with methods to analyze specific updates and a union for decoded register specifics.


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
  Writes a value to a specific SID register, updating tracking flags and state (`reg_written`, `reg_written_idx`, `reg_written_val`, `ext_reg_written`, `reg_changed`, `reg_changed_idx`, `reg_changed_from`, `reg_changed_to`, `ext_reg_changed`, and `last_change` if applicable).
  - **Example**:
    ```zig
    sid.writeRegister(0, 0x42); // Set osc1_freq_lo to 0x42
    if (sid.reg_changed) {
        std.debug.print("Osc1 freq lo changed from {X:02} to {X:02}\n",
            .{ sid.reg_changed_from, sid.reg_changed_to });
    }
    ```
    Writes to oscillator 1’s frequency low register and checks for a change.
  - **Example**:
    ```zig
    sid.dbg_enabled = true;
    sid.writeRegister(0, 0x42); // Set osc1_freq_lo to 0x42
    if (sid.last_change) |change| {
        std.debug.print("{s} updated to {X:02} (was {X:02})\n",
            .{ @tagName(change.meaning), change.new_value, change.old_value });
        // Expected output: "osc1_freq_lo updated to 42 (was 00)"
    }
    ```
    Writes to oscillator 1’s frequency low register and logs the change details, using `last_change: RegisterChange`.

  ```zig
  pub fn writeRegisterCycle(
      sid: *Sid,
      reg: usize,
      val: u8,
      cycle: usize
  ) void
  ```
  Writes a value to the specified SID register, records the CPU cycle in `last_write_cycle`, updating tracking flags and state (`reg_written`, `reg_written_idx`, `reg_written_val`, `ext_reg_written`, `reg_changed`, `reg_changed_idx`, `reg_changed_from`, `reg_changed_to`, `ext_reg_changed`, and `last_change` if applicable).
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
        if (change.oscFreqChanged(1)) {
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
        if (change.oscAttackDecayChanged(1)) {
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

## Vic
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
  cycles_since_vsync: u16,  // Cycles since last vertical sync
  cycles_since_hsync: u8,   // Cycles since last horizontal sync
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
  ) u8
  ```
  Advances the raster line, updates VIC registers (`0xD011`, `0xD012`), and handles bad line timing.  
  Returns number of cycles to add to cpu execution cycles. Helper for `emulate()`.

  ```zig
  pub fn emulate(vic: *Vic, cycles_last_step: u8) u8
  ```
  Updates cycles, and calls `emulateD012()`. Returns result of `emulateD012()`.
  Called by the cpu in `runStep()`.

  ```zig
  pub fn printStatus(
      vic: *Vic
  ) void
  ```
  Prints the current VIC status, including raster line, sync flags, and frame count.

## Asm
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
  pub fn disassembleInstruction(
      buffer: []u8,
      pc: u16,
      insn: Instruction
  ) ![]const u8
  ```
  Converts an instruction into a human-readable string (e.g., `"LDA #$10"`).
  - **Example**:
    ```zig
    var buffer: [32]u8 = undefined;
    const insn = Asm.decodeInstruction(&[_]u8{ 0xA9, 0x10 }); // LDA #$10
    const disasm = try Asm.disassembleInstruction(&buffer, 0x0800, insn);
    std.debug.print("{s}\n", .{disasm}); // Prints: "LDA #$10"
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
