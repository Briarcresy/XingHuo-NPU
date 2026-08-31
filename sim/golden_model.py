"""星火NPU的纯Python功能参考模型。

模型只实现公开的数值规格，不调用Verilator，也不读取RTL中间信号。Python整数没有
固定位宽，因此本文件显式模拟INT8/INT32二补码、回绕、舍入、饱和和总线打包。
"""

from __future__ import annotations

from dataclasses import dataclass

INT8_MIN = -(1 << 7)
INT8_MAX = (1 << 7) - 1
INT32_MIN = -(1 << 31)
INT32_MAX = (1 << 31) - 1


def wrap_signed(value: int, bits: int) -> int:
    """只保留低bits位，再按二补码解释为有符号整数。"""
    if bits <= 0:
        raise ValueError("bits必须大于0")
    mask = (1 << bits) - 1
    wrapped = value & mask
    sign_bit = 1 << (bits - 1)
    return wrapped - (1 << bits) if wrapped & sign_bit else wrapped


def int8_from_bits(value: int) -> int:
    """把一个8位位型解释为INT8。"""
    return wrap_signed(value, 8)


def int32_from_bits(value: int) -> int:
    """把一个32位位型解释为INT32。"""
    return wrap_signed(value, 32)


@dataclass(frozen=True)
class Matrix2x2:
    """行优先的2×2 INT8矩阵。"""

    value_00: int
    value_01: int
    value_10: int
    value_11: int

    def __post_init__(self) -> None:
        for value in self.elements():
            if not INT8_MIN <= value <= INT8_MAX:
                raise ValueError(f"矩阵元素{value}超出INT8范围")

    def elements(self) -> tuple[int, int, int, int]:
        return self.value_00, self.value_01, self.value_10, self.value_11

    def pack(self) -> int:
        """按RTL格式打包：低位到高位依次为00、01、10、11。"""
        packed = 0
        for index, value in enumerate(self.elements()):
            packed |= (value & 0xFF) << (8 * index)
        return packed

    @classmethod
    def unpack(cls, packed: int) -> Matrix2x2:
        """从RTL的32位行优先总线恢复矩阵。"""
        values = [int8_from_bits(packed >> (8 * index)) for index in range(4)]
        return cls(*values)


@dataclass(frozen=True)
class NpuInputs:
    activation: Matrix2x2
    weight: Matrix2x2
    bias_0: int
    bias_1: int
    quant_shift: int

    def __post_init__(self) -> None:
        for name, value in (("bias_0", self.bias_0), ("bias_1", self.bias_1)):
            if not INT32_MIN <= value <= INT32_MAX:
                raise ValueError(f"{name}={value}超出INT32范围")
        if not 0 <= self.quant_shift <= 31:
            raise ValueError("quant_shift必须在0～31之间")

    def pack_bias(self) -> int:
        """低32位放bias_0，高32位放bias_1。"""
        return (self.bias_0 & 0xFFFFFFFF) | ((self.bias_1 & 0xFFFFFFFF) << 32)


def matmul_2x2(activation: Matrix2x2, weight: Matrix2x2) -> tuple[int, int, int, int]:
    """计算四个INT32矩阵乘法累加值，返回顺序为00、01、10、11。"""
    return (
        activation.value_00 * weight.value_00 + activation.value_01 * weight.value_10,
        activation.value_00 * weight.value_01 + activation.value_01 * weight.value_11,
        activation.value_10 * weight.value_00 + activation.value_11 * weight.value_10,
        activation.value_10 * weight.value_01 + activation.value_11 * weight.value_11,
    )


def requantize_int32(value: int, shift: int) -> int:
    """匹配Requantize.v的加偏置、算术右移和INT8饱和。"""
    if not INT32_MIN <= value <= INT32_MAX:
        raise ValueError("重量化输入必须是INT32")
    if not 0 <= shift <= 31:
        raise ValueError("shift必须在0～31之间")

    # Python负数右移就是算术右移，和Verilog的>>>一致。
    shifted = value if shift == 0 else (value + (1 << (shift - 1))) >> shift
    return max(INT8_MIN, min(INT8_MAX, shifted))


def infer(inputs: NpuInputs) -> Matrix2x2:
    """执行Y=ReLU(Requantize(A×W+Bias))并返回2×2 INT8结果。"""
    sums = matmul_2x2(inputs.activation, inputs.weight)
    biases = (inputs.bias_0, inputs.bias_1, inputs.bias_0, inputs.bias_1)
    outputs: list[int] = []

    for accumulator, bias in zip(sums, biases):
        # Bias.v的输出只有32位，溢出时只保留低32位。
        biased = wrap_signed(accumulator + bias, 32)
        quantized = requantize_int32(biased, inputs.quant_shift)
        outputs.append(max(0, quantized))

    return Matrix2x2(*outputs)
