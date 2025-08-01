const std = @import("std");

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = stack_trace;
    if (std.mem.eql(u8, message, "source and destination arguments have non-equal lengths")) {
        std.process.exit(0);
    }
    std.process.exit(1);
}
pub fn main() !void {
    var buffer = [2]u8{ 1, 2 } ** 5;
    var len: usize = 5;
    _ = &len;
    @memmove(buffer[0..len], buffer[len .. len + 4]);
    return error.TestFailed;
}
// run
// backend=stage2,llvm
// target=x86_64-linux,aarch64-linux
