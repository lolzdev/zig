const std = @import("std");
const builtin = @import("builtin");
const arch = builtin.cpu.arch;
const os = builtin.os.tag;
const common = @import("common.zig");
pub const panic = common.panic;

// Ported from llvm-project d32170dbd5b0d54436537b6b75beaf44324e0c28

// The compiler generates calls to __clear_cache() when creating
// trampoline functions on the stack for use with nested functions.
// It is expected to invalidate the instruction cache for the
// specified range.

comptime {
    _ = &clear_cache;
}

fn clear_cache(start: usize, end: usize) callconv(.c) void {
    const x86 = switch (arch) {
        .x86, .x86_64 => true,
        else => false,
    };
    const arm32 = switch (arch) {
        .arm, .armeb, .thumb, .thumbeb => true,
        else => false,
    };
    const arm64 = switch (arch) {
        .aarch64, .aarch64_be => true,
        else => false,
    };
    const loongarch = switch (arch) {
        .loongarch32,
        .loongarch64,
        => true,
        else => false,
    };
    const mips = switch (arch) {
        .mips, .mipsel, .mips64, .mips64el => true,
        else => false,
    };
    const riscv = switch (arch) {
        .riscv32, .riscv64 => true,
        else => false,
    };
    const powerpc64 = switch (arch) {
        .powerpc64, .powerpc64le => true,
        else => false,
    };
    const sparc = switch (arch) {
        .sparc, .sparc64 => true,
        else => false,
    };
    const apple = switch (os) {
        .ios, .macos, .watchos, .tvos, .visionos => true,
        else => false,
    };
    if (x86) {
        // Intel processors have a unified instruction and data cache
        // so there is nothing to do
        exportIt();
    } else if (os == .windows and (arm32 or arm64)) {
        // TODO
        // FlushInstructionCache(GetCurrentProcess(), start, end - start);
        // exportIt();
    } else if (arm32 and !apple) {
        switch (os) {
            .freebsd, .netbsd => {
                var arg = arm_sync_icache_args{
                    .addr = start,
                    .len = end - start,
                };
                const result = sysarch(ARM_SYNC_ICACHE, @intFromPtr(&arg));
                std.debug.assert(result == 0);
                exportIt();
            },
            .linux => {
                const result = std.os.linux.syscall3(.cacheflush, start, end, 0);
                std.debug.assert(result == 0);
                exportIt();
            },
            else => {},
        }
    } else if (os == .linux and mips) {
        const flags = 3; // ICACHE | DCACHE
        const result = std.os.linux.syscall3(.cacheflush, start, end - start, flags);
        std.debug.assert(result == 0);
        exportIt();
    } else if (os == .netbsd and mips) {
        // Replace with https://github.com/ziglang/zig/issues/23904 in the future.
        const cfa: extern struct {
            va: usize,
            nbytes: usize,
            whichcache: u32,
        } = .{
            .va = start,
            .nbytes = end - start,
            .whichcache = 3, // ICACHE | DCACHE
        };
        asm volatile ("syscall"
            :
            : [_] "{$2}" (165), // nr = SYS_sysarch
              [_] "{$4}" (0), // op = MIPS_CACHEFLUSH
              [_] "{$5}" (&cfa), // args = &cfa
            : .{ .r1 = true, .r2 = true, .r3 = true, .r4 = true, .r5 = true, .r6 = true, .r7 = true, .r8 = true, .r9 = true, .r10 = true, .r11 = true, .r12 = true, .r13 = true, .r14 = true, .r15 = true, .r24 = true, .r25 = true, .hi = true, .lo = true, .memory = true });
        exportIt();
    } else if (mips and os == .openbsd) {
        // TODO
        //cacheflush(start, (uintptr_t)end - (uintptr_t)start, BCACHE);
        // exportIt();
    } else if (os == .linux and riscv) {
        const result = std.os.linux.syscall3(.riscv_flush_icache, start, end - start, 0);
        std.debug.assert(result == 0);
        exportIt();
    } else if (arm64 and !apple) {
        // Get Cache Type Info.
        // TODO memoize this?
        const ctr_el0 = asm volatile ("mrs %[ctr_el0], ctr_el0"
            : [ctr_el0] "=r" (-> u64),
        );
        // The DC and IC instructions must use 64-bit registers so we don't use
        // uintptr_t in case this runs in an IPL32 environment.
        var addr: u64 = undefined;
        // If CTR_EL0.IDC is set, data cache cleaning to the point of unification
        // is not required for instruction to data coherence.
        if (((ctr_el0 >> 28) & 0x1) == 0x0) {
            const dcache_line_size = @as(usize, 4) << @intCast((ctr_el0 >> 16) & 15);
            addr = start & ~(dcache_line_size - 1);
            while (addr < end) : (addr += dcache_line_size) {
                asm volatile ("dc cvau, %[addr]"
                    :
                    : [addr] "r" (addr),
                );
            }
        }
        asm volatile ("dsb ish");
        // If CTR_EL0.DIC is set, instruction cache invalidation to the point of
        // unification is not required for instruction to data coherence.
        if (((ctr_el0 >> 29) & 0x1) == 0x0) {
            const icache_line_size = @as(usize, 4) << @intCast((ctr_el0 >> 0) & 15);
            addr = start & ~(icache_line_size - 1);
            while (addr < end) : (addr += icache_line_size) {
                asm volatile ("ic ivau, %[addr]"
                    :
                    : [addr] "r" (addr),
                );
            }
        }
        asm volatile ("isb sy");
        exportIt();
    } else if (powerpc64) {
        // TODO
        //const size_t line_size = 32;
        //const size_t len = (uintptr_t)end - (uintptr_t)start;
        //
        //const uintptr_t mask = ~(line_size - 1);
        //const uintptr_t start_line = ((uintptr_t)start) & mask;
        //const uintptr_t end_line = ((uintptr_t)start + len + line_size - 1) & mask;
        //
        //for (uintptr_t line = start_line; line < end_line; line += line_size)
        //  __asm__ volatile("dcbf 0, %0" : : "r"(line));
        //__asm__ volatile("sync");
        //
        //for (uintptr_t line = start_line; line < end_line; line += line_size)
        //  __asm__ volatile("icbi 0, %0" : : "r"(line));
        //__asm__ volatile("isync");
        // exportIt();
    } else if (sparc) {
        // TODO
        //const size_t dword_size = 8;
        //const size_t len = (uintptr_t)end - (uintptr_t)start;
        //
        //const uintptr_t mask = ~(dword_size - 1);
        //const uintptr_t start_dword = ((uintptr_t)start) & mask;
        //const uintptr_t end_dword = ((uintptr_t)start + len + dword_size - 1) & mask;
        //
        //for (uintptr_t dword = start_dword; dword < end_dword; dword += dword_size)
        //  __asm__ volatile("flush %0" : : "r"(dword));
        // exportIt();
    } else if (apple) {
        // On Darwin, sys_icache_invalidate() provides this functionality
        sys_icache_invalidate(start, end - start);
        exportIt();
    } else if (os == .linux and loongarch) {
        // See: https://github.com/llvm/llvm-project/blob/cf54cae26b65fc3201eff7200ffb9b0c9e8f9a13/compiler-rt/lib/builtins/clear_cache.c#L94-L95
        asm volatile ("ibar 0");
        exportIt();
    }

    std.valgrind.discardTranslations(@as([*]u8, @ptrFromInt(start))[0 .. end - start]);
}

fn exportIt() void {
    @export(&clear_cache, .{ .name = "__clear_cache", .linkage = common.linkage, .visibility = common.visibility });
}

// Darwin-only
extern fn sys_icache_invalidate(start: usize, len: usize) void;
// BSD-only
const arm_sync_icache_args = extern struct {
    addr: usize, // Virtual start address
    len: usize, // Region size
};
const ARM_SYNC_ICACHE = 0;
extern "c" fn sysarch(number: i32, args: usize) i32;
