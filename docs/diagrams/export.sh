#!/usr/bin/env bash
# .drawio 是权威图源；本脚本只重新导出 SVG，绝不重建或覆盖图源。
set -euo pipefail

diagram_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
drawio_bin="${DRAWIO_BIN:-drawio}"

if ! command -v "$drawio_bin" >/dev/null 2>&1; then
    echo "ERROR: 找不到 drawio；请安装桌面版，或设置 DRAWIO_BIN。" >&2
    exit 1
fi

shopt -s nullglob
diagram_sources=("$diagram_dir"/*.drawio)
if ((${#diagram_sources[@]} == 0)); then
    echo "ERROR: 未找到 .drawio 图源。" >&2
    exit 1
fi

# 明确指定输入格式，避免将导出的 SVG 再次当作图源处理。
for diagram_source in "${diagram_sources[@]}"; do
    "$drawio_bin" --export --format svg --embed-diagram \
        --embed-svg-fonts false --theme light --border 20 "$diagram_source"
done

echo "已更新 ${#diagram_sources[@]} 张 SVG；.drawio 图源未修改。"
