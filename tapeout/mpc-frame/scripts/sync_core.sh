#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../../.." && pwd)
destination="$repo_root/tapeout/mpc-frame/xinghuo-npu/rtl/core"

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
    # FrameTop源码不带timescale；移除仿真指令以避免官方Frame测试的TIMESCALEMOD警告。
    sed -i '/^`timescale[[:space:]]/d' "$destination/$rtl_name"
done

echo "NPU core snapshot synchronized to: $destination"
