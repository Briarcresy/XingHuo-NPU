#!/usr/bin/env python3
"""Stage source-only input because the official exporter copies the entire directory."""
import argparse
from pathlib import Path
import shutil
import tempfile

from release_check import ROOT, source_hashes


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parent", type=Path, required=True)
    args = parser.parse_args()
    args.parent.mkdir(parents=True, exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix="source-", dir=args.parent.resolve()))
    for name in source_hashes():
        destination = folder / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, destination)
    print(folder)
