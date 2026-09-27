//! The platform's build, in place of scripts/build.py and scripts/bundle.py.
//!
//!     zig build                         the host for this machine
//!     zig build -Dhost=all              every host this OS can build
//!     zig build -Dhost=x64musl,arm64musl
//!     zig build bundle -- --output-dir dist [--target T ...] [roc bundle args]
//!
//! The host is the Rust half of the platform: cargo builds it, and it is put
//! at platform/targets/<target>/libhost.a (host.lib on Windows), where roc
//! links apps against it. `bundle` packages the platform with `roc bundle`.

const std = @import("std");

const Host = struct {
    name: []const u8,
    rust: []const u8,
    /// The Zig triple of a musl target, whose C dependencies cargo compiles
    /// with `zig cc` (tools/zig_cc.zig).
    zig: ?[]const u8 = null,
    os: std.Target.Os.Tag,
    arch: std.Target.Cpu.Arch,
};

const hosts = [_]Host{
    .{ .name = "x64musl", .rust = "x86_64-unknown-linux-musl", .zig = "x86_64-linux-musl", .os = .linux, .arch = .x86_64 },
    .{ .name = "arm64musl", .rust = "aarch64-unknown-linux-musl", .zig = "aarch64-linux-musl", .os = .linux, .arch = .aarch64 },
    .{ .name = "x64mac", .rust = "x86_64-apple-darwin", .os = .macos, .arch = .x86_64 },
    .{ .name = "arm64mac", .rust = "aarch64-apple-darwin", .os = .macos, .arch = .aarch64 },
    .{ .name = "x64win", .rust = "x86_64-pc-windows-msvc", .os = .windows, .arch = .x86_64 },
};

/// The Windows SDK import libraries the x64win host links with, copied next
/// to host.lib.
const windows_system_libraries = [_][]const u8{ "advapi32.lib", "bcrypt.lib", "ws2_32.lib" };

pub fn build(b: *std.Build) void {
    const host_names = b.option([]const u8, "host", "Hosts to build: native (default), all, none, or names such as x64musl,arm64musl") orelse "native";
    const features = b.option([]const u8, "host-features", "Comma-separated Cargo features, for non-production hosts") orelse "";

    // Helper programs run by this build, for the machine running it.
    const zig_cc = b.addExecutable(.{
        .name = "zig-cc",
        .root_module = b.createModule(.{ .root_source_file = b.path("tools/zig_cc.zig"), .target = b.graph.host, .optimize = .ReleaseSafe }),
    });
    // Only cargo calls it, so it stays out of bin/.
    const zig_cc_install = b.addInstallArtifact(zig_cc, .{ .dest_dir = .{ .override = .{ .custom = "tools" } } });

    const host_step = b.step("host", "Build the platform host (see -Dhost)");
    for (selectHosts(b, host_names)) |h| host_step.dependOn(addHost(b, h, features, zig_cc_install));
    b.getInstallStep().dependOn(host_step);

    const bundler = b.addExecutable(.{
        .name = "bundle",
        .root_module = b.createModule(.{ .root_source_file = b.path("tools/bundle.zig"), .target = b.graph.host, .optimize = .ReleaseSafe }),
    });
    const bundle = b.addRunArtifact(bundler);
    bundle.setCwd(b.path("."));
    bundle.has_side_effects = true;
    if (b.args) |args| bundle.addArgs(args);
    b.step("bundle", "Package the platform with `roc bundle` (args after --)").dependOn(&bundle.step);
}

fn nativeHost(b: *std.Build) ?Host {
    const t = b.graph.host.result;
    for (hosts) |h| if (h.os == t.os.tag and h.arch == t.cpu.arch) return h;
    return null;
}

fn selectHosts(b: *std.Build, names: []const u8) []const Host {
    var list: std.ArrayList(Host) = .empty;
    if (std.mem.eql(u8, names, "none")) return &.{};
    if (std.mem.eql(u8, names, "native")) {
        const h = nativeHost(b) orelse std.debug.panic("no host target for this machine; pass -Dhost=...", .{});
        list.append(b.allocator, h) catch @panic("OOM");
    } else if (std.mem.eql(u8, names, "all")) {
        // What this OS can cross-compile: both musl hosts from Linux, and
        // the musl and macOS hosts from macOS. Windows builds its own.
        const os = b.graph.host.result.os.tag;
        for (hosts) |h| {
            const ok = switch (os) {
                .linux => h.os == .linux,
                .macos => h.os == .linux or h.os == .macos,
                .windows => h.os == .windows,
                else => false,
            };
            if (ok) list.append(b.allocator, h) catch @panic("OOM");
        }
    } else {
        var it = std.mem.tokenizeScalar(u8, names, ',');
        next: while (it.next()) |name| {
            for (hosts) |h| if (std.mem.eql(u8, h.name, name)) {
                list.append(b.allocator, h) catch @panic("OOM");
                continue :next;
            };
            std.debug.panic("unknown host target '{s}'", .{name});
        }
    }
    return list.items;
}

/// cargo build, then the library copied into platform/targets/<name>/. The
/// musl hosts are also stripped of what linking does not need, which keeps
/// the platform bundle under roc's package size limit.
fn addHost(b: *std.Build, h: Host, features: []const u8, zig_cc: *std.Build.Step.InstallArtifact) *std.Build.Step {
    const native = if (nativeHost(b)) |n| std.mem.eql(u8, n.name, h.name) else false;
    if (h.os == .windows and b.graph.host.result.os.tag != .windows) std.debug.panic("the x64win host is built on Windows", .{});

    const rustup = b.addSystemCommand(&.{ "rustup", "target", "add", h.rust });
    rustup.has_side_effects = true;

    // A native macOS host builds without --target, like any cargo build.
    const cross = !(native and h.os == .macos);
    const cargo = b.addSystemCommand(&.{ "cargo", "build", "--locked", "--release", "--lib" });
    if (cross) cargo.addArgs(&.{ "--target", h.rust });
    if (features.len > 0) cargo.addArgs(&.{ "--features", features });
    cargo.setCwd(b.path("."));
    cargo.has_side_effects = true;
    cargo.step.dependOn(&rustup.step);
    if (h.zig) |zig_triple| {
        const key = b.dupe(h.rust);
        std.mem.replaceScalar(u8, key, '-', '_');
        cargo.setEnvironmentVariable("ZIG_CC_TARGET", zig_triple);
        cargo.setEnvironmentVariable("ZIG_EXE", b.graph.zig_exe);
        cargo.setEnvironmentVariable(b.fmt("CC_{s}", .{key}), b.getInstallPath(zig_cc.dest_dir.?, zig_cc.dest_sub_path));
        cargo.setEnvironmentVariable(b.fmt("AR_{s}", .{key}), b.fmt("{s} ar", .{b.graph.zig_exe}));
        cargo.setEnvironmentVariable(b.fmt("CFLAGS_{s}", .{key}), "-Wno-error");
        cargo.step.dependOn(&zig_cc.step);
    }

    const out_dir = if (cross) b.fmt("target/{s}/release", .{h.rust}) else "target/release";
    const lib = if (h.os == .windows) "host.lib" else "libhost.a";
    const source = b.pathFromRoot(b.fmt("{s}/{s}", .{ out_dir, lib }));
    const dest_rel = b.fmt("platform/targets/{s}/{s}", .{ h.name, lib });

    if (h.os == .linux) {
        // Copy and strip in one: llvm-strip -o writes the stripped copy.
        const strip = b.addSystemCommand(&.{ llvmStrip(b), "--strip-unneeded", "-o", b.pathFromRoot(dest_rel), source });
        strip.has_side_effects = true;
        strip.step.dependOn(&cargo.step);
        return &strip.step;
    }
    const copy = b.addUpdateSourceFiles();
    copy.addCopyFileToSource(.{ .cwd_relative = source }, dest_rel);
    copy.step.dependOn(&cargo.step);
    if (h.os == .windows) {
        const sdk = windowsSdkLibDir(b);
        for (windows_system_libraries) |name| {
            copy.addCopyFileToSource(.{ .cwd_relative = b.pathJoin(&.{ sdk, name }) }, b.fmt("platform/targets/{s}/{s}", .{ h.name, name }));
        }
    }
    return &copy.step;
}

/// llvm-strip from PATH, else the one rustup's llvm-tools-preview installs.
fn llvmStrip(b: *std.Build) []const u8 {
    if (b.findProgram(&.{"llvm-strip"}, &.{})) |path| return path else |_| {}
    const sysroot = std.mem.trim(u8, b.run(&.{ "rustc", "--print", "sysroot" }), " \r\n");
    const info = b.run(&.{ "rustc", "-vV" });
    var lines = std.mem.tokenizeScalar(u8, info, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "host: ")) {
            const triple = std.mem.trim(u8, line["host: ".len..], " \r");
            return b.pathJoin(&.{ sysroot, "lib", "rustlib", triple, "bin", "llvm-strip" });
        }
    }
    std.debug.panic("llvm-strip not found: rustup component add llvm-tools-preview", .{});
}

/// The newest Windows 10/11 SDK's x64 library directory.
fn windowsSdkLibDir(b: *std.Build) []const u8 {
    const io = b.graph.io;
    const program_files = b.graph.environ_map.get("ProgramFiles(x86)") orelse std.debug.panic("ProgramFiles(x86) is not set; cannot find the Windows SDK", .{});
    const root = b.pathJoin(&.{ program_files, "Windows Kits", "10", "Lib" });
    var dir = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true }) catch std.debug.panic("no Windows SDK at {s}", .{root});
    defer dir.close(io);
    var best: ?[]const u8 = null;
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .directory) continue;
        const candidate = b.pathJoin(&.{ root, entry.name, "um", "x64" });
        std.Io.Dir.cwd().access(io, b.pathJoin(&.{ candidate, "ws2_32.lib" }), .{}) catch continue;
        if (best == null or std.mem.order(u8, candidate, best.?) == .gt) best = candidate;
    }
    return best orelse std.debug.panic("no x64 Windows SDK libraries under {s}", .{root});
}
