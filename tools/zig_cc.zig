//! `zig cc` as the C compiler cargo's cc crate calls when it builds the
//! host's C dependencies for a musl target. cc-rs appends a Rust target
//! triple (`--target=x86_64-unknown-linux-musl`) that Zig does not know, so
//! it is dropped, and the Zig triple from `ZIG_CC_TARGET` is used instead.
//! `ZIG_EXE` is the zig that runs the build.

const std = @import("std");

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const env = init.environ_map;
    const args = try init.minimal.args.toSlice(arena);
    const target = env.get("ZIG_CC_TARGET") orelse {
        std.debug.print("zig_cc: ZIG_CC_TARGET must be set\n", .{});
        return 2;
    };
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ env.get("ZIG_EXE") orelse "zig", "cc", "-target", target });
    for (args[1..]) |arg| {
        if (!std.mem.startsWith(u8, arg, "--target=")) try argv.append(arena, arg);
    }
    var child = try std.process.spawn(init.io, .{ .argv = argv.items });
    return switch (try child.wait(init.io)) {
        .exited => |code| code,
        else => 1,
    };
}
