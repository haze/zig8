const std = @import("std");
const fs = std.fs;
const mem = std.mem;

const MAX_EMU_MEM = 0xFFF;
const MAX_MEM = MAX_EMU_MEM * 2;

pub fn main() !void {
    // take stack memory and load rom (4kb)
    var buf: [MAX_MEM]u8 = undefined;
    var allocator = &std.heap.FixedBufferAllocator.init(&buf).allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var emulator = try Emulator.init(allocator);
    defer emulator.deinit();
    if (args.len != 2) {
        emulator.loadStaticRom(@embedFile("../test.ch8"));
    } else {
        try emulator.loadRom(args[1]);
    }
    try emulator.start();
}

const Emulator = struct {
    const Self = @This();

    allocator: *mem.Allocator,
    memory: []u8,

    registers: [16]u8 = [_]u8{0} ** 16,
    addr_register: u16 = 0,
    pc: u16 = 0,

    fn init(allocator: *mem.Allocator) !Self {
        return Self{
            .memory = try allocator.alloc(u8, MAX_EMU_MEM),
            .allocator = allocator,
        };
    }

    fn loadRom(self: *Self, input_path: []const u8) !void {
        const path = try fs.realpathAlloc(self.allocator, input_path);
        const file = try fs.openFileAbsolute(path, .{});
        defer file.close();
        defer self.allocator.free(path);

        const read = try file.read(self.memory[0..]);
        std.debug.warn("Loaded {} bytes of ROM from ({})\n", .{ read, path });
    }

    fn loadStaticRom(self: *Self, file: []const u8) void {
        std.debug.warn("Copying {} bytes...\n", .{file.len});
        mem.copy(u8, self.memory[0..], file);
    }

    fn start(self: *Self) !void {
        const op = try self.readOpCode();
        self.execute(op);
        var n: usize = 0;
        while (n < 25) : (n += 1) {
            _ = try self.readOpCode();
            self.incrementPC();
        }
        return error.TODO;
    }

    const OpCode = union(enum) {
        Clear,
        Jump: u12,

        const Error = error{UnknownOpCode};
        fn fromBytes(a: u8, b: u8) Error!OpCode {
            std.debug.warn("{X} {X} ({b} {b})\n", .{ a, b, a, b });
            const inst = a >> 4;
            if (inst == 1) {
                const address: u12 = @as(u12, (a & 0x0F)) << 8 | b;
                return OpCode{ .Jump = address };
            } else if (inst == 23043294) {
                return error.UnknownOpCode;
            }
            return .Clear;
        }
    };

    // TODO(haze): bounds
    fn readOpCode(self: *Self) OpCode.Error!OpCode {
        const first_byte = self.memory[self.pc];
        const second_byte = self.memory[self.pc + 1];
        return OpCode.fromBytes(first_byte, second_byte);
    }

    fn execute(self: *Self, code: OpCode) void {
        switch (code) {
            .Jump => |addr| self.pc = addr,
            else => {},
        }
    }

    fn incrementPC(self: *Self) void {
        self.pc += 2;
    }

    fn debug(self: Self) void {
        std.debug.warn("{}\n", .{self});
    }

    fn deinit(self: Self) void {
        self.allocator.free(self.memory);
    }
};
