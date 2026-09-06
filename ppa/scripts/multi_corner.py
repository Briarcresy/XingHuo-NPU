#!/usr/bin/env python3
"""Run all seven available corners on ONE RVT/LVT/HVT mapped netlist.

These are pre-layout library-corner estimates: no extracted RC, CTS, or signoff.
Negative slack is reported as NOT_MET; tool or incomplete-report errors fail.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

from build_config import fingerprint


def read_timing(path):
    slacks = {"max": [], "min": []}
    tns = {}
    for line in Path(path).read_text().splitlines():
        if not line.startswith("|"):
            continue
        columns = [column.strip() for column in line.split("|")[1:-1]]
        if len(columns) == 8 and columns[1] == "tile_clock" and columns[2] in slacks:
            slacks[columns[2]].append(float(columns[6]))
        if len(columns) == 3 and columns[0] == "tile_clock" and columns[1] in slacks:
            tns[columns[1]] = float(columns[2])
    if not all(slacks.values()) or set(tns) != {"min", "max"}:
        raise ValueError(f"missing setup/hold results in {path}")
    result = {"setup_wns_ns": min(slacks["max"]), "hold_wns_ns": min(slacks["min"]),
              "setup_tns_ns": tns["max"], "hold_tns_ns": tns["min"]}
    result["timing_met"] = all(value >= 0 for value in result.values())
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("netlist", "sdc", "lib-dir", "ieda", "output"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    parser.add_argument("--design", required=True)
    parser.add_argument("--vt", choices=("R", "L", "H"), required=True)
    args = parser.parse_args()
    libraries = sorted(args.lib_dir.glob(f"ics55_LLSC_H7C{args.vt}_*_nldm.lib"))
    if len(libraries) != 7:
        raise SystemExit(f"expected 7 library corners, found {len(libraries)}")
    args.output.mkdir(parents=True, exist_ok=True)
    netlist = fingerprint(args.netlist)
    results = {
        "scope": "pre-layout estimate; ideal clock; no extracted parasitics; assumed IO budget",
        "signoff": False, "netlist": netlist, "sdc": fingerprint(args.sdc),
        "ieda": fingerprint(args.ieda), "corners": [],
    }
    for library in libraries:
        corner = library.stem.removeprefix(f"ics55_LLSC_H7C{args.vt}_").removesuffix("_nldm")
        folder = (args.output / corner).resolve()
        folder.mkdir(parents=True, exist_ok=True)
        print(f"STA {corner} ...", flush=True)
        command = [str(args.ieda.resolve()), "-script", str(Path(__file__).with_name("sta.tcl").resolve()),
                   str(args.sdc.resolve()), str(args.netlist.resolve()), args.design,
                   str(library.resolve()), str(folder), "0"]
        with (folder / "sta.log").open("w") as log:
            subprocess.run(command, cwd=folder, env={**os.environ, "GLOG_log_dir": str(folder)},
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=300)
        metrics = read_timing(folder / f"{args.design}.rpt")
        results["corners"].append({"name": corner, "liberty": fingerprint(library), **metrics})
        print(f"  setup {metrics['setup_wns_ns']:.3f} ns; hold {metrics['hold_wns_ns']:.3f} ns; "
              f"{'MET' if metrics['timing_met'] else 'NOT_MET'}", flush=True)
    if fingerprint(args.netlist) != netlist:
        raise RuntimeError("mapped netlist changed during corner analysis")
    results["timing_met"] = all(corner["timing_met"] for corner in results["corners"])
    (args.output / "summary.json").write_text(json.dumps(results, indent=2) + "\n")
    rows = ["# Pre-layout library-corner STA", "", results["scope"], "",
            "All corners use the same mapped netlist. This is not tapeout signoff.", "",
            "| Corner | Setup WNS (ns) | Hold WNS (ns) | Result |",
            "| --- | ---: | ---: | --- |"]
    rows += [f"| {c['name']} | {c['setup_wns_ns']:.3f} | {c['hold_wns_ns']:.3f} | "
             f"{'MET' if c['timing_met'] else 'NOT_MET'} |" for c in results["corners"]]
    (args.output / "summary.md").write_text("\n".join(rows) + "\n")
    print(f"Reports: {args.output / 'summary.md'}", flush=True)


if __name__ == "__main__":
    main()
