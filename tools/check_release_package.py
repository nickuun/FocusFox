"""Sanity-check the Windows release export for source-only files.

Run after exporting FocusFox.exe. The check reads the built binary because the export
embeds the pck, so forbidden resource names should not appear there either.
"""

from pathlib import Path
import sys


EXPORT = Path("build/FocusFox.exe")

FORBIDDEN = [
    b"res://build/",
    b"res://context/",
    b"res://tools/",
    b"den-room2",
    b"den-room3",
    b"green-wide-background - Copy",
    b"__pycache__",
    b".pyc",
    b"den_import.py",
    b"fox_import.py",
    b"unlock.mp3",
]

# GodotSteam ships as DLLs beside the exe rather than inside it. Without them the game
# still runs — just silently without Steam, which is exactly what's easy to miss.
REQUIRED_BESIDE = [
    "steam_api64.dll",
    "libgodotsteam.windows.template_release.x86_64.dll",
]


def main() -> int:
    if not EXPORT.exists():
        print(f"missing export: {EXPORT}", file=sys.stderr)
        return 2

    data = EXPORT.read_bytes()
    found = [needle.decode("utf-8", "replace") for needle in FORBIDDEN if needle in data]
    if found:
        print("release package contains source-only/scratch names:", file=sys.stderr)
        for name in found:
            print(f"  - {name}", file=sys.stderr)
        return 1

    missing = [name for name in REQUIRED_BESIDE if not (EXPORT.parent / name).exists()]
    if missing:
        print("release package is missing files that must ship beside the exe:", file=sys.stderr)
        for name in missing:
            print(f"  - {name}", file=sys.stderr)
        return 1

    print(f"{EXPORT} passed package sanity checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
