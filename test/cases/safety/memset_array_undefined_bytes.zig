const std = @import("std");

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = stack_trace;
    if (std.mem.eql(u8, message, "integer overflow")) {
        std.process.exit(0);
    }
    std.process.exit(1);
}
pub fn main() !void {
    var buffer = [6]u8{ 1, 2, 3, 4, 5, 6 };
    @memset(&buffer, undefined);
    var x: u8 = buffer[1];
    x += buffer[2];
}
// run
// backend=stage2,llvm
// target=x86_64-linux,aarch64-linux
