"""Manifest rejection tests, plus executable ABI checks on Windows."""
from __future__ import annotations

import json
import os
import re
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import build, bundle, windows_runtime as runtime


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name)
        for name in (*runtime.LIBRARIES, "host.lib"):
            (self.output / name).write_bytes(name.encode())
        license_file = runtime.notice(self.output, "license.txt", b"original license")
        components = {"fixture": {
            "license": "MIT", "license_files": [license_file],
            "redistribution_basis": "fixture", "sources": [{"sha256": "fixture"}],
            "build_commands": [["fixture"]],
        }}
        runtime.write_manifest(self.output, components,
                               {name: "fixture" for name in (*runtime.LIBRARIES, "host.lib")})

    def test_complete_inventory_returns_notices(self):
        self.assertEqual(len(runtime.validate(self.output)), 2)

    def test_consumers_import_without_python_311_tomllib(self):
        script = '''import builtins
original_import = builtins.__import__
def without_tomllib(name, *args, **kwargs):
    if name == "tomllib":
        raise ModuleNotFoundError("Python 3.10 has no tomllib")
    return original_import(name, *args, **kwargs)
builtins.__import__ = without_tomllib
from scripts import build, bundle
assert "x64win" in build.ROC_TARGETS
'''
        subprocess.run([sys.executable, "-c", script], cwd=runtime.ROOT, check=True)

    def test_tampered_library_rejected(self):
        (self.output / "host.lib").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "library hash mismatch"):
            runtime.validate(self.output)

    def test_tampered_notice_rejected(self):
        (self.output / "licenses/license.txt").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "license hash mismatch"):
            runtime.validate(self.output)

    def test_missing_and_empty_inputs_rejected(self):
        (self.output / runtime.LIBRARIES[0]).write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "inventory mismatch"):
            runtime.validate(self.output)

    def test_unexpected_sdk_archive_rejected(self):
        (self.output / "libcmt.lib").write_bytes(b"unapproved")
        with self.assertRaisesRegex(ValueError, "inventory mismatch"):
            runtime.validate(self.output)

    def test_unrecorded_binary_inputs_rejected_recursively(self):
        for relative in ("startup.obj", "startup.o", "extra.a", "EXTRA.LIB",
                         "nested/startup.OBJ", "licenses/extra.a"):
            for contents in (b"", b"unrecorded"):
                with self.subTest(relative=relative, contents=contents):
                    path = self.output / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(contents)
                    with self.assertRaisesRegex(ValueError, "inventory mismatch"):
                        runtime.validate(self.output)
                    path.unlink()

    def test_selected_zig_is_resolved_and_version_checked(self):
        with patch.dict(os.environ, {"ZIG": "selected-zig"}), \
             patch.object(runtime.shutil, "which", return_value=str(self.output / "zig")) as which, \
             patch.object(runtime.subprocess, "check_output", return_value=runtime.ZIG_VERSION) as output:
            zig = runtime.resolve_zig()
            which.assert_called_once_with("selected-zig")
            output.assert_called_once_with([zig, "version"], text=True)
        with patch.object(runtime.shutil, "which", return_value="zig"), \
             patch.object(runtime.subprocess, "check_output", return_value="0.16.0"), \
             patch.object(build, "run") as cargo:
            with self.assertRaisesRegex(SystemExit, "require Zig"):
                build.windows_build_env()
            cargo.assert_not_called()

    def test_runtime_commands_use_selected_zig_without_path_lookup(self):
        zig = runtime.resolve_zig()
        # Only ZIG supplies the compiler; no bare zig can be found on PATH.
        with patch.dict(os.environ, {"ZIG": zig, "PATH": ""}):
            self.assertEqual(runtime.resolve_zig(), zig)
            self.assertTrue(runtime.zig_lib_dir(zig).is_dir())

    def test_license_path_escape_rejected(self):
        path = self.output / runtime.MANIFEST_NAME
        manifest = json.loads(path.read_text())
        manifest["components"]["fixture"]["license_files"] = ["../outside.txt"]
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "invalid Windows license"):
            runtime.validate(self.output)

    def test_missing_rights_evidence_rejected(self):
        path = self.output / runtime.MANIFEST_NAME
        manifest = json.loads(path.read_text())
        del manifest["components"]["fixture"]["redistribution_basis"]
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "redistribution_basis"):
            runtime.validate(self.output)

    def test_combined_archive_still_requires_each_components_rights(self):
        path = self.output / runtime.MANIFEST_NAME
        manifest = json.loads(path.read_text())
        manifest["components"]["child"] = dict(manifest["components"]["fixture"])
        manifest["components"]["fixture"]["subcomponents"] = ["child"]
        del manifest["components"]["child"]["redistribution_basis"]
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "redistribution_basis.*child"):
            runtime.validate(self.output)

    def test_stdcall_normalization_preserves_ordinals(self):
        definition = runtime.normalize_definition("EXPORTS\n Foo@8 @123\n Bar @4 DATA\n")
        self.assertIn("Foo @123", definition)
        self.assertIn("Bar @4 DATA", definition)

    def test_zig_adapter_translates_rust_target_and_preserves_argument_boundaries(self):
        adapter = runpy.run_path(str(runtime.ROOT / "scripts/zig_cc.py"))
        args = adapter["compiler_args"]("x86_64-windows-msvc", [
            "--target=x86_64-pc-windows-msvc", "-target", "x86_64-pc-windows-msvc",
            "-I", "directory with spaces", "-O2"])
        self.assertEqual(args, ["cc", "-target", "x86_64-windows-msvc", "-fms-runtime-lib=dll", "-g0",
                                "-I", "directory with spaces", "-O2"])
        args = adapter["compiler_args"]("x86_64-linux-musl", ["--target=x86_64-unknown-linux-musl", "-O2"])
        self.assertEqual(args, ["cc", "-target", "x86_64-linux-musl", "-g0", "-O2"])
        args = adapter["compiler_args"]("x86_64-linux-musl", ["-gdwarf-4", "-O2"])
        self.assertEqual(args, ["cc", "-target", "x86_64-linux-musl", "-gdwarf-4", "-O2"])

    def test_inherited_rust_flags_preserved_and_dynamic_crt_selected(self):
        with patch.dict(os.environ, {"CARGO_ENCODED_RUSTFLAGS": "-Ctarget-feature=+crt-static\x1f-Cdebuginfo=1"}), \
             patch.object(runtime, "resolve_zig", return_value="zig"), \
             patch.object(build, "windows_compiler", return_value="adapter.cmd"):
            env, _ = build.windows_build_env()
        self.assertEqual(env["CARGO_ENCODED_RUSTFLAGS"].split("\x1f"),
                         ["-Ctarget-feature=+crt-static", "-Cdebuginfo=1", "-Ctarget-feature=-crt-static"])
        self.assertEqual(env["ZIG_CC_TARGET"], "x86_64-windows-msvc")

    def test_bundle_transfers_every_hashed_notice(self):
        root = self.output / "repo"
        platform = root / "platform"
        windows = platform / "targets/x64win"
        windows.parent.mkdir(parents=True)
        shutil.copytree(self.output / "licenses", windows / "licenses")
        for name in (*runtime.LIBRARIES, "host.lib", runtime.MANIFEST_NAME):
            shutil.copy2(self.output / name, windows / name)
        (root / "THIRD_PARTY_LICENSES.md").write_text("root notices")
        argv = ["bundle.py", "--target", "x64win", "--output-dir", str(root / "dist")]

        def run_bundle():
            with patch.object(bundle, "ROOT", root), patch.object(bundle, "PLATFORM_DIR", platform), \
                 patch.object(bundle, "validate_target_manifest"), \
                 patch.object(bundle, "generate_rust_dependency_licenses",
                              side_effect=lambda output, _targets: output.write_text("rust")), \
                 patch.object(sys, "argv", argv), \
                 patch.object(bundle.subprocess, "run") as run:
                try:
                    bundle.main()
                finally:
                    self.assertFalse((platform / "THIRD_PARTY_LICENSES.md").exists())
                    self.assertFalse((platform / "RUST_DEPENDENCY_LICENSES.md").exists())
                return run

        arguments = run_bundle().call_args.args[0]
        self.assertIn("targets/x64win/licenses/license.txt", arguments)
        self.assertIn("targets/x64win/PROVENANCE.json", arguments)
        self.assertIn("targets/x64win/windows_support.lib", arguments)
        self.assertIn("THIRD_PARTY_LICENSES.md", arguments)
        (windows / "licenses/unrecorded.OBJ").write_bytes(b"unrecorded")
        with self.assertRaisesRegex(ValueError, "inventory mismatch"):
            run_bundle()

    def test_declared_windows_inputs_match_producer_inventory(self):
        bundle.validate_target_manifest()
        self.assertEqual(set(bundle.TARGET_INPUTS["x64win"]), set(runtime.LIBRARIES) | {"host.lib"})


class BuiltinShadowTests(unittest.TestCase):
    def test_host_builtins_shadow_weak_compiler_rt_duplicates(self):
        zig = runtime.resolve_zig()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)

            def archive(name: str, source: str) -> Path:
                (root / f"{name}.zig").write_text(source)
                subprocess.run([zig, "build-obj", str(root / f"{name}.zig"), "-target", "x86_64-windows-msvc",
                                "-O", "ReleaseFast", f"-femit-bin={root / name}.obj"], check=True)
                subprocess.run([zig, "ar", "rcs", str(root / f"{name}.lib"), str(root / f"{name}.obj")],
                               check=True)
                return root / f"{name}.lib"

            # Both sides export the builtin weakly, as Rust's compiler-builtins
            # and Zig's compiler-rt do, and each is loaded for another symbol.
            exports = '''fn floattidf(a: i128) callconv(.c) f64 {{ return @floatFromInt(a); }}
fn other() callconv(.c) i32 {{ return {value}; }}
comptime {{
    @export(&floattidf, .{{ .name = "__floattidf", .linkage = .weak }});
    @export(&other, .{{ .name = "{other}" }});
}}
'''
            host = archive("host", exports.format(value=1, other="host_only"))
            compiler_rt = archive("compiler_rt", exports.format(value=2, other="rt_only"))
            (root / "app.zig").write_text('''extern fn __floattidf(i128) callconv(.c) f64;
extern fn host_only() callconv(.c) i32;
extern fn rt_only() callconv(.c) i32;
export var _fltused: c_int = 0;
export fn mainCRTStartup() callconv(.c) i32 {
    var value: i128 = 3;
    _ = &value;
    return @as(i32, @intFromFloat(__floattidf(value))) + host_only() + rt_only();
}
''')
            subprocess.run([zig, "build-obj", str(root / "app.zig"), "-target", "x86_64-windows-msvc",
                            "-O", "ReleaseFast", f"-femit-bin={root / 'app.obj'}"], check=True)
            link = [zig, "lld-link", "/nodefaultlib", "/subsystem:console", "/entry:mainCRTStartup",
                    "/machine:x64", f"/out:{root / 'app.exe'}", str(root / "app.obj"),
                    str(host), str(compiler_rt)]
            duplicate = subprocess.run(link, capture_output=True, text=True)
            self.assertIn("duplicate symbol: __floattidf", duplicate.stdout + duplicate.stderr)

            shadowed = runtime.shadow_host_builtins(compiler_rt, host, root)
            self.assertEqual(shadowed["renamed_symbols"], ["__floattidf"])
            subprocess.run(link, check=True)


class CompilerCacheTests(unittest.TestCase):
    def test_cargo_rebuilds_when_compiler_or_adapter_changes(self):
        zig = runtime.resolve_zig()
        cc_version = re.search(r'name = "cc"\nversion = "([^"]+)"',
                               (runtime.ROOT / "Cargo.lock").read_text())[1]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "scripts").mkdir()
            (root / "src").mkdir()
            (root / "Cargo.toml").write_text(
                '[package]\nname="compiler_cache_regression"\nversion="0.1.0"\nedition="2021"\n'
                f'[build-dependencies]\ncc="={cc_version}"\n')
            (root / "build.rs").write_text(
                'fn main() { cc::Build::new().file("sentinel.c").compile("sentinel"); }\n')
            (root / "sentinel.c").write_text('int sentinel(void) { return VALUE; }\n')
            (root / "src/main.rs").write_text(
                'extern "C" { fn sentinel() -> i32; }\n'
                'fn main() { assert_eq!(unsafe { sentinel() }, '
                'std::env::args().nth(1).unwrap().parse::<i32>().unwrap()); }\n')
            # Hidden compiler state and mutable wrapper contents are the two
            # inputs cc-rs does not track for a fixed-path adapter.
            selected = root / "selected-compiler"
            selected.write_text("1")
            adapter = root / "scripts/zig_cc.py"
            adapter.write_text(
                'import os, pathlib, subprocess, sys\n'
                'value = pathlib.Path(os.environ["ZIG"]).read_text().strip()\n'
                'args = [a for a in sys.argv[1:] if not a.startswith("--target=")]\n'
                f'raise SystemExit(subprocess.call([{zig!r}, "cc", *{(["-target", "x86_64-windows-msvc", "-fms-runtime-lib=dll"] if os.name == "nt" else [])!r}, "-DVALUE=" + value, *args]))\n')
            launcher = root / "scripts/zig_cc.cmd"
            if os.name == "nt":
                launcher.write_text('@echo off\npython "%~dp0zig_cc.py" %*\n')
            else:
                launcher.write_text('#!/bin/sh\nexec ' + sys.executable
                                    + ' "$(dirname "$0")/zig_cc.py" "$@"\n')
                launcher.chmod(0o755)
            env = os.environ.copy()
            env.pop("RUSTFLAGS", None)
            env.pop("CARGO_ENCODED_RUSTFLAGS", None)
            env["CARGO_TARGET_DIR"] = str(root / "target")
            env["ZIG"] = str(selected)
            for expected in (1, 2, 3):
                if expected == 2:
                    selected.write_text("2")
                elif expected == 3:
                    adapter.write_text(adapter.read_text().replace('value, *args', '"3", *args'))
                with patch.object(build, "ROOT", root):
                    env["CC"] = build.windows_compiler(str(selected))
                subprocess.run(["cargo", "run", "--quiet", "--", str(expected)],
                               cwd=root, env=env, check=True, timeout=180)
                # A repeat build keeps exactly the same compiler identity.
                with patch.object(build, "ROOT", root):
                    self.assertEqual(env["CC"], build.windows_compiler(str(selected)))


def link_windows_executable(zig: str, exe: Path, *inputs: Path) -> str:
    subprocess.run([zig, "lld-link", "/nodefaultlib", "/subsystem:console",
                    "/entry:mainCRTStartup", "/machine:x64", "/opt:ref", f"/out:{exe}",
                    *(str(path) for path in inputs)], check=True)
    readobj = build.find_llvm_strip().with_name("llvm-readobj.exe")
    return subprocess.check_output([str(readobj), "--coff-imports", str(exe)], text=True).lower()


@unittest.skipUnless(os.name == "nt", "native Windows ABI execution")
class WindowsRuntimeTests(unittest.TestCase):
    def test_tls_with_the_production_native_compiler_and_profile(self):
        env, _ = build.windows_build_env()
        subprocess.run([
            "cargo", "test", "--locked", "--release", "--lib", "--target", build.WINDOWS_TARGET,
            "http::tests::ring_tls_handshake_and_untrusted_certificate_rejection"],
            cwd=runtime.ROOT, env=env, check=True, timeout=600)

    def test_actual_host_links_without_sdk_or_vc_runtime_archives(self):
        inputs = runtime.ROOT / "platform/targets/x64win"
        runtime.validate(inputs)
        zig = runtime.resolve_zig()
        scratch = runtime.ROOT / "target/windows-host-fixture"
        scratch.mkdir(parents=True, exist_ok=True)
        source = scratch / "app.c"
        # Stub every Roc entrypoint from the glue. The host runs its startup,
        # then calls init first; exiting there proves that the host
        # initialized without calling into Roc code.
        glue = (runtime.ROOT / "src/roc_platform_abi.rs").read_text(encoding="utf-8")
        entrypoints = re.findall(r"/// Entrypoint: .*\n\s*pub fn (roc_\w+)\(", glue)
        self.assertIn("roc_init_for_host", entrypoints)
        source.write_text(
            "__declspec(dllimport) void __stdcall ExitProcess(unsigned int);\n"
            + "".join(f"void {name}(void) {{ ExitProcess({37 if name == 'roc_init_for_host' else 1}); }}\n"
                      for name in entrypoints))
        obj, exe = scratch / "app.obj", scratch / "app.exe"
        subprocess.run([zig, "cc", "-target", "x86_64-windows-msvc", "-c", str(source), "-o", str(obj)], check=True)
        imports = link_windows_executable(zig, exe, obj, inputs / "host.lib",
                                          *(inputs / name for name in runtime.LIBRARIES))
        self.assertNotIn("vcruntime", imports)
        self.assertNotIn("msvcp", imports)
        self.assertEqual(subprocess.run([str(exe)], timeout=20).returncode, 37)

    def test_startup_tls_initializers_cookie_and_metadata(self):
        inputs = runtime.ROOT / "platform/targets/x64win"
        runtime.validate(inputs)
        zig = runtime.resolve_zig()
        scratch = runtime.ROOT / "target/windows-runtime-fixture"
        scratch.mkdir(parents=True, exist_ok=True)
        for fail_initializer in (False, True):
            obj = scratch / "fixture.obj"
            exe = scratch / "fixture.exe"
            compile_args = [zig, "cc", "-target", "x86_64-windows-msvc", "-O2",
                            "-fstack-protector-strong", "-c",
                            str(runtime.SOURCE_DIR / "runtime_fixture.c"), "-o", str(obj)]
            if fail_initializer:
                compile_args.append("-DFAIL_INITIALIZER")
            subprocess.run(compile_args, check=True)
            imports = link_windows_executable(zig, exe, obj,
                                              *(inputs / name for name in runtime.LIBRARIES))
            self.assertNotIn("vcruntime", imports)
            self.assertNotIn("msvcp", imports)
            result = subprocess.run([str(exe), "a b"], timeout=20)
            self.assertEqual(result.returncode, 255 if fail_initializer else 37)
            if not fail_initializer:
                result = subprocess.run([str(exe), "fail"], timeout=20)
                self.assertEqual(result.returncode & 0xffffffff, 0xc0000409)


if __name__ == "__main__":
    unittest.main()
