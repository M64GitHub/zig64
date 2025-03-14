const std = @import("std");
const Cpu = @import("zig64").Cpu;
const C64 = @import("zig64");

const gpa = std.heap.page_allocator;

test "ADC basic addition without carry" {
    var c64 = C64.init(gpa, C64.Vic.Model.pal, 0x0800);
    defer c64.deinit(gpa);

    c64.cpu.a = 0x10;
    c64.cpu.flags.c = 0;
    c64.cpu.flags.v = 0;
    c64.cpu.adc(0x20);

    try std.testing.expectEqual(@as(u8, 0x30), c64.cpu.a);
    try std.testing.expectEqual(@as(u1, 0), c64.cpu.flags.c); // No carry
    try std.testing.expectEqual(@as(u1, 0), c64.cpu.flags.v); // No overflow
}

test "ADC addition with carry" {
    var c64 = C64.init(gpa, C64.Vic.Model.pal, 0x0800);
    defer c64.deinit(gpa);

    c64.cpu.a = 0x10;
    c64.cpu.flags.c = 1; // Carry is set
    c64.cpu.adc(0x20);

    try std.testing.expectEqual(@as(u8, 0x31), c64.cpu.a); // One extra from carry
    try std.testing.expectEqual(@as(u1, 0), c64.cpu.flags.c); // No extra carry generated
    try std.testing.expectEqual(@as(u1, 0), c64.cpu.flags.v); // No overflow
}

test "ADC signed overflow detection" {
    var c64 = C64.init(gpa, C64.Vic.Model.pal, 0x0800);
    defer c64.deinit(gpa);

    c64.cpu.a = 0x40; // +64
    c64.cpu.flags.c = 0;
    c64.cpu.adc(0x40); // +64

    try std.testing.expectEqual(@as(u8, 0x80), c64.cpu.a); // -128 (overflow!)
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.v); // Overflow should be set!
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.n); // Result is negative
}

test "ADC carry flag set on overflow past 255" {
    var c64 = C64.init(gpa, C64.Vic.Model.pal, 0x0800);
    defer c64.deinit(gpa);

    c64.cpu.a = 0xFF;
    c64.cpu.flags.c = 0;
    c64.cpu.adc(0x01);

    try std.testing.expectEqual(@as(u8, 0x00), c64.cpu.a); // Wraps around to 0
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.c); // Carry should be set!
    try std.testing.expectEqual(@as(u1, 0), c64.cpu.flags.v); // No signed overflow
}

test "ADC negative flag set" {
    var c64 = C64.init(gpa, C64.Vic.Model.pal, 0x0800);
    defer c64.deinit(gpa);

    c64.cpu.a = 0x80; // -128
    c64.cpu.flags.c = 0;
    c64.cpu.adc(0x01);

    try std.testing.expectEqual(@as(u8, 0x81), c64.cpu.a); // -127
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.n); // Negative flag should be set!
}

test "SBC basic subtraction without borrow" {
    var c64 = C64.init(gpa, C64.Vic.Model.pal, 0x0800);
    defer c64.deinit(gpa);

    c64.cpu.a = 0x50;
    c64.cpu.flags.c = 1; // No borrow
    c64.cpu.sbc(0x20);

    try std.testing.expectEqual(@as(u8, 0x30), c64.cpu.a);
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.c); // No borrow
    try std.testing.expectEqual(@as(u1, 0), c64.cpu.flags.v); // No signed overflow
    try std.testing.expectEqual(@as(u1, 0), c64.cpu.flags.n); // Result is positive
}

test "SBC with borrow (C=0)" {
    var c64 = C64.init(gpa, C64.Vic.Model.pal, 0x0800);
    defer c64.deinit(gpa);

    c64.cpu.a = 0x50;
    c64.cpu.flags.c = 0; // Borrow!
    c64.cpu.sbc(0x20);

    try std.testing.expectEqual(@as(u8, 0x2F), c64.cpu.a); // One less because of borrow
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.c); // No borrow needed
    try std.testing.expectEqual(@as(u1, 0), c64.cpu.flags.v);
}

test "SBC signed overflow (positive result turns negative)" {
    var c64 = C64.init(gpa, C64.Vic.Model.pal, 0x0800);
    defer c64.deinit(gpa);

    c64.cpu.a = 0x40; // +64
    c64.cpu.flags.c = 1;
    c64.cpu.sbc(0xC0); // -64

    try std.testing.expectEqual(@as(u8, 0x80), c64.cpu.a); // -128
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.v); // Overflow detected!
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.n); // Result is negative
}

test "SBC signed overflow (negative result turns positive)" {
    var c64 = C64.init(gpa, C64.Vic.Model.pal, 0x0800);
    defer c64.deinit(gpa);

    c64.cpu.a = 0x80; // -128
    c64.cpu.flags.c = 1;
    c64.cpu.sbc(0x80); // -128

    try std.testing.expectEqual(@as(u8, 0x00), c64.cpu.a); // 0
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.v); // Overflow detected!
    try std.testing.expectEqual(@as(u1, 0), c64.cpu.flags.n); // Result is positive
}

test "Branching instruction tests" {
    // Test case 1: No branch when t1 != t2
    var c64 = C64.init(gpa, C64.Vic.Model.pal, 0x0800);
    defer c64.deinit(gpa);

    c64.cpu.pc = 0x1000;
    c64.mem.data[0x1000] = 0x05; // Offset +5
    c64.cpu.branch(1, 0); // Should NOT branch
    try std.testing.expectEqual(@as(u16, 0x1001), c64.cpu.pc); // PC should just move forward

    // Test case 2: Branch forward +5 when t1 == t2
    c64.cpu.pc = 0x2000;
    c64.mem.data[0x2000] = 0x05; // Offset +5
    c64.cpu.branch(1, 1); // Should branch
    try std.testing.expectEqual(@as(u16, 0x2006), c64.cpu.pc); // PC should jump to 0x2006

    // Test case 3: Branch backward -4 when t1 == t2
    c64.cpu.pc = 0x3005;
    c64.mem.data[0x3005] = 0xFC; // Offset -4 (Two’s complement: -4)
    c64.cpu.branch(1, 1); // Should branch
    try std.testing.expectEqual(@as(u16, 0x3002), c64.cpu.pc); // PC should jump back

    // Test case 4: Page boundary crossing should add extra cycle
    c64.cpu.pc = 0x20FE; // Last byte of page 0x20
    c64.mem.data[0x20FE] = 0x02; // Offset +2 (would land in 0x2102)
    const cycles_before = c64.cpu.cycles_executed;
    c64.cpu.branch(1, 1); // Should branch and add extra cycle
    try std.testing.expectEqual(@as(u16, 0x2101), c64.cpu.pc); // PC should land in next page
    try std.testing.expectEqual(cycles_before + 3, c64.cpu.cycles_executed); // Extra cycle added

    // Test case 5: Branch without page crossing (normal case)
    c64.cpu.pc = 0x2500;
    c64.mem.data[0x2500] = 0x02; // Offset +2
    const cycles_before_2 = c64.cpu.cycles_executed;
    c64.cpu.branch(1, 1);
    try std.testing.expectEqual(@as(u16, 0x2503), c64.cpu.pc); // PC should move normally
    try std.testing.expectEqual(cycles_before_2 + 2, c64.cpu.cycles_executed); // Only 1 extra cycle
}
