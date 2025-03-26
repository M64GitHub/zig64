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

test "pushW and popW word" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.pushW(0xABCD);
    try std.testing.expectEqual(0xABCD, c64.cpu.popW());
    try std.testing.expectEqual(0xFD, c64.cpu.sp);
}

test "pushW stack contents" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.cpu.pushW(0x1234);
    try std.testing.expectEqual(0x34, c64.cpu.readByte(0x01FB));
    try std.testing.expectEqual(0x12, c64.cpu.readByte(0x01FC));
    try std.testing.expectEqual(0xFB, c64.cpu.sp);
}

test "JSR and RTS" {
    var c64 = try C64.init(gpa, C64.Vic.Model.pal, 0x1000);
    defer c64.deinit(gpa);

    resetCpu(&c64.cpu);
    c64.mem.data[0x1000] = 0x20; // JSR $1234
    c64.mem.data[0x1001] = 0x34;
    c64.mem.data[0x1002] = 0x12;
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x1234, c64.cpu.pc);
    try std.testing.expectEqual(0x1002, c64.cpu.readWord(0x01FB)); // Check stack, don’t pop

    c64.cpu.pc = 0x1234;
    c64.mem.data[0x1234] = 0x60; // RTS
    _ = c64.cpu.runStep();
    try std.testing.expectEqual(0x1003, c64.cpu.pc);
    try std.testing.expectEqual(0xFD, c64.cpu.sp);
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
