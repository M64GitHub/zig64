const std = @import("std");
const stdout = std.io.getStdOut().writer();

pub const Ram64k = @This();

data: [0x10000]u8,

pub fn init() Ram64k {
    return Ram64k{
        .data = [_]u8{0} ** 65536,
    };
}

pub fn clear(self: *Ram64k) void {
    @memset(&self.data, 0);
}
