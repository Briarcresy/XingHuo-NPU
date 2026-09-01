#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../../.." && pwd)
destination="$repo_root/tapeout/mpsoc-digital/xinghuo-npu/rtl/core"

mkdir -p "$destination"

for rtl_name in \
    Bias.v \
    ControlUnit.v \
    MacPE.v \
    MatrixFeeder.v \
    ReLU.v \
    Requantize.v \
    SystolicArray.v \
    VPU.v \
    XingHuo_NPU.v; do
    cp "$repo_root/src/$rtl_name" "$destination/$rtl_name"
    # 官方测试的 SystemVerilog 文件不含 timescale；移除快照中的仿真指令，
    # 避免 Verilator TIMESCALEMOD 警告。逻辑电路不发生任何改变。
    sed -i '/^`timescale[[:space:]]/d' "$destination/$rtl_name"
done

echo "NPU core snapshot synchronized to: $destination"
