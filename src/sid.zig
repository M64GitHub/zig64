const std = @import("std");
const stdout = std.io.getStdOut().writer();

pub const Sid = @This();

base_address: u16,
registers: [25]u8,
dbg_enabled: bool,
reg_written: bool,
reg_written_idx: usize,
reg_written_val: u8,
reg_changed: bool,
reg_changed_idx: usize,
reg_changed_from: u8,
reg_changed_to: u8,
ext_reg_written: bool,
ext_reg_changed: bool,
last_write_cycle: usize,
last_change: ?RegisterChange = null,

pub const std_base = 0xD400;

// Enum for register meanings (indices 0-24 match SID registers)
pub const RegisterMeaning = enum(usize) {
    osc1_freq_lo = 0, // $D400
    osc1_freq_hi, // $D401
    osc1_pw_lo, // $D402
    osc1_pw_hi, // $D403
    osc1_control, // $D404 (waveform, gate, etc.)
    osc1_attack_decay, // $D405
    osc1_sustain_release, // $D406
    osc2_freq_lo, // $D407
    osc2_freq_hi, // $D408
    osc2_pw_lo, // $D409
    osc2_pw_hi, // $D40A
    osc2_control, // $D40B
    osc2_attack_decay, // $D40C
    osc2_sustain_release, // $D40D
    osc3_freq_lo, // $D40E
    osc3_freq_hi, // $D40F
    osc3_pw_lo, // $D410
    osc3_pw_hi, // $D411
    osc3_control, // $D412
    osc3_attack_decay, // $D413
    osc3_sustain_release, // $D414
    filter_freq_lo, // $D415
    filter_freq_hi, // $D416
    filter_res_control, // $D417 (resonance + routing)
    filter_mode_volume, // $D418 (filter mode + volume)

    pub fn fromIndex(reg: usize) ?RegisterMeaning {
        return if (reg <= 24) @enumFromInt(reg) else null;
    }
};

// Bitfield structs for registers with complex values
pub const WaveformControl = packed struct(u8) {
    gate: bool = false, // Bit 0: Gate (1 = on)
    sync: bool = false, // Bit 1: Sync with next oscillator
    ring_mod: bool = false, // Bit 2: Ring modulation with next oscillator
    test_bit: bool = false, // Bit 3: Test bit (1 = reset/noise)
    triangle: bool = false, // Bit 4: Triangle waveform
    sawtooth: bool = false, // Bit 5: Sawtooth waveform
    pulse: bool = false, // Bit 6: Pulse waveform
    noise: bool = false, // Bit 7: Noise waveform

    pub fn fromValue(val: u8) WaveformControl {
        return @bitCast(val);
    }
};

pub const AttackDecay = packed struct(u8) {
    decay: u4 = 0, // Bits 0-3: Decay time (0-15)
    attack: u4 = 0, // Bits 4-7: Attack time (0-15)

    pub fn fromValue(val: u8) AttackDecay {
        return @bitCast(val);
    }
};

pub const SustainRelease = packed struct(u8) {
    release: u4 = 0, // Bits 0-3: Release time (0-15)
    sustain: u4 = 0, // Bits 4-7: Sustain level (0-15)

    pub fn fromValue(val: u8) SustainRelease {
        return @bitCast(val);
    }
};

pub const FilterResControl = packed struct(u8) {
    osc1: bool = false, // Bit 0: Route Osc 1 to filter
    osc2: bool = false, // Bit 1: Route Osc 2 to filter
    osc3: bool = false, // Bit 2: Route Osc 3 to filter
    ext: bool = false, // Bit 3: Route external input to filter
    resonance: u4 = 0, // Bits 4-7: Resonance level (0-15)

    pub fn fromValue(val: u8) FilterResControl {
        return @bitCast(val);
    }
};

pub const FilterModeVolume = packed struct(u8) {
    volume: u4 = 0, // Bits 0-3: Master volume (0-15)
    low_pass: bool = false, // Bit 4: Low-pass filter on
    band_pass: bool = false, // Bit 5: Band-pass filter on
    high_pass: bool = false, // Bit 6: High-pass filter on
    osc3_off: bool = false, // Bit 7: Mute Osc 3 output

    pub fn fromValue(val: u8) FilterModeVolume {
        return @bitCast(val);
    }
};
pub const RegisterChange = struct {
    meaning: RegisterMeaning,
    old_value: u8,
    new_value: u8,
    details: union(enum) {
        waveform: WaveformControl,
        filter_res: FilterResControl,
        filter_mode: FilterModeVolume,
        attack_decay: AttackDecay,
        sustain_release: SustainRelease,
        raw: u8,
    },
    cycle: usize,
};

pub fn init(base_address: u16) Sid {
    return Sid{
        .base_address = base_address,
        .registers = [_]u8{0} ** 25,
        .dbg_enabled = false,
        .reg_written = false,
        .reg_written_val = 0x00,
        .reg_written_idx = 0,
        .reg_changed = false,
        .reg_changed_from = 0x00,
        .reg_changed_to = 0x00,
        .reg_changed_idx = 0,
        .ext_reg_changed = false,
        .ext_reg_written = false,
        .last_write_cycle = 0,
    };
}

pub fn getRegisters(sid: *Sid) [25]u8 {
    return sid.registers;
}

pub fn writeRegister(sid: *Sid, reg: usize, val: u8) void {
    if (reg > 24) return;

    sid.reg_written_idx = reg;
    sid.reg_written_val = val;

    if (sid.registers[reg] != val) {
        sid.reg_changed = true;
        sid.ext_reg_changed = true;
        if (sid.dbg_enabled) {
            std.debug.print(
                "[sid] reg changed: {X:04} : {X:02} => {X:02}\n",
                .{ sid.base_address + reg, sid.registers[reg], val },
            );
        }
        sid.reg_changed_idx = reg;
        sid.reg_changed_from = sid.registers[reg];
        sid.reg_changed_to = val;

        // map register to meaning and decode value
        if (RegisterMeaning.fromIndex(reg)) |meaning| {
            sid.last_change = RegisterChange{
                .meaning = meaning,
                .old_value = sid.registers[reg],
                .new_value = val,
                .details = switch (meaning) {
                    .osc1_control, .osc2_control, .osc3_control => .{
                        .waveform = WaveformControl.fromValue(val),
                    },
                    .filter_res_control => .{
                        .filter_res = FilterResControl.fromValue(val),
                    },
                    .filter_mode_volume => .{ .filter_mode = FilterModeVolume.fromValue(val) },
                    .osc1_attack_decay, .osc2_attack_decay, .osc3_attack_decay => .{
                        .attack_decay = AttackDecay.fromValue(val),
                    },
                    .osc1_sustain_release, .osc2_sustain_release, .osc3_sustain_release => .{
                        .sustain_release = SustainRelease.fromValue(val),
                    },
                    else => .{ .raw = val },
                },
                .cycle = 0,
            };

            if (sid.dbg_enabled) {
                sid.printChange(meaning, val);
            }
        }
    } else {
        if (sid.dbg_enabled) {
            std.debug.print(
                "[sid] reg write  : {X:04} : {X:02} => {X:02}\n",
                .{ sid.base_address + reg, sid.registers[reg], val },
            );
        }
    }

    sid.registers[reg] = val;
    sid.reg_written = true;
    sid.ext_reg_written = true;
}

pub fn writeRegisterCycle(sid: *Sid, reg: usize, val: u8, cycle: usize) void {
    if (reg > 24) return;
    sid.last_write_cycle = cycle;
    // -- sid.writeRegister(reg, val);

    sid.reg_written_idx = reg;
    sid.reg_written_val = val;

    if (sid.registers[reg] != val) {
        sid.reg_changed = true;
        sid.ext_reg_changed = true;
        if (sid.dbg_enabled) {
            std.debug.print(
                "[sid] reg changed: {X:04} : {X:02} => {X:02}\n",
                .{ sid.base_address + reg, sid.registers[reg], val },
            );
        }
        sid.reg_changed_idx = reg;
        sid.reg_changed_from = sid.registers[reg];
        sid.reg_changed_to = val;

        // map register to meaning and decode value
        if (RegisterMeaning.fromIndex(reg)) |meaning| {
            sid.last_change = RegisterChange{
                .meaning = meaning,
                .old_value = sid.registers[reg],
                .new_value = val,
                .details = switch (meaning) {
                    .osc1_control, .osc2_control, .osc3_control => .{
                        .waveform = WaveformControl.fromValue(val),
                    },
                    .filter_res_control => .{
                        .filter_res = FilterResControl.fromValue(val),
                    },
                    .filter_mode_volume => .{ .filter_mode = FilterModeVolume.fromValue(val) },
                    .osc1_attack_decay, .osc2_attack_decay, .osc3_attack_decay => .{
                        .attack_decay = AttackDecay.fromValue(val),
                    },
                    .osc1_sustain_release, .osc2_sustain_release, .osc3_sustain_release => .{
                        .sustain_release = SustainRelease.fromValue(val),
                    },
                    else => .{ .raw = val },
                },
                .cycle = cycle,
            };

            if (sid.dbg_enabled) {
                sid.printChange(meaning, val);
            }
        }
    } else {
        if (sid.dbg_enabled) {
            std.debug.print(
                "[sid] reg write  : {X:04} : {X:02} => {X:02}\n",
                .{ sid.base_address + reg, sid.registers[reg], val },
            );
        }
    }

    sid.registers[reg] = val;
    sid.reg_written = true;
    sid.ext_reg_written = true;
}

pub fn printRegisters(sid: *Sid) void {
    stdout.print("[sid] registers: ", .{}) catch {};
    for (sid.registers) |v| {
        stdout.print("{X:0>2} ", .{v}) catch {};
    }
    stdout.print("\n", .{}) catch {};
}

fn printChange(sid: *Sid, meaning: RegisterMeaning, val: u8) void {
    const addr = sid.base_address + @intFromEnum(meaning);
    const old_val = sid.registers[@intFromEnum(meaning)];
    switch (meaning) {
        .osc1_control, .osc2_control, .osc3_control => {
            const wf = WaveformControl.fromValue(val);
            std.debug.print(
                "[sid] {s} changed: {X:04} : {X:02} => {X:02} (Gate: {}, Sync: {}, Ring: {}, Test: {}, Tri: {}, Saw: {}, Pulse: {}, Noise: {})\n",
                .{
                    @tagName(meaning),
                    addr,
                    old_val,
                    val,
                    wf.gate,
                    wf.sync,
                    wf.ring_mod,
                    wf.test_bit,
                    wf.triangle,
                    wf.sawtooth,
                    wf.pulse,
                    wf.noise,
                },
            );
        },
        .osc1_attack_decay, .osc2_attack_decay, .osc3_attack_decay => {
            const ad = AttackDecay.fromValue(val);
            std.debug.print(
                "[sid] {s} changed: {X:04} : {X:02} => {X:02} (Attack: {d}, Decay: {d})\n",
                .{
                    @tagName(meaning),
                    addr,
                    old_val,
                    val,
                    ad.attack,
                    ad.decay,
                },
            );
        },
        .osc1_sustain_release, .osc2_sustain_release, .osc3_sustain_release => {
            const sr = SustainRelease.fromValue(val);
            std.debug.print(
                "[sid] {s} changed: {X:04} : {X:02} => {X:02} (Sustain: {d}, Release: {d})\n",
                .{
                    @tagName(meaning),
                    addr,
                    old_val,
                    val,
                    sr.sustain,
                    sr.release,
                },
            );
        },
        .filter_res_control => {
            const fr = FilterResControl.fromValue(val);
            std.debug.print(
                "[sid] filter_res_control changed: {X:04} : {X:02} => {X:02} (Osc1: {}, Osc2: {}, Osc3: {}, Ext: {}, Res: {d})\n",
                .{
                    addr,
                    old_val,
                    val,
                    fr.osc1,
                    fr.osc2,
                    fr.osc3,
                    fr.ext,
                    fr.resonance,
                },
            );
        },
        .filter_mode_volume => {
            const fm = FilterModeVolume.fromValue(val);
            std.debug.print(
                "[sid] filter_mode_volume changed: {X:04} : {X:02} => {X:02} (Vol: {d}, LP: {}, BP: {}, HP: {}, Osc3 Off: {})\n",
                .{
                    addr,
                    old_val,
                    val,
                    fm.volume,
                    fm.low_pass,
                    fm.band_pass,
                    fm.high_pass,
                    fm.osc3_off,
                },
            );
        },
        else => {
            std.debug.print(
                "[sid] {s} changed: {X:04} : {X:02} => {X:02}\n",
                .{ @tagName(meaning), addr, old_val, val },
            );
        },
    }
}

// Volume change ($D418)
pub fn volumeChanged(change: RegisterChange) bool {
    return change.meaning == .filter_mode_volume;
}

// Filter mode change ($D418 - low-pass, band-pass, high-pass, osc3_off)
pub fn filterModeChanged(change: RegisterChange) bool {
    return change.meaning == .filter_mode_volume;
}

// Filter frequency change ($D415-$D416)
pub fn filterFreqChanged(change: RegisterChange) bool {
    return change.meaning == .filter_freq_lo or
        change.meaning == .filter_freq_hi;
}

// Filter resonance/routing change ($D417)
pub fn filterResChanged(change: RegisterChange) bool {
    return change.meaning == .filter_res_control;
}

// Oscillator frequency change (osc = 1, 2, or 3)
pub fn oscFreqChanged(change: RegisterChange, osc: u2) bool {
    return switch (osc) {
        1 => change.meaning == .osc1_freq_lo or change.meaning == .osc1_freq_hi,
        2 => change.meaning == .osc2_freq_lo or change.meaning == .osc2_freq_hi,
        3 => change.meaning == .osc3_freq_lo or change.meaning == .osc3_freq_hi,
        else => false, // Invalid oscillator number
    };
}

// Oscillator pulse width change (osc = 1, 2, or 3)
pub fn oscPulseWidthChanged(change: RegisterChange, osc: u2) bool {
    return switch (osc) {
        1 => change.meaning == .osc1_pw_lo or change.meaning == .osc1_pw_hi,
        2 => change.meaning == .osc2_pw_lo or change.meaning == .osc2_pw_hi,
        3 => change.meaning == .osc3_pw_lo or change.meaning == .osc3_pw_hi,
        else => false,
    };
}

// Oscillator waveform/control change (osc = 1, 2, or 3)
pub fn oscWaveformChanged(change: RegisterChange, osc: u2) bool {
    return switch (osc) {
        1 => change.meaning == .osc1_control,
        2 => change.meaning == .osc2_control,
        3 => change.meaning == .osc3_control,
        else => false,
    };
}

// Oscillator attack/decay change (osc = 1, 2, or 3)
pub fn oscAttackDecayChanged(change: RegisterChange, osc: u2) bool {
    return switch (osc) {
        1 => change.meaning == .osc1_attack_decay,
        2 => change.meaning == .osc2_attack_decay,
        3 => change.meaning == .osc3_attack_decay,
        else => false,
    };
}

// Oscillator sustain/release change (osc = 1, 2, or 3)
pub fn oscSustainReleaseChanged(change: RegisterChange, osc: u2) bool {
    return switch (osc) {
        1 => change.meaning == .osc1_sustain_release,
        2 => change.meaning == .osc2_sustain_release,
        3 => change.meaning == .osc3_sustain_release,
        else => false,
    };
}
