#!/usr/bin/env bash

# 从Yosys和iEDA报告中提取最重要的PPA结果。
set -euo pipefail

result_dir=$1
design=$2
stat_report="$result_dir/synth_stat.txt"
timing_report="$result_dir/$design.rpt"
power_report="$result_dir/$design.pwr"

cell_count=$(awk '$3 == "cells" { print $1; exit }' "$stat_report")
total_area=$(awk '/Chip area for module/ { print $NF; exit }' "$stat_report")
seq_summary=$(awk '/of which used for sequential elements/ {
    area=$(NF-1); pct=$NF; gsub(/[()%]/, "", pct);
    printf "%s um^2 (%s%%)", area, pct; exit
}' "$stat_report")

read -r setup_wns fmax <<< "$(awk -F '|' '
    $3 ~ /core_clock/ && $4 ~ /max/ {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $8);
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $9);
        print $8, $9; exit
    }
' "$timing_report")"

hold_wns=$(awk -F '|' '
    $3 ~ /core_clock/ && $4 ~ /min/ {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $8);
        print $8; exit
    }
' "$timing_report")

read -r setup_tns hold_tns <<< "$(awk -F '|' '
    $2 ~ /core_clock/ && $3 ~ /max/ {
        value=$4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); setup=value
    }
    $2 ~ /core_clock/ && $3 ~ /min/ {
        value=$4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); hold=value
    }
    END { print setup, hold }
' "$timing_report")"

total_power=$(awk '/^Total Power/ { print $(NF-1), $NF; exit }' "$power_report")

echo
echo "========== PPA关键结果 =========="
printf '%-18s %s\n' "标准单元数量:" "$cell_count"
printf '%-18s %s um^2\n' "标准单元面积:" "$total_area"
printf '%-18s %s\n' "时序单元面积:" "$seq_summary"
printf '%-18s %s ns\n' "建立时间WNS:" "$setup_wns"
printf '%-18s %s ns\n' "保持时间WNS:" "$hold_wns"
printf '%-18s %s / %s ns\n' "建立/保持TNS:" "$setup_tns" "$hold_tns"
printf '%-18s %s MHz\n' "估算最高频率:" "$fmax"
printf '%-18s %s\n' "粗略功耗:" "$total_power"
echo "功耗未使用真实VCD/SAIF，仅适合不同RTL版本间的相对比较。"
echo "================================="
