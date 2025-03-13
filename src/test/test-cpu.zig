const std = @import("std");
const Cpu = @import("mos6510").Cpu;
const Emulator = @import("mos6510").Emulator;

test "ADC basic addition without carry" {
    var cpu = Cpu.init(0x0000);

    cpu.a = 0x10;
    cpu.flags.c = 0;
    cpu.flags.v = 0;
    cpu.adc(0x20);

    try std.testing.expectEqual(@as(u8, 0x30), cpu.a);
    try std.testing.expectEqual(@as(u1, 0), cpu.flags.c); // No carry
    try std.testing.expectEqual(@as(u1, 0), cpu.flags.v); // No overflow
}

test "ADC addition with carry" {
    var cpu = Cpu.init(0x0000);

    cpu.a = 0x10;
    cpu.flags.c = 1; // Carry is set
    cpu.adc(0x20);

    try std.testing.expectEqual(@as(u8, 0x31), cpu.a); // One extra from carry
    try std.testing.expectEqual(@as(u1, 0), cpu.flags.c); // No extra carry generated
    try std.testing.expectEqual(@as(u1, 0), cpu.flags.v); // No overflow
}

test "ADC signed overflow detection" {
    var cpu = Cpu.init(0x0000);

    cpu.a = 0x40; // +64
    cpu.flags.c = 0;
    cpu.adc(0x40); // +64

    try std.testing.expectEqual(@as(u8, 0x80), cpu.a); // -128 (overflow!)
    try std.testing.expectEqual(@as(u1, 1), cpu.flags.v); // Overflow should be set!
    try std.testing.expectEqual(@as(u1, 1), cpu.flags.n); // Result is negative
}

test "ADC carry flag set on overflow past 255" {
    var cpu = Cpu.init(0x0000);

    cpu.a = 0xFF;
    cpu.flags.c = 0;
    cpu.adc(0x01);

    try std.testing.expectEqual(@as(u8, 0x00), cpu.a); // Wraps around to 0
    try std.testing.expectEqual(@as(u1, 1), cpu.flags.c); // Carry should be set!
    try std.testing.expectEqual(@as(u1, 0), cpu.flags.v); // No signed overflow
}

test "ADC negative flag set" {
    var cpu = Cpu.init(0x0000);

    cpu.a = 0x80; // -128
    cpu.flags.c = 0;
    cpu.adc(0x01);

    try std.testing.expectEqual(@as(u8, 0x81), cpu.a); // -127
    try std.testing.expectEqual(@as(u1, 1), cpu.flags.n); // Negative flag should be set!
}

test "SBC basic subtraction without borrow" {
    var cpu = Cpu.init(0x0000);

    cpu.a = 0x50;
    cpu.flags.c = 1; // No borrow
    cpu.sbc(0x20);

    try std.testing.expectEqual(@as(u8, 0x30), cpu.a);
    try std.testing.expectEqual(@as(u1, 1), cpu.flags.c); // No borrow
    try std.testing.expectEqual(@as(u1, 0), cpu.flags.v); // No signed overflow
    try std.testing.expectEqual(@as(u1, 0), cpu.flags.n); // Result is positive
}

test "SBC with borrow (C=0)" {
    var cpu = Cpu.init(0x0000);

    cpu.a = 0x50;
    cpu.flags.c = 0; // Borrow!
    cpu.sbc(0x20);

    try std.testing.expectEqual(@as(u8, 0x2F), cpu.a); // One less because of borrow
    try std.testing.expectEqual(@as(u1, 1), cpu.flags.c); // No borrow needed
    try std.testing.expectEqual(@as(u1, 0), cpu.flags.v);
}

test "SBC signed overflow (positive result turns negative)" {
    var cpu = Cpu.init(0x0000);

    cpu.a = 0x40; // +64
    cpu.flags.c = 1;
    cpu.sbc(0xC0); // -64

    try std.testing.expectEqual(@as(u8, 0x80), cpu.a); // -128
    try std.testing.expectEqual(@as(u1, 1), cpu.flags.v); // Overflow detected!
    try std.testing.expectEqual(@as(u1, 1), cpu.flags.n); // Result is negative
}

test "SBC signed overflow (negative result turns positive)" {
    var cpu = Cpu.init(0x0000);

    cpu.a = 0x80; // -128
    cpu.flags.c = 1;
    cpu.sbc(0x80); // -128

    try std.testing.expectEqual(@as(u8, 0x00), cpu.a); // 0
    try std.testing.expectEqual(@as(u1, 1), cpu.flags.v); // Overflow detected!
    try std.testing.expectEqual(@as(u1, 0), cpu.flags.n); // Result is positive
}

test "Branching instruction tests" {
    const gpa = std.heap.page_allocator;
    var emu = Emulator.init(gpa, Emulator.VicType.pal, 0x0800);

    // Test case 1: No branch when t1 != t2
    emu.cpu.pc = 0x1000;
    emu.mem.data[0x1000] = 0x05; // Offset +5
    emu.cpu.branch(1, 0); // Should NOT branch
    try std.testing.expectEqual(@as(u16, 0x1001), emu.cpu.pc); // PC should just move forward

    // Test case 2: Branch forward +5 when t1 == t2
    emu.cpu.pc = 0x2000;
    emu.mem.data[0x2000] = 0x05; // Offset +5
    emu.cpu.branch(1, 1); // Should branch
    try std.testing.expectEqual(@as(u16, 0x2006), emu.cpu.pc); // PC should jump to 0x2006

    // Test case 3: Branch backward -4 when t1 == t2
    emu.cpu.pc = 0x3005;
    emu.mem.data[0x3005] = 0xFC; // Offset -4 (Two’s complement: -4)
    emu.cpu.branch(1, 1); // Should branch
    try std.testing.expectEqual(@as(u16, 0x3002), emu.cpu.pc); // PC should jump back

    // Test case 4: Page boundary crossing should add extra cycle
    emu.cpu.pc = 0x20FE; // Last byte of page 0x20
    emu.mem.data[0x20FE] = 0x02; // Offset +2 (would land in 0x2102)
    const cycles_before = emu.cpu.cycles_executed;
    emu.cpu.branch(1, 1); // Should branch and add extra cycle
    try std.testing.expectEqual(@as(u16, 0x2101), emu.cpu.pc); // PC should land in next page
    try std.testing.expectEqual(cycles_before + 3, emu.cpu.cycles_executed); // Extra cycle added

    // Test case 5: Branch without page crossing (normal case)
    emu.cpu.pc = 0x2500;
    emu.mem.data[0x2500] = 0x02; // Offset +2
    const cycles_before_2 = emu.cpu.cycles_executed;
    emu.cpu.branch(1, 1);
    try std.testing.expectEqual(@as(u16, 0x2503), emu.cpu.pc); // PC should move normally
    try std.testing.expectEqual(cycles_before_2 + 2, emu.cpu.cycles_executed); // Only 1 extra cycle
}
