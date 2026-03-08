#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MERGE_SCRIPT="$SCRIPT_DIR/merge_dashcam_ts.sh"

pause_before_exit() {
  if [[ -t 0 ]]; then
    echo
    read -r -p "按回车退出..." _
  fi
}

pick_folder_with_finder() {
  osascript <<'APPLESCRIPT'
try
  POSIX path of (choose folder with prompt "选择包含 TS 视频文件的文件夹")
on error number -128
  return "__CANCELLED__"
end try
APPLESCRIPT
}

prompt_chunk() {
  local input
  echo >&2
  echo "请选择输出视频分段长度：" >&2
  echo "  1) 10分钟" >&2
  echo "  2) 30分钟" >&2
  echo "  3) 1小时" >&2
  read -r -p "输入 1/2/3，默认 1: " input >&2

  case "${input:-1}" in
    1) echo "10m" ;;
    2) echo "30m" ;;
    3) echo "1h" ;;
    *)
      echo >&2
      echo "输入无效，已使用默认值 10m。" >&2
      echo "10m"
      ;;
  esac
}

prompt_input_dir() {
  local mode
  local selected

  echo "请选择输入文件夹：" >&2
  echo "  1) 用 Finder 选择文件夹（推荐）" >&2
  echo "  2) 使用当前目录" >&2
  echo "  3) 手动输入路径" >&2
  read -r -p "输入 1/2/3，默认 1: " mode >&2

  case "${mode:-1}" in
    1)
      selected="$(pick_folder_with_finder)"
      if [[ "$selected" == "__CANCELLED__" ]]; then
        echo "已取消文件夹选择。" >&2
        pause_before_exit
        exit 1
      fi
      printf "%s\n" "$selected"
      ;;
    2)
      pwd
      ;;
    3)
      read -r -p "请输入文件夹完整路径: " selected
      if [[ -z "${selected:-}" ]]; then
        echo "未输入路径。" >&2
        pause_before_exit
        exit 1
      fi
      printf "%s\n" "$selected"
      ;;
    *)
      echo "输入无效，已使用 Finder 选择。" >&2
      selected="$(pick_folder_with_finder)"
      if [[ "$selected" == "__CANCELLED__" ]]; then
        echo "已取消文件夹选择。" >&2
        pause_before_exit
        exit 1
      fi
      printf "%s\n" "$selected"
      ;;
  esac
}

if [[ ! -x "$MERGE_SCRIPT" ]]; then
  echo "Error: missing script: $MERGE_SCRIPT"
  pause_before_exit
  exit 1
fi

if [[ $# -gt 0 ]]; then
  echo "Running:"
  printf '  %q' "$MERGE_SCRIPT" "$@"
  echo
  echo
  bash "$MERGE_SCRIPT" "$@"
  pause_before_exit
  exit 0
fi

if [[ -t 1 ]]; then
  clear
fi
echo "Dashcam MP4 Tool"
echo
echo "这个 .command 支持两种方式："
echo "  1) 双击运行后，按提示选择文件夹和分段长度"
echo "  2) 在终端里直接传参运行，例如："
echo "     ./run_dashcam_merge.command --input-dir /Users/likai/Desktop/video --chunk 30m"
echo

input_dir="$(prompt_input_dir)"
chunk_value="$(prompt_chunk)"

echo
read -r -p "输出根目录（直接回车使用默认值 <输入目录>/merged_mp4）: " output_dir

cmd=(bash "$MERGE_SCRIPT" --input-dir "$input_dir" --chunk "$chunk_value")
if [[ -n "${output_dir:-}" ]]; then
  cmd+=(--output-dir "$output_dir")
fi

echo
echo "即将执行："
printf '  %q' "${cmd[@]}"
echo
echo

"${cmd[@]}"
pause_before_exit
