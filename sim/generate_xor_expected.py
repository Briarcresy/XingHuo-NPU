#!/usr/bin/env python3
"""从Python Golden Model生成SystemVerilog XOR测试常量包。"""

from pathlib import Path
import random

from golden_model import Matrix2x2, NpuInputs, infer, expected_error_code, infer_xor_network


def main() -> None:
    output = Path("tests/rtl/XorExpectedPkg.sv")
    lines = [
        "// 由sim/generate_xor_expected.py从Golden Model生成，请勿手工计算expected。",
        "package XorExpectedPkg;",
    ]
    for x1, x2 in ((0, 0), (0, 1), (1, 0), (1, 1)):
        result = infer_xor_network(Matrix2x2(x1, x2, 0, 0))
        suffix = f"{x1}{x2}"
        lines.extend(
            [
                f"  localparam logic XOR_CLASS_{suffix} = 1'b{result.classification};",
                f"  localparam logic [31:0] XOR_HIDDEN_{suffix} = 32'h{result.hidden.pack():08x};",
                f"  localparam logic [31:0] XOR_OUTPUT_{suffix} = 32'h{result.output.pack():08x};",
            ]
        )
    # 固定种子使官方离线包也包含可复现的两层随机参考结果。
    rng = random.Random(0x20260906)
    cases = []
    for shift in range(32):
        cases.append((Matrix2x2(-128, 127, 127, -128),
                      Matrix2x2(-128, 127, 127, -128),
                      (2147483647, -2147483648), shift,
                      Matrix2x2(127, -128, -128, 127),
                      (2147483647, -2147483648), 31 - shift))
    for index in range(128):
        matrix = lambda: Matrix2x2(*(rng.randint(-128, 127) for _ in range(4)))
        bias = lambda: tuple(rng.choice((rng.randint(-32768, 32767),
                                       2147483647, -2147483648)) for _ in range(2))
        cases.append((matrix(), matrix(), bias(), index % 16,
                      matrix(), bias(), rng.randrange(32)))
    lines += [
        "  typedef struct packed {",
        "    logic [31:0] activation, weight1;",
        "    logic [63:0] bias1;",
        "    logic [7:0] shift1;",
        "    logic [31:0] weight2;",
        "    logic [63:0] bias2;",
        "    logic [7:0] shift2;",
        "    logic [31:0] hidden, result;",
        "    logic [7:0] error_code;",
        "    logic classification;",
        "  } NetworkVector;",
        f"  localparam integer NETWORK_CASES = {len(cases)};",
        "  localparam NetworkVector NETWORK_VECTORS [0:NETWORK_CASES-1] = '{",
    ]
    text_vectors = []
    for number, (activation, w1, b1, s1, w2, b2, s2) in enumerate(cases):
        first = NpuInputs(activation, w1, *b1, s1)
        hidden = infer(first)
        second = NpuInputs(hidden, w2, *b2, s2)
        result = infer(second)
        error = expected_error_code(first) | expected_error_code(second)
        # 高三位也随机化，验证RAM shift寄存器只使用低五位。
        fields = [f"32'h{activation.pack():08x}", f"32'h{w1.pack():08x}",
                  f"64'h{first.pack_bias():016x}", f"8'h{s1 | (rng.randrange(8) << 5):02x}",
                  f"32'h{w2.pack():08x}", f"64'h{second.pack_bias():016x}",
                  f"8'h{s2 | (rng.randrange(8) << 5):02x}",
                  f"32'h{hidden.pack():08x}", f"32'h{result.pack():08x}",
                  f"8'h{error:02x}", f"1'b{int(result.value_01 > result.value_00)}"]
        lines.append("    '{" + ", ".join(fields) + "}" +
                     ("," if number + 1 < len(cases) else ""))
        text_vectors.append(" ".join(field.split("'")[1][1:] for field in fields))
    lines += ["  };", "endpackage"]
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    vector_path = Path("build/sim/network_vectors.txt")
    vector_path.parent.mkdir(parents=True, exist_ok=True)
    vector_path.write_text("\n".join(text_vectors) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
