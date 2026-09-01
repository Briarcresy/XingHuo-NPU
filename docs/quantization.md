# INT8量化规则

## 数据宽度

- Activation和Weight：有符号INT8，范围`-128～127`；
- 单次乘积：完整有符号INT16；
- PE累加器：有符号INT32；
- Bias：有符号INT32，并与累加器采用相同尺度；
- 输出：重量化并激活后的INT8。

Bias的常见离线计算方式是：

```text
bias_int32 = round(real_bias / (activation_scale × weight_scale))
```

NPU1.1会检测`INT32 accumulator + INT32 bias`的数学结果是否超出INT32范围。发生
溢出时仍按二补码保留低32位以兼容NPU1.0，同时置位`error_code[1]`供软件诊断。

## 当前重量化

完整量化通常需要乘法比例系数和zero-point。当前版本为减小面积，使用对称、2的幂
缩放，zero-point固定为0：

```text
if quant_shift == 0:
    shifted = biased_sum
else:
    shifted = (biased_sum + 2^(quant_shift-1)) >>> quant_shift

quantized = saturate_to_int8(shifted)
result = max(0, quantized)
```

`>>>`是算术右移。加半个量化步长实现就近舍入，恰好位于半值时向正方向舍入。
例如右移1位时：`1→1`、`-1→0`、`-3→-1`。

## 当前限制

- 一层的四个输出共用同一个`quant_shift`；
- 不支持任意乘法比例系数；
- 不支持非零zero-point；
- 不支持逐通道量化参数；
- ReLU固定开启；
- 只计算固定2×2矩阵。

这些限制使硬件适合教学和小面积实验，但不能直接覆盖通用神经网络部署流程。
