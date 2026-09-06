#!/usr/bin/env python3
"""Invalidate synthesis when a PDK selection or synthesis tool changes."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def fingerprint(path):
    path = Path(path).resolve(strict=True)
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"path": str(path), "sha256": digest}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("output", "design", "frequency", "vt", "liberty", "cells"):
        parser.add_argument(f"--{name}", required=True)
    args = parser.parse_args()
    config = {
        "design": args.design, "frequency_mhz": float(args.frequency), "vt": args.vt,
        "liberty": fingerprint(args.liberty), "cells": fingerprint(args.cells),
        "yosys": subprocess.check_output(["yosys", "-V"], text=True).strip(),
    }
    output = Path(args.output)
    text = json.dumps(config, indent=2) + "\n"
    if not output.exists() or output.read_text() != text:
        output.write_text(text)
