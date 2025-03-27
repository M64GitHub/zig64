const std = @import("std");
const testing = std.testing;
const Cpu = @import("zig64").Cpu;
const C64 = @import("zig64");

const gpa = std.heap.page_allocator;

// Helper to reset CPU state
const resetCpu = struct {
    fn reset(cpu: *Cpu) void {
        cpu.a = 0;
        cpu.x = 0;
        cpu.y = 0;
        cpu.flags = Cpu.CpuFlags{
            .c = 0,
            .z = 0,
            .i = 1,
            .d = 0,
            .b = 0,
            .unused = 1,
            .v = 0,
            .n = 0,
        };
        cpu.cycles_executed = 0;
        cpu.c64.mem.clear(); // Clear RAM
    }
}.reset;

test "ADC basic addition without carry" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x0000);
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
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x0000);
    defer c64.deinit(gpa);

    c64.cpu.a = 0x10;
    c64.cpu.flags.c = 1; // Carry is set
    c64.cpu.adc(0x20);

    try std.testing.expectEqual(@as(u8, 0x31), c64.cpu.a); // One extra from carry
    try std.testing.expectEqual(@as(u1, 0), c64.cpu.flags.c); // No extra carry generated
    try std.testing.expectEqual(@as(u1, 0), c64.cpu.flags.v); // No overflow
}

test "ADC signed overflow detection" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x0000);
    defer c64.deinit(gpa);

    c64.cpu.a = 0x40; // +64
    c64.cpu.flags.c = 0;
    c64.cpu.adc(0x40); // +64

    try std.testing.expectEqual(@as(u8, 0x80), c64.cpu.a); // -128 (overflow!)
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.v); // Overflow should be set!
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.n); // Result is negative
}

test "ADC carry flag set on overflow past 255" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x0000);
    defer c64.deinit(gpa);

    c64.cpu.a = 0xFF;
    c64.cpu.flags.c = 0;
    c64.cpu.adc(0x01);

    try std.testing.expectEqual(@as(u8, 0x00), c64.cpu.a); // Wraps around to 0
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.c); // Carry should be set!
    try std.testing.expectEqual(@as(u1, 0), c64.cpu.flags.v); // No signed overflow
}

test "ADC negative flag set" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x0000);
    defer c64.deinit(gpa);

    c64.cpu.a = 0x80; // -128
    c64.cpu.flags.c = 0;
    c64.cpu.adc(0x01);

    try std.testing.expectEqual(@as(u8, 0x81), c64.cpu.a); // -127
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.n); // Negative flag should be set!
}

test "SBC basic subtraction without borrow" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x0000);
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
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x0000);
    defer c64.deinit(gpa);

    c64.cpu.a = 0x50;
    c64.cpu.flags.c = 0; // Borrow!
    c64.cpu.sbc(0x20);

    try std.testing.expectEqual(@as(u8, 0x2F), c64.cpu.a); // One less because of borrow
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.c); // No borrow needed
    try std.testing.expectEqual(@as(u1, 0), c64.cpu.flags.v);
}

test "SBC signed overflow (positive result turns negative)" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x0000);
    defer c64.deinit(gpa);

    c64.cpu.a = 0x40; // +64
    c64.cpu.flags.c = 1;
    c64.cpu.sbc(0xC0); // -64

    try std.testing.expectEqual(@as(u8, 0x80), c64.cpu.a); // -128
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.v); // Overflow detected!
    try std.testing.expectEqual(@as(u1, 1), c64.cpu.flags.n); // Result is negative
}

test "SBC signed overflow (negative result turns positive)" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x0000);
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
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x0000);
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

// Test ASL via runStep
test "ASL accumulator via runStep" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0b01000000;
    c64.mem.data[0x1000] = 0x0A; // ASL A
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0b10000000, c64.cpu.a);
    try std.testing.expectEqual(0, c64.cpu.flags.c);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(1, c64.cpu.flags.n);
}

test "ASL accumulator with carry via runStep" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0b10000000;
    c64.mem.data[0x1000] = 0x0A; // ASL A
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0b00000000, c64.cpu.a);
    try std.testing.expectEqual(1, c64.cpu.flags.c);
    try std.testing.expectEqual(1, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

// Test LSR via runStep
test "LSR accumulator via runStep" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0b00000010;
    c64.mem.data[0x1000] = 0x4A; // LSR A
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0b00000001, c64.cpu.a);
    try std.testing.expectEqual(0, c64.cpu.flags.c);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "LSR accumulator with carry via runStep" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0b00000001;
    c64.mem.data[0x1000] = 0x4A; // LSR A
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0b00000000, c64.cpu.a);
    try std.testing.expectEqual(1, c64.cpu.flags.c);
    try std.testing.expectEqual(1, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

// Test ROL via runStep
test "ROL accumulator via runStep" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0b01000000;
    c64.cpu.flags.c = 0;
    c64.mem.data[0x1000] = 0x2A; // ROL A
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0b10000000, c64.cpu.a);
    try std.testing.expectEqual(0, c64.cpu.flags.c);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(1, c64.cpu.flags.n);
}

test "ROL accumulator with carry via runStep" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0b10000000;
    c64.cpu.flags.c = 1;
    c64.mem.data[0x1000] = 0x2A; // ROL A
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0b00000001, c64.cpu.a);
    try std.testing.expectEqual(1, c64.cpu.flags.c);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

// Test ROR via runStep
test "ROR accumulator via runStep" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0b00000010;
    c64.cpu.flags.c = 0;
    c64.mem.data[0x1000] = 0x6A; // ROR A
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0b00000001, c64.cpu.a);
    try std.testing.expectEqual(0, c64.cpu.flags.c);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "ROR accumulator with carry via runStep" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0b00000001;
    c64.cpu.flags.c = 1;
    c64.mem.data[0x1000] = 0x6A; // ROR A
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0b10000000, c64.cpu.a);
    try std.testing.expectEqual(1, c64.cpu.flags.c);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(1, c64.cpu.flags.n);
}

// Test INC via runStep
test "INC memory via runStep" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.writeByte(0x41, 0x0200);
    c64.cpu.pc = 0x1000;
    c64.mem.data[0x1000] = 0xEE; // INC $0200 (absolute)
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0x02;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x42, c64.cpu.readByte(0x0200));
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "INC memory overflow via runStep" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.writeByte(0xFF, 0x0200);
    c64.cpu.pc = 0x1000;
    c64.mem.data[0x1000] = 0xEE; // INC $0200 (absolute)
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0x02;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x00, c64.cpu.readByte(0x0200));
    try std.testing.expectEqual(1, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

// Test DEC via runStep
test "DEC memory via runStep" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.writeByte(0x41, 0x0200);
    c64.cpu.pc = 0x1000;
    c64.mem.data[0x1000] = 0xCE; // DEC $0200 (absolute)
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0x02;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x40, c64.cpu.readByte(0x0200));
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "DEC memory underflow via runStep" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.writeByte(0x00, 0x0200);
    c64.cpu.pc = 0x1000;
    c64.mem.data[0x1000] = 0xCE; // DEC $0200 (absolute)
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0x02;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0xFF, c64.cpu.readByte(0x0200));
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(1, c64.cpu.flags.n);
}

test "Zero Page X Addressing" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.x = 0x05;
    c64.cpu.writeByte(0x42, 0x0035); // Store 0x42 at $0035
    c64.mem.data[0x1000] = 0xB5; // LDA $30,X
    c64.mem.data[0x1001] = 0x30;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x42, c64.cpu.a);
}

test "Indirect Indexed Y Addressing" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x02;
    c64.cpu.writeByte(0x40, 0x0030); // Pointer low
    c64.cpu.writeByte(0x02, 0x0031); // Pointer high ($0240)
    c64.cpu.writeByte(0x77, 0x0242); // Data at $0240 + Y
    c64.mem.data[0x1000] = 0xB1; // LDA ($30),Y
    c64.mem.data[0x1001] = 0x30;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x77, c64.cpu.a);
}

test "Absolute X Addressing" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.x = 0x03;
    c64.cpu.writeByte(0x99, 0x2043); // Data at $2040 + X
    c64.mem.data[0x1000] = 0xBD; // LDA $2040,X
    c64.mem.data[0x1001] = 0x40;
    c64.mem.data[0x1002] = 0x20;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x99, c64.cpu.a);
}

test "PHA and PLA" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x42;
    c64.mem.data[0x1000] = 0x48; // PHA
    _ = c64.cpu.runStep();
    c64.cpu.a = 0x00; // Clear A
    c64.cpu.pc = 0x1000;
    c64.mem.data[0x1000] = 0x68; // PLA
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x42, c64.cpu.a);
    try std.testing.expectEqual(0xFD, c64.cpu.sp); // Should be back to initial value
}

test "PHP and PLP" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.flags.c = 1;
    c64.cpu.flags.z = 0;
    c64.cpu.flags.n = 1;
    c64.mem.data[0x1000] = 0x08; // PHP
    _ = c64.cpu.runStep();
    c64.cpu.flags.c = 0;
    c64.cpu.flags.z = 1;
    c64.cpu.flags.n = 0;
    c64.cpu.pc = 0x1000;
    c64.mem.data[0x1000] = 0x28; // PLP
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(1, c64.cpu.flags.c);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(1, c64.cpu.flags.n);
}

test "CMP immediate" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x50;
    c64.mem.data[0x1000] = 0xC9; // CMP #$30
    c64.mem.data[0x1001] = 0x30;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(1, c64.cpu.flags.c); // $50 >= $30
    try std.testing.expectEqual(0, c64.cpu.flags.z); // Not equal
    try std.testing.expectEqual(0, c64.cpu.flags.n); // Positive
}

test "CPX zero page" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.x = 0x20;
    c64.cpu.writeByte(0x10, 0x0050);
    c64.mem.data[0x1000] = 0xE4; // CPX $50
    c64.mem.data[0x1001] = 0x50;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(1, c64.cpu.flags.c); // $20 >= $10
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "CPY absolute" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0xFF;
    c64.cpu.writeByte(0x01, 0x2000);
    c64.mem.data[0x1000] = 0xCC; // CPY $2000
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0x20;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(1, c64.cpu.flags.c); // $FF >= $01
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(1, c64.cpu.flags.n); // $FF - $01 = negative
}

test "AND immediate" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0b10101010;
    c64.mem.data[0x1000] = 0x29; // AND #$55
    c64.mem.data[0x1001] = 0x55; // 0b01010101
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0b00000000, c64.cpu.a);
    try std.testing.expectEqual(1, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "ORA zero page" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0b10100000;
    c64.cpu.writeByte(0b00001111, 0x0050);
    c64.mem.data[0x1000] = 0x05; // ORA $50
    c64.mem.data[0x1001] = 0x50;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0b10101111, c64.cpu.a);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(1, c64.cpu.flags.n);
}

test "EOR absolute" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0b11110000;
    c64.cpu.writeByte(0b10101010, 0x2000);
    c64.mem.data[0x1000] = 0x4D; // EOR $2000
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0x20;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0b01011010, c64.cpu.a);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "Indirect X addressing with LDA" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.x = 0x02;
    c64.cpu.writeByte(0x34, 0x0032); // Pointer low at $30 + X
    c64.cpu.writeByte(0x12, 0x0033); // Pointer high
    c64.cpu.writeByte(0x77, 0x1234); // Data at $1234
    c64.mem.data[0x1000] = 0xA1; // LDA ($30,X)
    c64.mem.data[0x1001] = 0x30;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x77, c64.cpu.a);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "Absolute Y addressing with STA" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x05;
    c64.cpu.a = 0x42;
    c64.mem.data[0x1000] = 0x99; // STA $2000,Y
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0x20;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x42, c64.cpu.readByte(0x2005));
}

test "Indirect X with zero page wrap" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.x = 0x05;
    c64.cpu.writeByte(0x34, 0x0004); // $FF + 5 = $04 (wraps)
    c64.cpu.writeByte(0x12, 0x0005);
    c64.cpu.writeByte(0x99, 0x1234);
    c64.mem.data[0x1000] = 0xA1; // LDA ($FF,X)
    c64.mem.data[0x1001] = 0xFF;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x99, c64.cpu.a);
}

test "Indirect Y with zero page wrap" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x02;
    c64.cpu.writeByte(0xFF, 0x00FE); // Pointer low
    c64.cpu.writeByte(0x01, 0x00FF); // Pointer high ($01FF)
    c64.cpu.writeByte(0x88, 0x0201); // $01FF + 2 = $0201
    c64.mem.data[0x1000] = 0xB1; // LDA ($FE),Y
    c64.mem.data[0x1001] = 0xFE;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x88, c64.cpu.a);
}

test "Indirect Y with page crossing" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0xFF;
    c64.cpu.writeByte(0x01, 0x0050); // $01FF
    c64.cpu.writeByte(0xFF, 0x0051);
    c64.cpu.writeByte(0xBB, 0x0000); // $01FF + $FF = $01FE + 1 = $0200, but wraps
    c64.mem.data[0x1000] = 0xB1; // LDA ($50),Y
    c64.mem.data[0x1001] = 0x50;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0xBB, c64.cpu.a);
}

test "LDA absolute X with page crossing" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.x = 0xFF;
    c64.cpu.writeByte(0x77, 0x02FF); // $200 + $FF = $2FF
    c64.mem.data[0x1000] = 0xBD; // LDA $200,X
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0x02;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x77, c64.cpu.a);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "LDA absolute Y with wrap around" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x01;
    c64.cpu.writeByte(0x88, 0x0000); // $FFFF + 1 wraps to $0000
    c64.mem.data[0x1000] = 0xB9; // LDA $FFFF,Y
    c64.mem.data[0x1001] = 0xFF;
    c64.mem.data[0x1002] = 0xFF;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x88, c64.cpu.a);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(1, c64.cpu.flags.n);
}

test "STA absolute X with edge case" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.x = 0x00;
    c64.cpu.a = 0x42;
    c64.mem.data[0x1000] = 0x9D; // STA $FFFF,X
    c64.mem.data[0x1001] = 0xFF;
    c64.mem.data[0x1002] = 0xFF;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x42, c64.cpu.readByte(0xFFFF));
}

test "Indirect X with page boundary" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.x = 0xFF;
    c64.cpu.writeByte(0x00, 0x00FF); // $00 + $FF = $FF
    c64.cpu.writeByte(0x20, 0x0000); // Wraps to $00, $2000
    c64.cpu.writeByte(0xAA, 0x2000);
    c64.mem.data[0x1000] = 0xA1; // LDA ($00,X)
    c64.mem.data[0x1001] = 0x00;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0xAA, c64.cpu.a);
}

test "SID register write" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x42;
    c64.mem.data[0x1000] = 0x8D; // STA $D400 (SID freq low)
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0xD4;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x42, c64.cpu.c64.sid.registers[0]);
    try std.testing.expectEqual(true, c64.cpu.sid_reg_written);
}

test "SID register write with change detection" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x55;
    c64.mem.data[0x1000] = 0x8D; // STA $D418 (SID volume)
    c64.mem.data[0x1001] = 0x18;
    c64.mem.data[0x1002] = 0xD4;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x55, c64.cpu.c64.sid.registers[24]);
    try std.testing.expectEqual(true, c64.cpu.sid_reg_changed);
    c64.cpu.a = 0x55; // Same value
    c64.cpu.pc = 0x1000;
    c64.cpu.sid_reg_changed = false;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(false, c64.cpu.sid_reg_changed); // No change
}

test "updateFlags zero and negative" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x00;
    c64.cpu.updateFlags(c64.cpu.a);
    try std.testing.expectEqual(1, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);

    c64.cpu.a = 0x80;
    c64.cpu.updateFlags(c64.cpu.a);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(1, c64.cpu.flags.n);

    c64.cpu.a = 0x7F;
    c64.cpu.updateFlags(c64.cpu.a);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "JMP indirect" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.writeByte(0x34, 0x2000); // Low byte
    c64.cpu.writeByte(0x12, 0x2001); // High byte ($1234)
    c64.mem.data[0x1000] = 0x6C; // JMP ($2000)
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0x20; // Fix typo: was $2002
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x1234, c64.cpu.pc);
}

test "BIT zero page" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0xAA;
    c64.cpu.writeByte(0xC0, 0x0050); // Bit 7 = 1, Bit 6 = 1
    c64.mem.data[0x1000] = 0x24; // BIT $50
    c64.mem.data[0x1001] = 0x50;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0, c64.cpu.flags.z); // A & $C0 != 0
    try std.testing.expectEqual(1, c64.cpu.flags.n);
    try std.testing.expectEqual(1, c64.cpu.flags.v);
}

test "TAX and TAY" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x42;
    c64.mem.data[0x1000] = 0xAA; // TAX
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x42, c64.cpu.x);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);

    c64.cpu.pc = 0x1000;
    c64.mem.data[0x1000] = 0xA8; // TAY
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x42, c64.cpu.y);
}

test "INX and INY" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.x = 0xFF;
    c64.mem.data[0x1000] = 0xE8; // INX
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x00, c64.cpu.x);
    try std.testing.expectEqual(1, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);

    c64.cpu.y = 0x7F;
    c64.cpu.pc = 0x1000;
    c64.mem.data[0x1000] = 0xC8; // INY
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x80, c64.cpu.y);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(1, c64.cpu.flags.n);
}

test "TSX transfer" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.sp = 0xAB;
    c64.mem.data[0x1000] = 0xBA; // TSX
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0xAB, c64.cpu.x);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(1, c64.cpu.flags.n);
}

test "TXA transfer" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.x = 0xFF;
    c64.mem.data[0x1000] = 0x8A; // TXA
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0xFF, c64.cpu.a);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(1, c64.cpu.flags.n);
}

test "DEC absolute X with wrap" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.x = 0x01;
    c64.cpu.writeByte(0x01, 0x0000); // $FFFF + 1 wraps to $0000
    c64.mem.data[0x1000] = 0xDE; // DEC $FFFF,X
    c64.mem.data[0x1001] = 0xFF;
    c64.mem.data[0x1002] = 0xFF;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x00, c64.cpu.readByte(0x0000));
    try std.testing.expectEqual(1, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "TYA transfer" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x42;
    c64.mem.data[0x1000] = 0x98; // TYA
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x42, c64.cpu.a);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "TXS transfer" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.x = 0xEE;
    c64.mem.data[0x1000] = 0x9A; // TXS
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0xEE, c64.cpu.sp);
}

test "SID register write overwrite" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x33;
    c64.mem.data[0x1000] = 0x8D; // STA $D404 (SID voice 1 control)
    c64.mem.data[0x1001] = 0x04;
    c64.mem.data[0x1002] = 0xD4;
    _ = c64.cpu.runStep();
    c64.cpu.a = 0x44;
    c64.cpu.pc = 0x1000; // Same address
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x44, c64.cpu.c64.sid.registers[4]);
    try std.testing.expectEqual(true, c64.cpu.sid_reg_changed); // Should detect change
}

test "SEC and CLC flag toggle" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.mem.data[0x1000] = 0x38; // SEC
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(1, c64.cpu.flags.c);
    c64.cpu.pc = 0x1000;
    c64.mem.data[0x1000] = 0x18; // CLC
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0, c64.cpu.flags.c);
}

test "JMP indirect at page boundary wrap bug" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.writeByte(0x34, 0x20FF); // Low byte
    c64.cpu.writeByte(0x12, 0x2000); // High byte should be $2000, not $2100 (6502 bug)
    c64.mem.data[0x1000] = 0x6C; // JMP ($20FF)
    c64.mem.data[0x1001] = 0xFF;
    c64.mem.data[0x1002] = 0x20;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x1234, c64.cpu.pc);
}

test "SID rapid write sequence" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x21; // Waveform: triangle
    c64.mem.data[0x1000] = 0x8D; // STA $D404
    c64.mem.data[0x1001] = 0x04;
    c64.mem.data[0x1002] = 0xD4;
    _ = c64.cpu.runStep();
    c64.cpu.a = 0x41; // Waveform: sawtooth
    c64.cpu.pc = 0x1000;
    _ = c64.cpu.runStep();
    c64.cpu.a = 0x81; // Waveform: noise
    c64.cpu.pc = 0x1000;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x81, c64.cpu.c64.sid.registers[4]);
    try std.testing.expectEqual(true, c64.cpu.sid_reg_changed);
}

test "JMP indirect with page boundary" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.writeByte(0x00, 0x20FF); // Low byte
    c64.cpu.writeByte(0x30, 0x2000); // High byte ($3000) - wrap to $2000!
    c64.mem.data[0x1000] = 0x6C; // JMP ($20FF)
    c64.mem.data[0x1001] = 0xFF;
    c64.mem.data[0x1002] = 0x20;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x3000, c64.cpu.pc);
}

test "CLD and SED decimal mode" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.mem.data[0x1000] = 0xF8; // SED
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(1, c64.cpu.flags.d);
    c64.cpu.pc = 0x1000;
    c64.mem.data[0x1000] = 0xD8; // CLD
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0, c64.cpu.flags.d);
}

test "ADC with decimal mode" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x29; // 29 decimal
    c64.cpu.flags.d = 1; // Decimal mode
    c64.mem.data[0x1000] = 0x69; // ADC #$15
    c64.mem.data[0x1001] = 0x15; // 15 decimal
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x44, c64.cpu.a); // 29 + 15 = 44 (BCD)
    try std.testing.expectEqual(0, c64.cpu.flags.c);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "PHA with stack wrap" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.sp = 0x00; // Stack at $0100
    c64.cpu.a = 0x42;
    c64.mem.data[0x1000] = 0x48; // PHA
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x42, c64.cpu.readByte(0x0100));
    try std.testing.expectEqual(0xFF, c64.cpu.sp); // Wraps to $FF
    c64.cpu.pc = 0x1000;
    c64.mem.data[0x1000] = 0x68; // PLA
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x42, c64.cpu.a);
    try std.testing.expectEqual(0x00, c64.cpu.sp);
}

test "LDA ADC STA sequence" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.writeByte(0x20, 0x0050); // Base value
    c64.mem.data[0x1000] = 0xA5; // LDA $50
    c64.mem.data[0x1001] = 0x50;
    c64.mem.data[0x1002] = 0x69; // ADC #$05
    c64.mem.data[0x1003] = 0x05;
    c64.mem.data[0x1004] = 0x8D; // STA $D400 (SID freq low)
    c64.mem.data[0x1005] = 0x00;
    c64.mem.data[0x1006] = 0xD4;
    _ = c64.cpu.runStep(); // LDA
    _ = c64.cpu.runStep(); // ADC
    _ = c64.cpu.runStep(); // STA
    try std.testing.expectEqual(0x25, c64.cpu.a); // 20 + 5 = 25
    try std.testing.expectEqual(0x25, c64.cpu.c64.sid.registers[0]);
}

test "SID overwrite with same value" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x42;
    c64.mem.data[0x1000] = 0x8D; // STA $D404 (SID voice 1 control)
    c64.mem.data[0x1001] = 0x04;
    c64.mem.data[0x1002] = 0xD4;
    _ = c64.cpu.runStep();
    c64.cpu.sid_reg_changed = false; // Reset flag
    c64.cpu.pc = 0x1000;
    c64.cpu.a = 0x42; // Same value
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x42, c64.cpu.c64.sid.registers[4]);
    try std.testing.expectEqual(false, c64.cpu.sid_reg_changed); // No change
}

test "LDX absolute Y with wrap" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x01;
    c64.cpu.writeByte(0x77, 0x0000); // $FFFF + 1 wraps
    c64.mem.data[0x1000] = 0xBE; // LDX $FFFF,Y
    c64.mem.data[0x1001] = 0xFF;
    c64.mem.data[0x1002] = 0xFF;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x77, c64.cpu.x);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "LDY absolute X with page cross" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.x = 0xFF;
    c64.cpu.writeByte(0x88, 0x02FF); // $200 + $FF
    c64.mem.data[0x1000] = 0xBC; // LDY $200,X
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0x02;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x88, c64.cpu.y);
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(1, c64.cpu.flags.n);
}

test "STX and STY to SID" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.x = 0x42;
    c64.mem.data[0x1000] = 0x8E; // STX $D400 (SID freq low)
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0xD4;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x42, c64.cpu.c64.sid.registers[0]);
    c64.cpu.y = 0x55;
    c64.cpu.pc = 0x1000;
    c64.mem.data[0x1000] = 0x8C; // STY $D400
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x55, c64.cpu.c64.sid.registers[0]);
}

test "CMP absolute X with page cross" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x50;
    c64.cpu.x = 0xFF;
    c64.cpu.writeByte(0x30, 0x02FF); // $200 + $FF
    c64.mem.data[0x1000] = 0xDD; // CMP $200,X
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0x02;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(1, c64.cpu.flags.c); // $50 >= $30
    try std.testing.expectEqual(0, c64.cpu.flags.z);
    try std.testing.expectEqual(0, c64.cpu.flags.n);
}

test "PHA PLA stack loop" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x42;
    c64.mem.data[0x1000] = 0x48; // PHA
    c64.mem.data[0x1001] = 0xA9; // LDA #$55
    c64.mem.data[0x1002] = 0x55;
    c64.mem.data[0x1003] = 0x48; // PHA
    c64.mem.data[0x1004] = 0x68; // PLA
    c64.mem.data[0x1005] = 0x68; // PLA
    _ = c64.cpu.runStep(); // PHA $42
    _ = c64.cpu.runStep(); // LDA $55
    _ = c64.cpu.runStep(); // PHA $55
    _ = c64.cpu.runStep(); // PLA $55
    try std.testing.expectEqual(0x55, c64.cpu.a);
    _ = c64.cpu.runStep(); // PLA $42
    try std.testing.expectEqual(0x42, c64.cpu.a);
    try std.testing.expectEqual(0xFD, c64.cpu.sp);
}

test "ORA to SID filter control" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x1F;
    c64.mem.data[0x1000] = 0x09; // ORA #$C0
    c64.mem.data[0x1001] = 0xC0;
    c64.mem.data[0x1002] = 0x8D; // STA $D417
    c64.mem.data[0x1003] = 0x17;
    c64.mem.data[0x1004] = 0xD4;
    _ = c64.cpu.runStep(); // ORA
    _ = c64.cpu.runStep(); // STA
    try std.testing.expectEqual(0xDF, c64.cpu.c64.sid.registers[23]); // Fix to $DF
}
test "SID register write sync" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);
    resetCpu(&c64.cpu);
    c64.cpu.a = 0xCF;
    c64.mem.data[0x1000] = 0x8D; // STA $D417
    c64.mem.data[0x1001] = 0x17;
    c64.mem.data[0x1002] = 0xD4;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0xCF, c64.sid.registers[23]);
    try std.testing.expectEqual(0xCF, c64.sid.getRegisters()[23]);
    try std.testing.expectEqual(0xCF, c64.mem.data[0xD417]);
}

test "SID multiple writes" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);
    resetCpu(&c64.cpu);
    c64.cpu.a = 0x82;
    c64.mem.data[0x1000] = 0x8D; // STA $D417
    c64.mem.data[0x1001] = 0x17;
    c64.mem.data[0x1002] = 0xD4;
    c64.mem.data[0x1003] = 0xA9; // LDA #$CF
    c64.mem.data[0x1004] = 0xCF;
    c64.mem.data[0x1005] = 0x8D; // STA $D417
    c64.mem.data[0x1006] = 0x17;
    c64.mem.data[0x1007] = 0xD4;
    _ = c64.cpu.runStep(); // STA $82
    _ = c64.cpu.runStep(); // LDA $CF
    _ = c64.cpu.runStep(); // STA $CF
    try std.testing.expectEqual(0xCF, c64.sid.registers[23]);
    try std.testing.expectEqual(0xCF, c64.sid.getRegisters()[23]);
    try std.testing.expectEqual(0xCF, c64.mem.data[0xD417]);
}

test "indirect indexed LDA - Frame 0 A7E1" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 1; // Frame 0: Y=1
    c64.cpu.x = 1; // Frame 0: X=1
    c64.cpu.pc = 0xA7E1;
    c64.mem.data[0xA7E1] = 0xB1; // LDA ($46),Y
    c64.mem.data[0xA7E2] = 0x46; // ZP $46
    c64.mem.data[0x46] = 0x2C; // Low byte
    c64.mem.data[0x47] = 0xB2; // High byte: $B22C
    c64.mem.data[0xB22D] = 0x82; // Expected $82 (adjust after dump)
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(@as(u8, 0x82), c64.cpu.a); // Loads $82?
}

test "indirect indexed LDA - Frame 1 AC90" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 5; // Frame 1: Y=5
    c64.cpu.x = 2; // Frame 1: X=2
    c64.cpu.pc = 0xAC90;
    c64.mem.data[0xAC90] = 0xB1; // LDA ($44),Y
    c64.mem.data[0xAC91] = 0x44; // ZP $44
    c64.mem.data[0x44] = 0xD6; // Low byte
    c64.mem.data[0x45] = 0xAF; // High byte: $AFD6
    c64.mem.data[0xAFDB] = 0x3F; // Expected $3F (adjust after dump)
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(@as(u8, 0x3F), c64.cpu.a); // Loads $3F?
}

test "indirect indexed LDA - Hunt for CF" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 1; // Frame 0: Y=1
    c64.cpu.x = 1; // Frame 0: X=1
    c64.cpu.pc = 0xA7E1;
    c64.mem.data[0xA7E1] = 0xB1; // LDA ($46),Y
    c64.mem.data[0xA7E2] = 0x46; // ZP $46
    c64.mem.data[0x46] = 0x2C; // Low byte
    c64.mem.data[0x47] = 0xB2; // High byte: $B22C
    c64.mem.data[0xB22D] = 0xCF; // Force $CF
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(@as(u8, 0xCF), c64.cpu.a); // Loads $CF?
}

test "indirect indexed LDA - Check Next Offset" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 2; // Try Y=2—$B22E = C4?
    c64.cpu.x = 1;
    c64.cpu.pc = 0xA7E1;
    c64.mem.data[0xA7E1] = 0xB1; // LDA ($46),Y
    c64.mem.data[0xA7E2] = 0x46;
    c64.mem.data[0x46] = 0x2C;
    c64.mem.data[0x47] = 0xB2; // $B22C
    c64.mem.data[0xB22E] = 0xC4; // From dump
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(@as(u8, 0xC4), c64.cpu.a);
}

test "indirect indexed LDA - Hunt CF Offset" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 3; // Try Y=3—$B22F = A0?
    c64.cpu.x = 1;
    c64.cpu.pc = 0xA7E1;
    c64.mem.data[0xA7E1] = 0xB1; // LDA ($46),Y
    c64.mem.data[0xA7E2] = 0x46;
    c64.mem.data[0x46] = 0x2C;
    c64.mem.data[0x47] = 0xB2; // $B22C
    c64.mem.data[0xB22F] = 0xA0; // From dump
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(@as(u8, 0xA0), c64.cpu.a); // $A0?
}

test "pushW and popW word" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu); // SP = $FD
    c64.cpu.pushW(0xABCD);
    try std.testing.expectEqual(0xABCD, c64.cpu.popW());
    try std.testing.expectEqual(0xFD, c64.cpu.sp);
}

test "pushW stack contents" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu); // SP = $FD
    c64.cpu.pushW(0x1234);
    try std.testing.expectEqual(0x34, c64.cpu.readByte(0x01FC)); // Low byte at $01FC
    try std.testing.expectEqual(0x12, c64.cpu.readByte(0x01FD)); // High byte at $01FD
    try std.testing.expectEqual(0xFB, c64.cpu.sp);
}

test "JSR and RTS" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu); // SP = $FD
    c64.mem.data[0x1000] = 0x20; // JSR $1234
    c64.mem.data[0x1001] = 0x34;
    c64.mem.data[0x1002] = 0x12;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x1234, c64.cpu.pc);
    try std.testing.expectEqual(0x1002, c64.cpu.readWord(0x01FC)); // $01FC-$01FD holds $1002
    c64.cpu.pc = 0x1234;
    c64.mem.data[0x1234] = 0x60; // RTS
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x1003, c64.cpu.pc);
    try std.testing.expectEqual(0xFD, c64.cpu.sp);
}

test "STA to SID D417" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);
    resetCpu(&c64.cpu);
    c64.cpu.a = 0xCF;
    c64.mem.data[0x1000] = 0x8D; // STA $D417
    c64.mem.data[0x1001] = 0x17;
    c64.mem.data[0x1002] = 0xD4;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0xCF, c64.cpu.c64.sid.registers[23]);
}

test "AND immediate preserves bit 7" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0xFF; // All bits set
    c64.mem.data[0x1000] = 0x29; // AND #$CF
    c64.mem.data[0x1001] = 0xCF;
    c64.mem.data[0x1002] = 0x8D; // STA $D417
    c64.mem.data[0x1003] = 0x17;
    c64.mem.data[0x1004] = 0xD4;
    _ = c64.cpu.runStep(); // AND
    try std.testing.expectEqual(0xCF, c64.cpu.a);
    _ = c64.cpu.runStep(); // STA
    try std.testing.expectEqual(0xCF, c64.cpu.c64.sid.registers[23]);
}

test "ORA immediate sets bit 7" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x00;
    c64.mem.data[0x1000] = 0x09; // ORA #$80
    c64.mem.data[0x1001] = 0x80;
    c64.mem.data[0x1002] = 0x8D; // STA $D417
    c64.mem.data[0x1003] = 0x17;
    c64.mem.data[0x1004] = 0xD4;
    _ = c64.cpu.runStep(); // ORA
    try std.testing.expectEqual(0x80, c64.cpu.a);
    _ = c64.cpu.runStep(); // STA
    try std.testing.expectEqual(0x80, c64.cpu.c64.sid.registers[23]);
}

test "EOR immediate flips bit 7" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x4F; // Bit 7 off
    c64.mem.data[0x1000] = 0x49; // EOR #$80
    c64.mem.data[0x1001] = 0x80;
    c64.mem.data[0x1002] = 0x8D; // STA $D417
    c64.mem.data[0x1003] = 0x17;
    c64.mem.data[0x1004] = 0xD4;
    _ = c64.cpu.runStep(); // EOR
    try std.testing.expectEqual(0xCF, c64.cpu.a); // $4F ^ $80 = $CF
    _ = c64.cpu.runStep(); // STA
    try std.testing.expectEqual(0xCF, c64.cpu.c64.sid.registers[23]);
}

test "ASL shifts into bit 7" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x67; // 01100111
    c64.mem.data[0x1000] = 0x0A; // ASL A
    c64.mem.data[0x1001] = 0x8D; // STA $D417
    c64.mem.data[0x1002] = 0x17;
    c64.mem.data[0x1003] = 0xD4;
    _ = c64.cpu.runStep(); // ASL
    try std.testing.expectEqual(0xCE, c64.cpu.a); // $67 << 1 = $CE
    try std.testing.expectEqual(0, c64.cpu.flags.c); // No carry
    _ = c64.cpu.runStep(); // STA
    try std.testing.expectEqual(0xCE, c64.cpu.c64.sid.registers[23]);
}

test "LSR clears bit 7" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0xCF; // 11001111
    c64.mem.data[0x1000] = 0x4A; // LSR A
    c64.mem.data[0x1001] = 0x8D; // STA $D417
    c64.mem.data[0x1002] = 0x17;
    c64.mem.data[0x1003] = 0xD4;
    _ = c64.cpu.runStep(); // LSR
    try std.testing.expectEqual(0x67, c64.cpu.a); // $CF >> 1 = $67
    try std.testing.expectEqual(1, c64.cpu.flags.c); // Carry set
    _ = c64.cpu.runStep(); // STA
    try std.testing.expectEqual(0x67, c64.cpu.c64.sid.registers[23]);
}

test "ADC sets bit 7" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x7F; // 01111111
    c64.cpu.flags.c = 0;
    c64.mem.data[0x1000] = 0x69; // ADC #$50
    c64.mem.data[0x1001] = 0x50;
    c64.mem.data[0x1002] = 0x8D; // STA $D417
    c64.mem.data[0x1003] = 0x17;
    c64.mem.data[0x1004] = 0xD4;
    _ = c64.cpu.runStep(); // ADC
    try std.testing.expectEqual(0xCF, c64.cpu.a); // $7F + $50 = $CF
    try std.testing.expectEqual(0, c64.cpu.flags.c);
    try std.testing.expectEqual(1, c64.cpu.flags.n);
    _ = c64.cpu.runStep(); // STA
    try std.testing.expectEqual(0xCF, c64.cpu.c64.sid.registers[23]);
}

test "ROL with carry sets bit 7" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0x4F; // 01001111
    c64.cpu.flags.c = 1;
    c64.mem.data[0x1000] = 0x2A; // ROL A
    c64.mem.data[0x1001] = 0x8D; // STA $D417
    c64.mem.data[0x1002] = 0x17;
    c64.mem.data[0x1003] = 0xD4;
    _ = c64.cpu.runStep(); // ROL
    try std.testing.expectEqual(0x9F, c64.cpu.a); // ($4F << 1) | 1 = $9F
    try std.testing.expectEqual(0, c64.cpu.flags.c);
    _ = c64.cpu.runStep(); // STA
    try std.testing.expectEqual(0x9F, c64.cpu.c64.sid.registers[23]);
}

test "STA absolute X to D417" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0xCF;
    c64.cpu.x = 0x02;
    c64.mem.data[0x1000] = 0x9D; // STA $D415,X
    c64.mem.data[0x1001] = 0x15;
    c64.mem.data[0x1002] = 0xD4;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0xCF, c64.cpu.c64.sid.registers[23]); // $D417 = 23
}

// Test 1: Basic Indirect Indexed Read
test "Basic Indirect Indexed LDA ($46),Y" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x00; // Start at Y=0
    c64.cpu.pc = 0x1000;

    // Set up pointer at $46,$47
    c64.cpu.writeByte(0x50, 0x0046); // Low byte
    c64.cpu.writeByte(0xAF, 0x0047); // High byte: $AF50
    c64.cpu.writeByte(0xAA, 0xAF50); // Data at $AF50

    // Program: LDA ($46),Y
    c64.mem.data[0x1000] = 0xB1; // LDA ($46),Y
    c64.mem.data[0x1001] = 0x46;

    _ = c64.cpu.runStep();
    try testing.expectEqual(@as(u8, 0xAA), c64.cpu.a);
    try testing.expectEqual(@as(u1, 0), c64.cpu.flags.z);
    try testing.expectEqual(@as(u1, 1), c64.cpu.flags.n); // $AA is negative
}

// Test 2: Indirect Indexed with Y Increment
test "Indirect Indexed LDA ($46),Y with Y Increment" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x00;
    c64.cpu.pc = 0x1000;

    // Fake table at $AF60
    c64.cpu.writeByte(0x60, 0x0046); // $46 = $60
    c64.cpu.writeByte(0xAF, 0x0047); // $47 = $AF
    c64.cpu.writeByte(0x11, 0xAF60); // Y=0
    c64.cpu.writeByte(0x22, 0xAF61); // Y=1
    c64.cpu.writeByte(0x33, 0xAF62); // Y=2

    // Program:
    // LDA ($46),Y  ; $11
    // INY
    // LDA ($46),Y  ; $22
    // INY
    // LDA ($46),Y  ; $33
    // STA $D401    ; Write to SID freq hi
    c64.mem.data[0x1000] = 0xB1; // LDA ($46),Y
    c64.mem.data[0x1001] = 0x46;
    c64.mem.data[0x1002] = 0xC8; // INY
    c64.mem.data[0x1003] = 0xB1; // LDA ($46),Y
    c64.mem.data[0x1004] = 0x46;
    c64.mem.data[0x1005] = 0xC8; // INY
    c64.mem.data[0x1006] = 0xB1; // LDA ($46),Y
    c64.mem.data[0x1007] = 0x46;
    c64.mem.data[0x1008] = 0x8D; // STA $D401
    c64.mem.data[0x1009] = 0x01;
    c64.mem.data[0x100A] = 0xD4;

    _ = c64.cpu.runStep(); // LDA $11
    _ = c64.cpu.runStep(); // INY
    _ = c64.cpu.runStep(); // LDA $22
    _ = c64.cpu.runStep(); // INY
    _ = c64.cpu.runStep(); // LDA $33
    _ = c64.cpu.runStep(); // STA $D401

    try testing.expectEqual(@as(u8, 0x33), c64.cpu.a);
    try testing.expectEqual(@as(u8, 0x33), c64.cpu.c64.sid.registers[1]);
    try testing.expectEqual(@as(u8, 0x02), c64.cpu.y);
}

// Test 3: Replicate Log at $A7E1
test "Indirect Indexed LDA ($46),Y from Log A7E1" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0xA7E1);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x01; // From log: Y=1 at $A7E1
    c64.cpu.x = 0x01; // From log: X=1
    c64.cpu.pc = 0xA7E1;

    // From log: $46,$47 = $B22C
    c64.cpu.writeByte(0x2C, 0x0046);
    c64.cpu.writeByte(0xB2, 0x0047);
    c64.cpu.writeByte(0x82, 0xB22D); // Y=1 should load $82 (matches $D417 write)

    // Program from log
    c64.mem.data[0xA7E1] = 0xB1; // LDA ($46),Y
    c64.mem.data[0xA7E2] = 0x46;
    c64.mem.data[0xA7E3] = 0x8D; // STA $D417 (next in log)
    c64.mem.data[0xA7E4] = 0x17;
    c64.mem.data[0xA7E5] = 0xD4;

    _ = c64.cpu.runStep(); // LDA ($46),Y
    try testing.expectEqual(@as(u8, 0x82), c64.cpu.a); // Should load $82
    _ = c64.cpu.runStep(); // STA $D417
    try testing.expectEqual(@as(u8, 0x82), c64.cpu.c64.sid.registers[23]);
}

// Test 5: Pointer Update and Read
test "Indirect Indexed LDA ($46),Y with Pointer Update" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x00;
    c64.cpu.pc = 0x1000;

    // Initial table at $AF70, then switch to $AF80
    c64.cpu.writeByte(0x70, 0x0046);
    c64.cpu.writeByte(0xAF, 0x0047);
    c64.cpu.writeByte(0xBB, 0xAF70);
    c64.cpu.writeByte(0xCC, 0xAF80);

    // Program:
    // LDA ($46),Y  ; $BB from $AF70
    // STA $D418
    // LDA #$80     ; Update $46 to $80
    // STA $46
    // LDA ($46),Y  ; $CC from $AF80
    // STA $D418
    c64.mem.data[0x1000] = 0xB1; // LDA ($46),Y
    c64.mem.data[0x1001] = 0x46;
    c64.mem.data[0x1002] = 0x8D; // STA $D418
    c64.mem.data[0x1003] = 0x18;
    c64.mem.data[0x1004] = 0xD4;
    c64.mem.data[0x1005] = 0xA9; // LDA #$80
    c64.mem.data[0x1006] = 0x80;
    c64.mem.data[0x1007] = 0x85; // STA $46
    c64.mem.data[0x1008] = 0x46;
    c64.mem.data[0x1009] = 0xB1; // LDA ($46),Y
    c64.mem.data[0x100A] = 0x46;
    c64.mem.data[0x100B] = 0x8D; // STA $D418
    c64.mem.data[0x100C] = 0x18;
    c64.mem.data[0x100D] = 0xD4;

    _ = c64.cpu.runStep(); // LDA $BB
    _ = c64.cpu.runStep(); // STA $D418
    try testing.expectEqual(@as(u8, 0xBB), c64.cpu.c64.sid.registers[24]);
    _ = c64.cpu.runStep(); // LDA #$80
    _ = c64.cpu.runStep(); // STA $46
    _ = c64.cpu.runStep(); // LDA $CC
    _ = c64.cpu.runStep(); // STA $D418
    try testing.expectEqual(@as(u8, 0xCC), c64.cpu.c64.sid.registers[24]);
    try testing.expectEqual(@as(u8, 0x80), c64.cpu.readByte(0x0046));
}

test "Indirect Indexed LDA ($46),Y Table Sequence" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x00;
    c64.cpu.pc = 0x1000;

    c64.cpu.writeByte(0x90, 0x0046);
    c64.cpu.writeByte(0xAF, 0x0047);
    c64.cpu.writeByte(0x04, 0xAF90);
    c64.cpu.writeByte(0x1A, 0xAF91);
    c64.cpu.writeByte(0xFF, 0xAF92);

    c64.mem.data[0x1000] = 0xA0; // LDY #$00
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0xB1; // LDA ($46),Y
    c64.mem.data[0x1003] = 0x46;
    c64.mem.data[0x1004] = 0xC9; // CMP #$FF
    c64.mem.data[0x1005] = 0xFF;
    c64.mem.data[0x1006] = 0xF0; // BEQ END
    c64.mem.data[0x1007] = 0x07; // Offset +7 to $100F
    c64.mem.data[0x1008] = 0x8D; // STA $D401
    c64.mem.data[0x1009] = 0x01;
    c64.mem.data[0x100A] = 0xD4;
    c64.mem.data[0x100B] = 0xC8; // INY
    c64.mem.data[0x100C] = 0x4C; // JMP LOOP
    c64.mem.data[0x100D] = 0x02;
    c64.mem.data[0x100E] = 0x10;
    c64.mem.data[0x100F] = 0xEA; // NOP (END)

    _ = c64.cpu.runStep(); // LDY #$00
    _ = c64.cpu.runStep(); // LDA $04
    try testing.expectEqual(@as(u8, 0x04), c64.cpu.a);
    _ = c64.cpu.runStep(); // CMP #$FF
    _ = c64.cpu.runStep(); // BEQ (no)
    _ = c64.cpu.runStep(); // STA $D401
    try testing.expectEqual(@as(u8, 0x04), c64.cpu.c64.sid.registers[1]);
    _ = c64.cpu.runStep(); // INY
    _ = c64.cpu.runStep(); // JMP $1002
    _ = c64.cpu.runStep(); // LDA $1A
    try testing.expectEqual(@as(u8, 0x1A), c64.cpu.a);
    _ = c64.cpu.runStep(); // CMP #$FF
    _ = c64.cpu.runStep(); // BEQ (no)
    _ = c64.cpu.runStep(); // STA $D401
    try testing.expectEqual(@as(u8, 0x1A), c64.cpu.c64.sid.registers[1]);
    _ = c64.cpu.runStep(); // INY
    _ = c64.cpu.runStep(); // JMP $1002
    _ = c64.cpu.runStep(); // LDA $FF
    try testing.expectEqual(@as(u8, 0xFF), c64.cpu.a);
    _ = c64.cpu.runStep(); // CMP #$FF
    _ = c64.cpu.runStep(); // BEQ (yes)
    try testing.expectEqual(@as(u16, 0x100F), c64.cpu.pc);
}

// Test Indirect Indexed with Page Crossing and Bit Manipulation
test "Indirect Indexed LDA ($46),Y with Page Cross and ASL" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0xFF; // Y=255, will cross page
    c64.cpu.pc = 0x1000;

    // Pointer at $46: $AFFE + $FF = $B0FD -> $B0FE
    c64.cpu.writeByte(0xFE, 0x0046);
    c64.cpu.writeByte(0xAF, 0x0047);
    c64.cpu.writeByte(0x42, 0xB0FD); // $AFFE + $FF = $B0FD

    // Program:
    // LDA ($46),Y  ; Load $42 from $B0FD
    // ASL A        ; Shift left: $42 -> $84
    // STA $D401    ; Write to SID freq hi
    c64.mem.data[0x1000] = 0xB1; // LDA ($46),Y
    c64.mem.data[0x1001] = 0x46;
    c64.mem.data[0x1002] = 0x0A; // ASL A
    c64.mem.data[0x1003] = 0x8D; // STA $D401
    c64.mem.data[0x1004] = 0x01;
    c64.mem.data[0x1005] = 0xD4;

    _ = c64.cpu.runStep(); // LDA $42
    try testing.expectEqual(@as(u8, 0x42), c64.cpu.a);
    _ = c64.cpu.runStep(); // ASL
    try testing.expectEqual(@as(u8, 0x84), c64.cpu.a);
    try testing.expectEqual(@as(u1, 0), c64.cpu.flags.c); // No carry
    try testing.expectEqual(@as(u1, 1), c64.cpu.flags.n); // Negative
    _ = c64.cpu.runStep(); // STA
    try testing.expectEqual(@as(u8, 0x84), c64.cpu.c64.sid.registers[1]);
}

// Test Table Read with Stack Wrap and EOR
test "Indirect Indexed LDA ($46),Y with Stack Wrap and EOR" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x01;
    c64.cpu.sp = 0x00; // Stack at $0100
    c64.cpu.pc = 0x1000;

    // Pointer at $46: $AF00
    c64.cpu.writeByte(0x00, 0x0046);
    c64.cpu.writeByte(0xAF, 0x0047);
    c64.cpu.writeByte(0x55, 0xAF01); // Y=1

    // Program:
    // LDA ($46),Y  ; Load $55
    // PHA          ; Push to stack ($0100)
    // LDA #$AA     ; Load mask
    // EOR $0100    ; XOR with stack value: $55 ^ $AA = $FF
    // STA $D418    ; Write to SID volume
    c64.mem.data[0x1000] = 0xB1; // LDA ($46),Y
    c64.mem.data[0x1001] = 0x46;
    c64.mem.data[0x1002] = 0x48; // PHA
    c64.mem.data[0x1003] = 0xA9; // LDA #$AA
    c64.mem.data[0x1004] = 0xAA;
    c64.mem.data[0x1005] = 0x4D; // EOR $0100
    c64.mem.data[0x1006] = 0x00;
    c64.mem.data[0x1007] = 0x01;
    c64.mem.data[0x1008] = 0x8D; // STA $D418
    c64.mem.data[0x1009] = 0x18;
    c64.mem.data[0x100A] = 0xD4;

    _ = c64.cpu.runStep(); // LDA $55
    try testing.expectEqual(@as(u8, 0x55), c64.cpu.a);
    _ = c64.cpu.runStep(); // PHA
    try testing.expectEqual(@as(u8, 0x55), c64.cpu.readByte(0x0100));
    try testing.expectEqual(@as(u8, 0xFF), c64.cpu.sp);
    _ = c64.cpu.runStep(); // LDA #$AA
    _ = c64.cpu.runStep(); // EOR $0100
    try testing.expectEqual(@as(u8, 0xFF), c64.cpu.a); // $55 ^ $AA
    try testing.expectEqual(@as(u1, 1), c64.cpu.flags.n);
    _ = c64.cpu.runStep(); // STA $D418
    try testing.expectEqual(@as(u8, 0xFF), c64.cpu.c64.sid.registers[24]);
}

// Test Indirect Indexed with AND and Negative Offset Branch
test "Indirect Indexed LDA ($46),Y with AND and BNE Edge" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x00;
    c64.cpu.pc = 0x1000;

    // Table at $AF00
    c64.cpu.writeByte(0x00, 0x0046);
    c64.cpu.writeByte(0xAF, 0x0047);
    c64.cpu.writeByte(0xF0, 0xAF00); // Y=0
    c64.cpu.writeByte(0x0F, 0xAF01); // Y=1 (end)

    // Program:
    // LDY #$00
    // LOOP:
    // LDA ($46),Y  ; Load table value
    // AND #$0F     ; Mask lower nibble
    // BNE LOOP     ; Branch back if not zero (offset -6)
    // STA $D417    ; Write to SID filter
    c64.mem.data[0x1000] = 0xA0; // LDY #$00
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0xB1; // LDA ($46),Y
    c64.mem.data[0x1003] = 0x46;
    c64.mem.data[0x1004] = 0x29; // AND #$0F
    c64.mem.data[0x1005] = 0x0F;
    c64.mem.data[0x1006] = 0xD0; // BNE LOOP
    c64.mem.data[0x1007] = 0xFA; // Offset -6 to $1002 (-6 = 0xFA in two’s complement)
    c64.mem.data[0x1008] = 0x8D; // STA $D417
    c64.mem.data[0x1009] = 0x17;
    c64.mem.data[0x100A] = 0xD4;

    _ = c64.cpu.runStep(); // LDY #$00
    _ = c64.cpu.runStep(); // LDA $F0
    try testing.expectEqual(@as(u8, 0xF0), c64.cpu.a);
    _ = c64.cpu.runStep(); // AND #$0F
    try testing.expectEqual(@as(u8, 0x00), c64.cpu.a); // $F0 & $0F = $00
    try testing.expectEqual(@as(u1, 1), c64.cpu.flags.z);
    _ = c64.cpu.runStep(); // BNE (no branch, z=1)
    try testing.expectEqual(@as(u16, 0x1008), c64.cpu.pc);
    _ = c64.cpu.runStep(); // STA $D417
    try testing.expectEqual(@as(u8, 0x00), c64.cpu.c64.sid.registers[23]);
    // Reset and loop again
    c64.cpu.y = 0x01;
    c64.cpu.pc = 0x1002;
    _ = c64.cpu.runStep(); // LDA $0F
    try testing.expectEqual(@as(u8, 0x0F), c64.cpu.a);
    _ = c64.cpu.runStep(); // AND #$0F
    try testing.expectEqual(@as(u8, 0x0F), c64.cpu.a);
    try testing.expectEqual(@as(u1, 0), c64.cpu.flags.z);
    _ = c64.cpu.runStep(); // BNE (branch to $1002)
    try testing.expectEqual(@as(u16, 0x1002), c64.cpu.pc);
}

// Test ROR with Debug
test "Indirect Indexed LDA ($46),Y Loop with ROR and BEQ Edge" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x00;
    c64.cpu.pc = 0x1000;

    c64.cpu.writeByte(0xFF, 0x0046);
    c64.cpu.writeByte(0xAF, 0x0047);
    c64.cpu.writeByte(0x81, 0xAFFF);
    c64.cpu.writeByte(0x01, 0xB000);
    c64.cpu.writeByte(0x00, 0xB001);

    c64.mem.data[0x1000] = 0xA0;
    c64.mem.data[0x1001] = 0x00;
    c64.mem.data[0x1002] = 0xB1;
    c64.mem.data[0x1003] = 0x46;
    c64.mem.data[0x1004] = 0x6A;
    c64.mem.data[0x1005] = 0xC9;
    c64.mem.data[0x1006] = 0x00;
    c64.mem.data[0x1007] = 0xF0;
    c64.mem.data[0x1008] = 0x07;
    c64.mem.data[0x1009] = 0x8D;
    c64.mem.data[0x100A] = 0x01;
    c64.mem.data[0x100B] = 0xD4;
    c64.mem.data[0x100C] = 0xC8;
    c64.mem.data[0x100D] = 0x4C;
    c64.mem.data[0x100E] = 0x02;
    c64.mem.data[0x100F] = 0x10;
    c64.mem.data[0x1010] = 0xEA;

    _ = c64.cpu.runStep(); // LDY
    _ = c64.cpu.runStep(); // LDA $81
    try testing.expectEqual(@as(u8, 0x81), c64.cpu.a);
    _ = c64.cpu.runStep(); // ROR
    try testing.expectEqual(@as(u8, 0x40), c64.cpu.a);
    try testing.expectEqual(@as(u1, 1), c64.cpu.flags.c);
}

test "Indirect Indexed LDA ($FF),Y with Zero-Page Wrap" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x02;
    c64.cpu.pc = 0x1000;

    c64.cpu.writeByte(0xFE, 0x00FF);
    c64.cpu.writeByte(0xAF, 0x0000);
    c64.cpu.writeByte(0x77, 0xB000);

    c64.mem.data[0x1000] = 0xB1;
    c64.mem.data[0x1001] = 0xFF;
    c64.mem.data[0x1002] = 0x8D;
    c64.mem.data[0x1003] = 0x18;
    c64.mem.data[0x1004] = 0xD4;

    _ = c64.cpu.runStep(); // Execute $B1
    try testing.expectEqual(@as(u8, 0x77), c64.cpu.a);
    _ = c64.cpu.runStep();
    try testing.expectEqual(@as(u8, 0x77), c64.cpu.c64.sid.registers[24]);
}

test "SID $D419 Write" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.a = 0xCF;
    c64.mem.data[0x1000] = 0x8D; // STA $D419
    c64.mem.data[0x1001] = 0x18;
    c64.mem.data[0x1002] = 0xD4;

    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0xCF, c64.cpu.c64.sid.registers[24]);
}

test "SID $A7E6 to $D418" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0xA7E1);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.y = 0x01;
    c64.cpu.x = 0x01;
    c64.cpu.sp = 0xFB;
    c64.cpu.pc = 0xA7E1;

    c64.cpu.writeByte(0x2C, 0x0046);
    c64.cpu.writeByte(0xB2, 0x0047);
    c64.cpu.writeByte(0x82, 0xB22D); // From log

    // $A7E1 to $A7E8
    c64.mem.data[0xA7E1] = 0xB1; // LDA ($46),Y
    c64.mem.data[0xA7E2] = 0x46;
    c64.mem.data[0xA7E3] = 0x8D; // STA $D417
    c64.mem.data[0xA7E4] = 0x17;
    c64.mem.data[0xA7E5] = 0xD4;
    c64.mem.data[0xA7E6] = 0x20; // JSR $A932
    c64.mem.data[0xA7E7] = 0x32;
    c64.mem.data[0xA7E8] = 0xA9;

    // $A932 subroutine (from log)
    c64.mem.data[0xA932] = 0xFE; // INC $30A6,X (placeholder)
    c64.mem.data[0xA933] = 0x30;
    c64.mem.data[0xA934] = 0xA6;
    c64.mem.data[0xA935] = 0xC8; // INY
    c64.mem.data[0xA936] = 0xB1; // LDA ($46),Y
    c64.mem.data[0xA937] = 0x46;
    c64.mem.data[0xA938] = 0xC9; // CMP #$FF
    c64.mem.data[0xA939] = 0xFF;

    _ = c64.cpu.runStep(); // LDA $82
    _ = c64.cpu.runStep(); // STA $D417
    try std.testing.expectEqual(0x82, c64.cpu.c64.sid.registers[23]);
    _ = c64.cpu.runStep(); // JSR $A932
    // Add more steps if $D418 write is here
}
