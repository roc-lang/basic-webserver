//! Packages the platform for release, in place of scripts/bundle.py: checks
//! that every target's link inputs are built, generates
//! RUST_DEPENDENCY_LICENSES.md from `cargo metadata`, checks roc's package
//! size limit, and runs `roc bundle`, which writes the .tar.zst.
//!
//!     zig build bundle -- [--output-dir DIR] [--target T ...] [--roc ROC] [roc bundle args]
//!
//! Run from the repository root (`zig build bundle` does).

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const max_platform_bytes = 100 * 1024 * 1024;

const Target = struct { name: []const u8, rust: []const u8, inputs: []const []const u8 };

/// Must match the `targets` block of platform/main.roc, which is checked.
const targets = [_]Target{
    .{ .name = "x64mac", .rust = "x86_64-apple-darwin", .inputs = &.{"libhost.a"} },
    .{ .name = "arm64mac", .rust = "aarch64-apple-darwin", .inputs = &.{"libhost.a"} },
    .{ .name = "x64musl", .rust = "x86_64-unknown-linux-musl", .inputs = &.{ "crt1.o", "libhost.a", "libunwind.a", "libc.a" } },
    .{ .name = "arm64musl", .rust = "aarch64-unknown-linux-musl", .inputs = &.{ "crt1.o", "libhost.a", "libunwind.a", "libc.a" } },
    .{ .name = "x64win", .rust = "x86_64-pc-windows-msvc", .inputs = &.{ "host.lib", "ws2_32.lib", "bcrypt.lib", "advapi32.lib" } },
};

const library_extensions = [_][]const u8{ ".a", ".o", ".lib", ".obj" };
const mac_link_support = "targets/macos-sysroot/usr/lib/libSystem.tbd";

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    const cwd = Io.Dir.cwd();
    const args = try init.minimal.args.toSlice(arena);

    var output_dir: []const u8 = ".";
    var roc: []const u8 = "roc";
    var selected: std.ArrayList(Target) = .empty;
    var roc_args: std.ArrayList([]const u8) = .empty;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--output-dir") and i + 1 < args.len) {
            i += 1;
            output_dir = args[i];
        } else if (std.mem.eql(u8, arg, "--roc") and i + 1 < args.len) {
            i += 1;
            roc = args[i];
        } else if (std.mem.eql(u8, arg, "--target") and i + 1 < args.len) {
            i += 1;
            try selected.append(arena, targetNamed(args[i]) orelse return fail("unknown target {s}", .{args[i]}));
        } else {
            try roc_args.append(arena, arg);
        }
    }
    if (selected.items.len == 0) try selected.appendSlice(arena, &targets);

    try cwd.createDirPath(io, output_dir);
    const output_abs = try cwd.realPathFileAlloc(io, output_dir, arena);
    var platform = try cwd.openDir(io, "platform", .{ .iterate = true });
    defer platform.close(io);

    if (!try manifestMatches(arena, io, platform)) return fail("Release target manifest is out of sync with platform/main.roc", .{});

    // Every .roc file of the platform, then every target's link inputs.
    var roc_files: std.ArrayList([]const u8) = .empty;
    var it = platform.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".roc")) try roc_files.append(arena, try arena.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, roc_files.items, {}, lessThan);

    var link_inputs: std.ArrayList([]const u8) = .empty;
    var mac = false;
    for (selected.items) |t| {
        for (t.inputs) |name| {
            const path = try std.fmt.allocPrint(arena, "targets/{s}/{s}", .{ t.name, name });
            if (!hasLibraryExtension(name)) return fail("Unexpected target input extension: {s}", .{path});
            try link_inputs.append(arena, path);
        }
        if (std.mem.endsWith(u8, t.name, "mac")) mac = true;
    }
    if (mac) try link_inputs.append(arena, mac_link_support);
    var missing = false;
    for (link_inputs.items) |path| platform.access(io, path, .{}) catch {
        if (!missing) std.debug.print("Missing release target inputs; build all Unix targets and the Windows host before bundling:\n", .{});
        std.debug.print("  {s}\n", .{path});
        missing = true;
    };
    if (missing) return 1;

    try writeRustLicenses(arena, io, platform, selected.items);
    defer platform.deleteFile(io, "RUST_DEPENDENCY_LICENSES.md") catch {};

    var size: u64 = 0;
    for (roc_files.items) |p| size += (try platform.statFile(io, p, .{})).size;
    for (link_inputs.items) |p| size += (try platform.statFile(io, p, .{})).size;
    size += (try cwd.statFile(io, "THIRD_PARTY_LICENSES.md", .{})).size;
    size += (try platform.statFile(io, "RUST_DEPENDENCY_LICENSES.md", .{})).size;
    if (size > max_platform_bytes) {
        return fail("Platform inputs exceed Roc's default 100 MiB transitive dependency limit: {d} bytes. Rebuild Linux hosts with `zig build -Dhost=all` so their archives are stripped.", .{size});
    }

    std.debug.print("Bundling {d} .roc files and {d} link input files...\n\nFiles to bundle:\n", .{ roc_files.items.len, link_inputs.items.len });
    for (roc_files.items) |p| std.debug.print("  {s}\n", .{p});
    for (link_inputs.items) |p| std.debug.print("  {s}\n", .{p});
    std.debug.print("  THIRD_PARTY_LICENSES.md\n  RUST_DEPENDENCY_LICENSES.md\n\nUnpacked platform size: {d} bytes\n\n", .{size});

    try Io.Dir.copyFile(cwd, "THIRD_PARTY_LICENSES.md", platform, "THIRD_PARTY_LICENSES.md", io, .{});
    defer platform.deleteFile(io, "THIRD_PARTY_LICENSES.md") catch {};

    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ roc, "bundle" });
    try argv.appendSlice(arena, roc_files.items);
    try argv.appendSlice(arena, link_inputs.items);
    try argv.appendSlice(arena, &.{ "THIRD_PARTY_LICENSES.md", "RUST_DEPENDENCY_LICENSES.md", "--output-dir", output_abs });
    try argv.appendSlice(arena, roc_args.items);
    var child = try std.process.spawn(io, .{ .argv = argv.items, .cwd = .{ .path = "platform" } });
    return switch (try child.wait(io)) {
        .exited => |code| code,
        else => 1,
    };
}

fn fail(comptime fmt: []const u8, args: anytype) u8 {
    std.debug.print(fmt ++ "\n", args);
    return 1;
}

fn targetNamed(name: []const u8) ?Target {
    for (targets) |t| if (std.mem.eql(u8, t.name, name)) return t;
    return null;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn hasLibraryExtension(name: []const u8) bool {
    for (library_extensions) |ext| if (std.mem.endsWith(u8, name, ext)) return true;
    return false;
}

/// The lines `name: { inputs: ["a", "b"] },` of platform/main.roc must list
/// exactly the targets and inputs above, in order.
fn manifestMatches(arena: Allocator, io: Io, platform: Io.Dir) !bool {
    const source = try platform.readFileAlloc(io, "main.roc", arena, .unlimited);
    var found: usize = 0;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        const colon = std.mem.indexOf(u8, line, ": { inputs: [") orelse continue;
        const name = line[0..colon];
        const rest = line[colon + ": { inputs: [".len ..];
        const close = std.mem.indexOf(u8, rest, "]") orelse continue;
        var inputs: std.ArrayList([]const u8) = .empty;
        var parts = std.mem.splitScalar(u8, rest[0..close], '"');
        var odd = false;
        while (parts.next()) |part| : (odd = !odd) if (odd) try inputs.append(arena, part);
        const t = targetNamed(name) orelse return false;
        if (t.inputs.len != inputs.items.len) return false;
        for (t.inputs, inputs.items) |a, b| if (!std.mem.eql(u8, a, b)) return false;
        found += 1;
    }
    return found == targets.len;
}

const Package = struct {
    id: []const u8,
    name: []const u8,
    version: []const u8,
    root: []const u8,
    license_file: ?[]const u8,
    repository: ?[]const u8,
    license: ?[]const u8,
    paths: []const []const u8 = &.{},
};

fn str(value: std.json.Value, key: []const u8) ?[]const u8 {
    const v = value.object.get(key) orelse return null;
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

/// The third-party Rust crates the host links, each with its license text,
/// from `cargo metadata` for the selected targets.
fn writeRustLicenses(arena: Allocator, io: Io, platform: Io.Dir, selected: []const Target) !void {
    var by_id: std.StringArrayHashMapUnmanaged(Package) = .empty;
    for (selected) |t| {
        const result = try std.process.run(arena, io, .{ .argv = &.{ "cargo", "metadata", "--locked", "--format-version", "1", "--filter-platform", t.rust } });
        if (result.term != .exited or result.term.exited != 0) return error.CargoMetadataFailed;
        const metadata = try std.json.parseFromSliceLeaky(std.json.Value, arena, result.stdout, .{});
        var reachable: std.StringHashMapUnmanaged(void) = .empty;
        for (metadata.object.get("resolve").?.object.get("nodes").?.array.items) |node| try reachable.put(arena, str(node, "id").?, {});
        for (metadata.object.get("packages").?.array.items) |p| {
            const id = str(p, "id").?;
            if (!reachable.contains(id) or !std.mem.startsWith(u8, str(p, "source") orelse "", "registry+")) continue;
            try by_id.put(arena, id, .{
                .id = id,
                .name = str(p, "name").?,
                .version = str(p, "version").?,
                .root = std.fs.path.dirname(str(p, "manifest_path").?).?,
                .license_file = str(p, "license_file"),
                .repository = str(p, "repository"),
                .license = str(p, "license"),
            });
        }
    }
    const packages = by_id.values();
    std.mem.sort(Package, packages, {}, struct {
        fn lt(_: void, a: Package, b: Package) bool {
            return switch (std.mem.order(u8, a.name, b.name)) {
                .lt => true,
                .gt => false,
                .eq => std.mem.order(u8, a.version, b.version) == .lt,
            };
        }
    }.lt);

    // A crate's license files: its declared `license_file`, then any file
    // named LICENSE*, COPYING*, NOTICE* or UNLICENSE*, resolved and deduped.
    for (packages) |*p| {
        var candidates: std.ArrayList([]const u8) = .empty;
        if (p.license_file) |f| try candidates.append(arena, try std.fs.path.join(arena, &.{ p.root, f }));
        var listed: std.ArrayList([]const u8) = .empty;
        var dir = try Io.Dir.cwd().openDir(io, p.root, .{ .iterate = true });
        defer dir.close(io);
        var it = dir.iterate();
        while (try it.next(io)) |entry| {
            const lower = try std.ascii.allocLowerString(arena, entry.name);
            for ([_][]const u8{ "license", "copying", "notice", "unlicense" }) |prefix| {
                if (std.mem.startsWith(u8, lower, prefix)) {
                    try listed.append(arena, try std.fs.path.join(arena, &.{ p.root, entry.name }));
                    break;
                }
            }
        }
        std.mem.sort([]const u8, listed.items, {}, lessThan);
        try candidates.appendSlice(arena, listed.items);
        var paths: std.ArrayList([]const u8) = .empty;
        for (candidates.items) |c| {
            const resolved = Io.Dir.cwd().realPathFileAlloc(io, c, arena) catch continue;
            const stat = Io.Dir.cwd().statFile(io, resolved, .{}) catch continue;
            if (stat.kind != .file) continue;
            for (paths.items) |seen| {
                if (std.mem.eql(u8, seen, resolved)) break;
            } else try paths.append(arena, resolved);
        }
        p.paths = paths.items;
    }

    var out: std.ArrayList(u8) = .empty;
    const w = struct {
        fn line(list: *std.ArrayList(u8), a: Allocator, text: []const u8) !void {
            if (list.items.len > 0) try list.append(a, '\n');
            try list.appendSlice(a, text);
        }
    };
    for ([_][]const u8{ "# Rust Dependency Licenses", "", "This file is generated from the exact dependencies in `Cargo.lock`.", "" }) |l| try w.line(&out, arena, l);
    for (packages) |p| {
        var source = p;
        if (p.paths.len == 0) {
            // Crates of one repository often ship the license once: borrow it
            // from another crate there with the same SPDX expression.
            for (packages) |c| {
                if (std.mem.eql(u8, c.id, p.id) or p.repository == null or c.repository == null or p.license == null or c.license == null) continue;
                if (std.mem.eql(u8, c.repository.?, p.repository.?) and std.mem.eql(u8, c.license.?, p.license.?) and c.paths.len > 0) {
                    source = c;
                    break;
                }
            }
        }
        if (source.paths.len == 0) {
            std.debug.print("No license text found for Rust dependency {s} {s}\n", .{ p.name, p.version });
            return error.MissingLicense;
        }
        try w.line(&out, arena, try std.fmt.allocPrint(arena, "## {s} {s}", .{ p.name, p.version }));
        try w.line(&out, arena, "");
        try w.line(&out, arena, try std.fmt.allocPrint(arena, "SPDX expression: `{s}`", .{p.license orelse "see included license"}));
        try w.line(&out, arena, "");
        if (p.repository) |r| {
            try w.line(&out, arena, try std.fmt.allocPrint(arena, "Source: {s}", .{r}));
            try w.line(&out, arena, "");
        }
        if (!std.mem.eql(u8, source.id, p.id)) {
            try w.line(&out, arena, try std.fmt.allocPrint(arena, "License text supplied by `{s} {s}` from the same upstream repository and SPDX license.", .{ source.name, source.version }));
            try w.line(&out, arena, "");
        }
        for (source.paths) |path| {
            // Line endings as Python's text mode reads them (\r\n and \r are \n),
            // so the file matches the one scripts/bundle.py wrote.
            const raw = try Io.Dir.cwd().readFileAlloc(io, path, arena, .unlimited);
            const text = try std.mem.replaceOwned(u8, arena, try std.mem.replaceOwned(u8, arena, raw, "\r\n", "\n"), "\r", "\n");
            try w.line(&out, arena, try std.fmt.allocPrint(arena, "### {s}", .{std.fs.path.basename(path)}));
            try w.line(&out, arena, "");
            try w.line(&out, arena, "```text");
            try w.line(&out, arena, std.mem.trimEnd(u8, text, " \t\r\n\x0b\x0c"));
            try w.line(&out, arena, "```");
            try w.line(&out, arena, "");
        }
    }
    try platform.writeFile(io, .{ .sub_path = "RUST_DEPENDENCY_LICENSES.md", .data = out.items });
}
