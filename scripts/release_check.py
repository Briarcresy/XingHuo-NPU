#!/usr/bin/env python3
"""Run frontend checks and archive a reproducible, explicitly non-signoff handoff."""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def source_hashes():
    files = [ROOT / name for name in ("Makefile", "README.md", "design.json", ".gitignore")]
    for directory in ("rtl", "sim", "tests", "verification", "filelists", "constraints",
                      "docs", "ppa", "scripts", ".github"):
        files.extend(path for path in (ROOT / directory).rglob("*")
                     if path.is_file() and "__pycache__" not in path.parts)
    return {str(path.relative_to(ROOT)): digest(path) for path in sorted(set(files))}


def capture(command, cwd=ROOT):
    return subprocess.check_output(command, cwd=cwd, text=True, stderr=subprocess.STDOUT).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    local_framework = ROOT / "mpsoc-digital"
    parser.add_argument(
        "--framework",
        type=Path,
        default=(local_framework if (local_framework / "Makefile").is_file()
                 else Path.home() / "mpsoc-digital"),
    )
    parser.add_argument("--pdk", type=Path, default=Path.home() / "pdk/icsprout55-pdk")
    parser.add_argument("--ieda", type=Path, default=ROOT / "yosys-sta/bin/iEDA")
    args = parser.parse_args()
    release_root = ROOT / "build/releases"
    release_root.mkdir(parents=True, exist_ok=True)
    with (release_root / ".lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        folder = release_root / run_id
        folder.mkdir()
        (folder / "logs").mkdir()
        # Regenerate deterministic expected files BEFORE freezing the source set.
        subprocess.run(["make", "xor-expected"], cwd=ROOT, check=True)
        sources = source_hashes()
        manifest = {
            "created_utc": run_id, "frontend_checks_passed": False,
            "tapeout_signoff": False, "sources_sha256": sources, "checks": [],
            "git_head": capture(["git", "rev-parse", "HEAD"]),
            "git_status": capture(["git", "status", "--short"]),
            "framework_head": capture(["git", "rev-parse", "HEAD"], args.framework),
            "pdk_head": capture(["git", "rev-parse", "HEAD"], args.pdk),
            "tools": {"verilator": capture(["verilator", "--version"]),
                      "yosys": capture(["yosys", "-V"]),
                      "iverilog": capture(["iverilog", "-V"]).splitlines()[0]},
        }
        ppa = ROOT / "build/ppa/XingHuoNpuTile-main-150MHz-RVT"
        commands = [
            ("rtl", ["make", "lint", "test"]),
            ("official", ["make", "official-export", f"MPSOC_DIGITAL={args.framework.resolve()}"]),
            ("mapped", ["make", "-C", "ppa", "gls", "ppa", "multi-corner",
                        f"ICS55_PDK={args.pdk.resolve()}", f"IEDA_BIN={args.ieda.resolve()}",
                        f"BUILD_DIR={ppa}", "VT=R", "CLK_FREQ_MHZ=200"]),
        ]
        try:
            for name, command in commands:
                print(f"Release check {name}; log: {folder / 'logs' / (name + '.log')}", flush=True)
                # Do not inherit parent make command-line overrides into the fixed release profile.
                environment = {key: value for key, value in os.environ.items()
                               if key not in ("MAKEFLAGS", "MFLAGS", "MAKEOVERRIDES")}
                with (folder / "logs" / f"{name}.log").open("w") as log:
                    result = subprocess.run(command, cwd=ROOT, env=environment,
                                            stdout=log, stderr=subprocess.STDOUT)
                manifest["checks"].append({"name": name, "command": command, "exit_code": result.returncode})
                if result.returncode:
                    raise RuntimeError(f"{name} failed; see {folder / 'logs' / (name + '.log')}")
                if name == "official":
                    # Freeze the validated export immediately; framework workspaces can be cleaned later.
                    export = args.framework / "build/export/xinghuo-npu"
                    for forbidden in (".git", "build", "yosys-sta", "reference"):
                        if (export / "source" / forbidden).exists():
                            raise RuntimeError(f"official export contains unwanted source/{forbidden}")
                    shutil.copytree(export, folder / "tile")
            if source_hashes() != sources:
                raise RuntimeError("source files changed during checks; refusing to package")
            for name in sources:
                destination = folder / "source" / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / name, destination)
            report_dir = folder / "ppa"
            report_dir.mkdir()
            corner_results = json.loads((ppa / "corners/summary.json").read_text())
            # iEDA also creates timestamp backups and duplicate netlists; archive only this run's reports.
            reports = [ppa / name for name in ("XingHuoNpuTile.netlist.v", "XingHuoNpuTile.sim.v",
                       "XingHuoNpuTile.rpt", "XingHuoNpuTile.pwr", "XingHuoNpuTile.sdc",
                       "synth_stat.txt", "synth_check.txt", "gate-test.log", "build-config.json",
                       "corners/summary.json", "corners/summary.md")]
            reports += [ppa / "corners" / corner["name"] / "XingHuoNpuTile.rpt"
                        for corner in corner_results["corners"]]
            for path in reports:
                destination = report_dir / path.relative_to(ppa)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, destination)
            manifest["frontend_checks_passed"] = True
            manifest["prelayout_timing_met"] = corner_results["timing_met"]
            manifest["remaining_signoff_work"] = "See source/docs/tapeout-readiness.md"
            manifest["artifacts_sha256"] = {
                str(path.relative_to(folder)): digest(path)
                for path in sorted(folder.rglob("*")) if path.is_file()
            }
        except Exception as error:
            manifest["error"] = str(error)
            (folder / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
            raise
        (folder / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
        sums = [f"{digest(path)}  {path.relative_to(folder)}" for path in sorted(folder.rglob("*")) if path.is_file()]
        (folder / "SHA256SUMS").write_text("\n".join(sums) + "\n")
        archive = release_root / f"{run_id}.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(folder, arcname=run_id)
        (release_root / f"{run_id}.tar.gz.sha256").write_text(f"{digest(archive)}  {archive.name}\n")
        print(f"Frontend checks PASS; prelayout timing {'MET' if manifest['prelayout_timing_met'] else 'NOT_MET'}; "
              "tapeout signoff NOT COMPLETED", flush=True)
        print(f"Archive: {archive}", flush=True)


if __name__ == "__main__":
    main()
