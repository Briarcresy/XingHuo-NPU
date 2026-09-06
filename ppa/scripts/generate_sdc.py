#!/usr/bin/env python3
"""为映射网表的实际标量端口生成完整的探索性IO预算，不自动添加false path。"""
import argparse
import json
import math
from pathlib import Path
import re


def generate(config: dict, netlist: str, period: float) -> str:
    keys = ("setup_uncertainty_ns", "hold_uncertainty_ns", "clock_transition_ns",
            "input_delay_min_ns", "input_delay_max_ns", "input_transition_ns",
            "output_delay_min_ns", "output_delay_max_ns", "output_load_pf")
    for key in keys:
        value = config[key]
        if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
            raise ValueError(f"invalid constraint: {key}")
    if not math.isfinite(period) or period <= 0:
        raise ValueError("period must be positive")
    for direction in ("input", "output"):
        if config[f"{direction}_delay_min_ns"] > config[f"{direction}_delay_max_ns"]:
            raise ValueError(f"{direction} delay min exceeds max")
    inputs = re.findall(r"^\s*input (\w+);", netlist, re.M)
    outputs = re.findall(r"^\s*output (\w+);", netlist, re.M)
    if "clock" not in inputs or "reset" not in inputs or not outputs:
        raise ValueError("expected scalar Tile netlist with clock/reset")
    if len(set(inputs)) != 42 or len(set(outputs)) != 51:
        raise ValueError("incomplete Tile v1 port coverage: expected 42 inputs and 51 outputs")
    inputs.remove("clock")
    lines = ["# EXPLORATORY ONLY: budgets are assumptions, not platform signoff.",
             "# Async inputs are conservatively timed here; no broad false paths.",
             "# Shared RAM external delay must be replaced by platform timing.",
             f"create_clock -name tile_clock -period {period:.6f} [get_ports clock]",
             f"set_clock_uncertainty -setup {config['setup_uncertainty_ns']} [get_clocks tile_clock]",
             f"set_clock_uncertainty -hold {config['hold_uncertainty_ns']} [get_clocks tile_clock]",
             f"set_clock_transition {config['clock_transition_ns']} [get_clocks tile_clock]"]
    for port in inputs:
        for limit in ("min", "max"):
            lines.append(f"set_input_delay -{limit} {config[f'input_delay_{limit}_ns']} "
                         f"-clock tile_clock [get_ports {{{port}}}]")
        lines.append(f"set_input_transition {config['input_transition_ns']} [get_ports {{{port}}}]")
    for port in outputs:
        for limit in ("min", "max"):
            lines.append(f"set_output_delay -{limit} {config[f'output_delay_{limit}_ns']} "
                         f"-clock tile_clock [get_ports {{{port}}}]")
        lines.append(f"set_load {config['output_load_pf']} [get_ports {{{port}}}]")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--netlist", type=Path, required=True)
    parser.add_argument("--period", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(generate(json.loads(args.config.read_text()),
                                    args.netlist.read_text(), args.period))
