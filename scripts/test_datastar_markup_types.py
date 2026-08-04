#!/usr/bin/env python3
"""Check that the typed Datastar markup API rejects invalid programs."""

from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "target" / "datastar-markup-type-tests"
HTTP_PACKAGE = (
    "https://github.com/roc-lang/http/releases/download/1.0.0/"
    "6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst"
)


CASES: tuple[tuple[str, str, tuple[str, ...]], ...] = (
    (
        "toggle-string-signal",
        'probe = DatastarMarkup.Signal.str("name").toggle()',
        ("TYPE MISMATCH", "Signal(Str)", "toggle"),
    ),
    (
        "update-bool-with-string",
        'probe = DatastarMarkup.Signal.bool("enabled").update("yes")',
        ("TYPE MISMATCH", "string literal", "Bool"),
    ),
    (
        "disable-with-string-expression",
        'probe = DatastarMarkup.Expr.str("enabled").disabled_when_true()',
        ("TYPE MISMATCH", "Expr(Str)", "disabled_when_true"),
    ),
    (
        "bind-bool-to-text-input",
        'probe = DatastarMarkup.Signal.bool("enabled").text_input([])',
        ("TYPE MISMATCH", "Signal(Bool)", "Signal(Str)", "text_input"),
    ),
    (
        "compare-different-expression-types",
        'probe = DatastarMarkup.Expr.str("one").equals(DatastarMarkup.Expr.bool(Bool.True))',
        ("TYPE MISMATCH", "Expr(Str)", "Expr(Bool)"),
    ),
    (
        "invalid-literal-route",
        'probe = DatastarMarkup.RequestTarget.get("relative/path")',
        ("INVALID STRING", "absolute application paths"),
    ),
    (
        "dynamic-unparsed-route",
        '\n'.join(
            (
                'dynamic_path : Str',
                'dynamic_path = "/examples/load"',
                'probe = DatastarMarkup.RequestTarget.get(dynamic_path)',
            )
        ),
        ("TYPE MISMATCH", "RoutePath", "Str"),
    ),
    (
        "invalid-literal-signal-name",
        'probe = DatastarMarkup.Signal.bool("not-valid")',
        ("INVALID STRING", "signal names must start"),
    ),
    (
        "invalid-literal-selector",
        'probe = DatastarMarkup.PatchTarget.css("")',
        ("INVALID STRING", "selectors must be non-empty"),
    ),
    (
        "invalid-literal-element-id",
        '\n'.join(
            (
                'probe : ElementId',
                'probe = "9 agents"',
            )
        ),
        ("INVALID STRING", "element IDs must start"),
    ),
    (
        "opaque-element-id-constructor",
        'probe = ElementId.("agents")',
        ("OPAQUE", "ElementId"),
    ),
)


def source_for(probe: str) -> str:
    return f'''app [Context, program] {{
    pf: platform "../../platform/main.roc",
    http: "{HTTP_PACKAGE}",
}}

import pf.DatastarMarkup
import pf.ElementId
import pf.Server
import http.Response

Context : {{}}

{probe}

program = {{ init!, respond!, shutdown! }}

init! = || {{
    _ = Str.inspect(probe)
    Ok({{ config: Server.default_config, context: {{}} }})
}}

respond! = |_request, _context| Ok(Server.respond(Response.from_status(204)))

shutdown! = |_reason, _context| Ok({{}})
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--roc", default="roc")
    args = parser.parse_args()

    if FIXTURE_DIR.exists():
        shutil.rmtree(FIXTURE_DIR)
    FIXTURE_DIR.mkdir(parents=True)

    failures: list[str] = []
    for name, probe, expected in CASES:
        source = FIXTURE_DIR / f"{name}.roc"
        source.write_text(source_for(probe), encoding="utf-8", newline="\n")
        command = [args.roc, "check", str(source)]
        print("+ !", " ".join(command), flush=True)
        result = subprocess.run(
            command,
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        output = result.stdout
        if result.returncode == 0:
            failures.append(f"{name}: unexpectedly compiled")
            continue
        missing = [needle for needle in expected if needle not in output]
        if missing:
            failures.append(
                f"{name}: missing diagnostics {missing!r}\n--- compiler output ---\n{output}"
            )

    if failures:
        raise SystemExit("\n\n".join(failures))

    print(f"All {len(CASES)} Datastar markup compile-failure cases passed.")


if __name__ == "__main__":
    main()
