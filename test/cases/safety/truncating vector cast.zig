const std = @import("std");

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = stack_trace;
    if (std.mem.eql(u8, message, "integer does not fit in destination type")) {
        std.process.exit(0);
    }
    std.process.exit(1);
}

pub fn main() !void {
    var x: @Vector(4, u32) = @splat(0xdeadbeef);
    _ = &x;
    const y: @Vector(4, u16) = @intCast(x);
    _ = y;
    return error.TestFailed;
}

// run
// backend=stage2,llvm
// target=x86_64-linux
