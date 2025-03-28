const std = @import("std");
const stdout = std.io.getStdOut().writer();

pub const Sid = struct {
    base_address: u16,
    registers: [25]u8,
    dbg_enabled: bool,

    pub const std_base = 0xD400;

    pub fn init(base_address: u16) Sid {
        return Sid{
            .base_address = base_address,
            .registers = [_]u8{0} ** 25,
            .dbg_enabled = false,
        };
    }

    pub fn getRegisters(sid: *Sid) [25]u8 {
        return sid.registers;
    }

    pub fn printRegisters(sid: *Sid) void {
        stdout.print("[sid] registers: ", .{}) catch {};
        for (sid.registers) |v| {
            stdout.print("{X:0>2} ", .{v}) catch {};
        }
        stdout.print("\n", .{}) catch {};
    }
};
