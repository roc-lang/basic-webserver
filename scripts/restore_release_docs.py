#!/usr/bin/env python3
"""Rebuild a versioned documentation tree from published release archives.

Releases attach a `docs.tar.gz` asset containing the API documentation
generated for that version. GitHub Pages is assembled from those assets, so
generated documentation never has to be committed to this repository.

Requires the GitHub CLI (`gh`) on PATH and an authenticated token.
"""

from __future__ import annotations

import argparse
import html
import os
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path


DOCS_ASSET = "docs.tar.gz"


def run_gh(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["gh", *arguments],
        check=False,
        capture_output=True,
        text=True,
    )


def gh_output(arguments: list[str], description: str) -> str:
    result = run_gh(arguments)
    if result.returncode != 0:
        raise SystemExit(f"Failed to {description}: {result.stderr.strip()}")
    return result.stdout


def releases_with_docs(repository: str) -> list[str]:
    """Published releases that carry a documentation archive.

    Releases from before the archive was published, and prereleases whose
    assets were removed, are simply absent from the result.
    """

    output = gh_output(
        [
            "api",
            "--paginate",
            f"repos/{repository}/releases?per_page=100",
            "--jq",
            ".[]"
            " | select(.draft == false)"
            f' | select([.assets[].name] | index("{DOCS_ASSET}"))'
            " | .tag_name",
        ],
        "list releases",
    )
    return [line.strip() for line in output.splitlines() if line.strip()]


def latest_stable_release(repository: str) -> str | None:
    result = run_gh(["api", f"repos/{repository}/releases/latest", "--jq", ".tag_name"])
    if result.returncode != 0:
        return None
    tag_name = result.stdout.strip()
    return tag_name or None


def download_docs_asset(repository: str, release: str, destination: Path) -> Path:
    destination.mkdir(parents=True, exist_ok=True)
    gh_output(
        [
            "release",
            "download",
            release,
            "--repo",
            repository,
            "--pattern",
            DOCS_ASSET,
            "--dir",
            str(destination),
            "--clobber",
        ],
        f"download {DOCS_ASSET} for {release}",
    )
    archive = destination / DOCS_ASSET
    if not archive.is_file():
        raise SystemExit(f"Downloaded no {DOCS_ASSET} for {release}")
    return archive


def extract_docs(archive: Path, destination: Path) -> None:
    """Extract `archive`, dropping its top-level version directory."""

    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)

    with tarfile.open(archive, "r:gz") as tar:
        members = []
        for member in tar.getmembers():
            parts = Path(member.name).parts
            if len(parts) <= 1:
                continue
            relative = Path(*parts[1:])
            if relative.is_absolute() or ".." in relative.parts:
                raise SystemExit(f"Unsafe member path in {archive}: {member.name}")
            member.name = relative.as_posix()
            members.append(member)
        if not members:
            raise SystemExit(f"Docs archive contains no versioned files: {archive}")
        tar.extractall(destination, members=members, filter="data")


def write_index(docs_root: Path, repository: str, docs_version: str) -> None:
    """Write the documentation root redirect for `docs_version`.

    Matches the index written during a release by the shared
    `roc-lang/release-package` `docs-index` action.
    """

    repository_name = repository.split("/")[-1]
    target = html.escape(f"/{repository_name}/{docs_version}/", quote=True)
    escaped_version = html.escape(docs_version)
    docs_root.mkdir(parents=True, exist_ok=True)
    (docs_root / "index.html").write_text(
        "<!doctype html>\n"
        '<html lang="en">\n'
        "<head>\n"
        '  <meta charset="utf-8">\n'
        f'  <meta http-equiv="refresh" content="0; url={target}">\n'
        f'  <link rel="canonical" href="{target}">\n'
        f"  <title>Redirecting to {escaped_version}</title>\n"
        "</head>\n"
        "<body>\n"
        f'  <p><a href="{target}">Redirecting to {escaped_version}</a></p>\n'
        "</body>\n"
        "</html>\n",
        encoding="utf-8",
        newline="\n",
    )


def restore(docs_root: Path, repository: str, download_root: Path) -> int:
    docs_root.mkdir(parents=True, exist_ok=True)

    restored = 0
    for release in releases_with_docs(repository):
        archive = download_docs_asset(repository, release, download_root / release)
        extract_docs(archive, docs_root / release)
        restored += 1
        print(f"Restored docs for {release}")

    write_index(docs_root, repository, latest_stable_release(repository) or "main")
    return restored


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("docs_root", type=Path, help="Directory to restore docs into")
    parser.add_argument(
        "--repository",
        default=os.environ.get("GITHUB_REPOSITORY", "roc-lang/basic-webserver"),
        help="GitHub repository in owner/name form",
    )
    parser.add_argument(
        "--download-root",
        type=Path,
        default=None,
        help="Directory for downloaded archives (default: a temporary directory)",
    )
    args = parser.parse_args()

    if args.download_root is not None:
        restored = restore(args.docs_root, args.repository, args.download_root)
    else:
        with tempfile.TemporaryDirectory() as temporary_root:
            restored = restore(args.docs_root, args.repository, Path(temporary_root))

    print(f"Restored {restored} documentation archive(s) into {args.docs_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
