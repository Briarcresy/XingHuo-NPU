import unittest

from sim.golden_model import (
    INT32_MAX,
    INT32_MIN,
    Matrix2x2,
    NpuInputs,
    ERROR_BIAS_OVERFLOW,
    bias_add_int32,
    expected_error_code,
    infer,
    matmul_2x2,
    requantize_int32,
    wrap_signed,
)


class GoldenModelTest(unittest.TestCase):
    def test_pack_unpack_round_trip(self):
        matrix = Matrix2x2(-128, -1, 0, 127)
        self.assertEqual(Matrix2x2.unpack(matrix.pack()), matrix)
        self.assertEqual(matrix.pack(), 0x7F00FF80)

    def test_matrix_multiply_and_element_order(self):
        activation = Matrix2x2(1, 2, 3, 4)
        weight = Matrix2x2(5, 6, 7, 8)
        self.assertEqual(matmul_2x2(activation, weight), (19, 22, 43, 50))

    def test_bias_is_broadcast_by_output_column(self):
        inputs = NpuInputs(Matrix2x2(1, 0, 0, 1), Matrix2x2(1, 1, 1, 1), 2, 4, 0)
        self.assertEqual(infer(inputs), Matrix2x2(3, 5, 3, 5))

    def test_signed_operands_and_relu(self):
        inputs = NpuInputs(Matrix2x2(-2, 0, 0, 2), Matrix2x2(3, -4, 3, -4), 0, 0, 0)
        self.assertEqual(infer(inputs), Matrix2x2(0, 8, 6, 0))

    def test_shift_zero(self):
        self.assertEqual(requantize_int32(126, 0), 126)
        self.assertEqual(requantize_int32(-127, 0), -127)

    def test_arithmetic_shift_boundaries(self):
        self.assertEqual(requantize_int32(1, 1), 0)
        self.assertEqual(requantize_int32(2, 1), 1)
        self.assertEqual(requantize_int32(-1, 1), -1)
        self.assertEqual(requantize_int32(-3, 1), -2)

    def test_int8_saturation(self):
        self.assertEqual(requantize_int32(1000, 0), 127)
        self.assertEqual(requantize_int32(-1000, 0), -128)

    def test_relu_after_saturation(self):
        inputs = NpuInputs(Matrix2x2(0, 0, 0, 0), Matrix2x2(0, 0, 0, 0), -1000, 1000, 0)
        self.assertEqual(infer(inputs), Matrix2x2(0, 127, 0, 127))

    def test_int32_wrap(self):
        self.assertEqual(wrap_signed(INT32_MAX + 1, 32), INT32_MIN)
        self.assertEqual(wrap_signed(INT32_MIN - 1, 32), INT32_MAX)

    def test_bias_overflow_status(self):
        self.assertEqual(bias_add_int32(INT32_MAX, 1), (INT32_MIN, True))
        self.assertEqual(bias_add_int32(INT32_MIN, -1), (INT32_MAX, True))
        self.assertEqual(bias_add_int32(100, -50), (50, False))

        overflowing = NpuInputs(
            Matrix2x2(1, 1, 1, 1), Matrix2x2(1, 1, 1, 1), INT32_MAX, 0, 0
        )
        self.assertEqual(expected_error_code(overflowing), ERROR_BIAS_OVERFLOW)

    def test_invalid_ranges_are_rejected(self):
        with self.assertRaises(ValueError):
            Matrix2x2(128, 0, 0, 0)
        with self.assertRaises(ValueError):
            NpuInputs(Matrix2x2(0, 0, 0, 0), Matrix2x2(0, 0, 0, 0), 0, 0, 32)


if __name__ == "__main__":
    unittest.main()
