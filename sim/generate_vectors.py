#!/usr/bin/env python3
"""生成可复现的定向与随机Verilator测试向量。"""

from __future__ import annotations

import argparse
import random
from dataclasses import dataclass
from pathlib import Path

try:
    from .golden_model import INT32_MAX, INT32_MIN, Matrix2x2, NpuInputs, expected_error_code, infer
except ImportError:  # 允许直接执行python3 sim/generate_vectors.py。
    from golden_model import INT32_MAX, INT32_MIN, Matrix2x2, NpuInputs, expected_error_code, infer

DEFAULT_COUNT = 1000
DEFAULT_SEED = 0x20260831


@dataclass(frozen=True)
class NamedCase:
    name: str
    inputs: NpuInputs


def directed_cases() -> list[NamedCase]:
    """覆盖主要功能和数值边界；expected仍统一由infer()计算。"""
    return [
        NamedCase("all_zero", NpuInputs(Matrix2x2(0, 0, 0, 0), Matrix2x2(0, 0, 0, 0), 0, 0, 0)),
        NamedCase("basic_matmul", NpuInputs(Matrix2x2(1, 2, 3, 4), Matrix2x2(5, 6, 7, 8), 1, -2, 0)),
        NamedCase("signed_operands", NpuInputs(Matrix2x2(-8, 7, -6, 5), Matrix2x2(4, -3, 2, -1), 3, -4, 0)),
        NamedCase("int8_max", NpuInputs(Matrix2x2(127, 127, 127, 127), Matrix2x2(127, 127, 127, 127), 0, 0, 8)),
        NamedCase("int8_min", NpuInputs(Matrix2x2(-128, -128, -128, -128), Matrix2x2(-128, -128, -128, -128), 0, 0, 8)),
        NamedCase("relu_negative", NpuInputs(Matrix2x2(1, 2, 3, 4), Matrix2x2(5, 6, 7, 8), -1000, -1000, 0)),
        NamedCase("positive_saturation", NpuInputs(Matrix2x2(127, 127, 127, 127), Matrix2x2(127, 127, 127, 127), 1000, 1000, 0)),
        NamedCase("negative_saturation", NpuInputs(Matrix2x2(-128, -128, -128, -128), Matrix2x2(127, 127, 127, 127), -1000, -1000, 0)),
        NamedCase("positive_rounding", NpuInputs(Matrix2x2(1, 0, 0, 1), Matrix2x2(1, 3, 1, 3), 0, 0, 1)),
        NamedCase("negative_rounding", NpuInputs(Matrix2x2(1, 0, 0, 1), Matrix2x2(-1, -3, -1, -3), 0, 0, 1)),
        NamedCase("maximum_shift", NpuInputs(Matrix2x2(127, -128, -128, 127), Matrix2x2(-128, 127, 127, -128), 123456, -123456, 31)),
        NamedCase("bias_boundaries", NpuInputs(Matrix2x2(1, 1, 1, 1), Matrix2x2(1, 1, 1, 1), INT32_MAX, INT32_MIN, 0)),
        # NPU1.2 Weight-resident（权重驻留）定向用例：前两例复用同一权重；
        # 后两例用相同Activation
        # 对比切换前后的两组权重。expected仍全部由golden model生成。
        NamedCase("resident_reuse_a", NpuInputs(Matrix2x2(2, -3, 4, 5), Matrix2x2(1, 2, -1, 3), 7, -9, 1)),
        NamedCase("resident_reuse_b", NpuInputs(Matrix2x2(-6, 7, 8, -9), Matrix2x2(1, 2, -1, 3), 7, -9, 1)),
        NamedCase("resident_shadow_old", NpuInputs(Matrix2x2(3, 4, -5, 6), Matrix2x2(1, 2, -1, 3), 0, 0, 0)),
        NamedCase("resident_shadow_new", NpuInputs(Matrix2x2(3, 4, -5, 6), Matrix2x2(-2, 5, 7, -4), 0, 0, 0)),
    ]


def random_matrix(generator: random.Random) -> Matrix2x2:
    return Matrix2x2(*(generator.randint(-128, 127) for _ in range(4)))


def random_cases(count: int, seed: int) -> list[NamedCase]:
    generator = random.Random(seed)
    cases: list[NamedCase] = []
    for index in range(count):
        # 大多数Bias靠近实际小矩阵结果；每4例加入一次完整INT32范围以覆盖回绕。
        if index % 4 == 0:
            bias_0 = generator.randint(INT32_MIN, INT32_MAX)
            bias_1 = generator.randint(INT32_MIN, INT32_MAX)
        else:
            bias_0 = generator.randint(-100_000, 100_000)
            bias_1 = generator.randint(-100_000, 100_000)
        cases.append(
            NamedCase(
                f"random_{index:04d}",
                NpuInputs(
                    random_matrix(generator),
                    random_matrix(generator),
                    bias_0,
                    bias_1,
                    generator.randint(0, 31),
                ),
            )
        )
    return cases


def write_vectors(path: Path, cases: list[NamedCase], directed_count: int, random_count: int, seed: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as output:
        output.write("# XingHuo-NPU vector format v1\n")
        output.write(f"# directed={directed_count} random={random_count} seed=0x{seed:x}\n")
        output.write("# name activation_hex weight_hex bias_hex shift expected_hex error_hex\n")
        for case in cases:
            expected = infer(case.inputs).pack()
            output.write(
                f"{case.name} "
                f"{case.inputs.activation.pack():08x} "
                f"{case.inputs.weight.pack():08x} "
                f"{case.inputs.pack_bias():016x} "
                f"{case.inputs.quant_shift:d} "
                f"{expected:08x} "
                f"{expected_error_code(case.inputs):02x}\n"
            )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="生成星火NPU Verilator测试向量")
    parser.add_argument("--count", type=int, default=DEFAULT_COUNT, help="随机用例数，默认1000")
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=DEFAULT_SEED, help="随机种子")
    parser.add_argument("--output", type=Path, default=Path("build/sim/test_vectors.txt"), help="输出文件")
    arguments = parser.parse_args()
    if arguments.count < 0:
        parser.error("--count不能为负数")
    return arguments


def main() -> None:
    arguments = parse_arguments()
    directed = directed_cases()
    random_part = random_cases(arguments.count, arguments.seed)
    write_vectors(arguments.output, directed + random_part, len(directed), len(random_part), arguments.seed)
    print(
        f"Generated {len(directed) + len(random_part)} vectors "
        f"(directed={len(directed)}, random={len(random_part)}, seed=0x{arguments.seed:x})"
    )


if __name__ == "__main__":
    main()
