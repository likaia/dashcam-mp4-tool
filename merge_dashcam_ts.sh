#!/bin/bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<EOF
Usage:
  ./$SCRIPT_NAME [options]

Options:
  -i, --input-dir DIR    Input folder containing .ts/.TS files. Default: current folder
  -o, --output-dir DIR   Output root folder. Default: <input-dir>/merged_mp4
  -c, --chunk SIZE       Output chunk length: 10m | 30m | 1h. Default: 10m
  -h, --help             Show this help message

Behavior:
  - Recursively scans the input folder for .ts/.TS files
  - Groups files by date extracted from the filename when possible
  - Creates one output folder per date
  - Encodes to QuickTime-friendly H.264/AAC MP4

Examples:
  ./$SCRIPT_NAME
  ./$SCRIPT_NAME --input-dir /Users/likai/Desktop/video --chunk 30m
  ./$SCRIPT_NAME --input-dir /path/to/ts --output-dir /path/to/output --chunk 1h
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: '$1' is not installed." >&2
    exit 1
  fi
}

to_abs_path() {
  local target="$1"
  (
    cd "$target" >/dev/null 2>&1
    pwd
  )
}

escape_ffconcat_path() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

chunk_to_seconds() {
  case "$1" in
    10m|10min|10mins|10)
      echo 600
      ;;
    30m|30min|30mins|30)
      echo 1800
      ;;
    1h|60m|60min|60mins|60)
      echo 3600
      ;;
    *)
      return 1
      ;;
  esac
}

extract_date() {
  local file_name
  file_name="$(basename "$1")"

  if [[ "$file_name" =~ ([12][0-9]{3})([01][0-9])([0-3][0-9]) ]]; then
    printf "%s-%s-%s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    return 0
  fi

  stat -f "%Sm" -t "%Y-%m-%d" "$1"
}

pick_video_encoder() {
  if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q 'h264_videotoolbox'; then
    echo "h264_videotoolbox"
  else
    echo "libx264"
  fi
}

build_video_args() {
  local encoder="$1"
  local fps="$2"
  local gop="$3"

  if [[ "$encoder" == "h264_videotoolbox" ]]; then
    cat <<EOF
-c:v
h264_videotoolbox
-pix_fmt
yuv420p
-profile:v
high
-b:v
35M
-maxrate
45M
-bufsize
90M
-g
$gop
-tag:v
avc1
-force_key_frames
expr:gte(t,n_forced*CHUNK_SECONDS)
EOF
  else
    cat <<EOF
-c:v
libx264
-pix_fmt
yuv420p
-preset
medium
-crf
20
-profile:v
high
-g
$gop
-sc_threshold
0
-tag:v
avc1
-force_key_frames
expr:gte(t,n_forced*CHUNK_SECONDS)
EOF
  fi
}

input_dir="."
output_dir=""
chunk_label="10m"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input-dir)
      if [[ $# -lt 2 ]]; then
        echo "Error: missing value for $1" >&2
        exit 1
      fi
      input_dir="$2"
      shift 2
      ;;
    -o|--output-dir)
      if [[ $# -lt 2 ]]; then
        echo "Error: missing value for $1" >&2
        exit 1
      fi
      output_dir="$2"
      shift 2
      ;;
    -c|--chunk)
      if [[ $# -lt 2 ]]; then
        echo "Error: missing value for $1" >&2
        exit 1
      fi
      chunk_label="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$input_dir" ]]; then
  echo "Error: input folder does not exist: $input_dir" >&2
  exit 1
fi

chunk_seconds="$(chunk_to_seconds "$chunk_label")" || {
  echo "Error: unsupported chunk size '$chunk_label'. Use 10m, 30m, or 1h." >&2
  exit 1
}

require_command ffmpeg
require_command ffprobe

input_dir="$(to_abs_path "$input_dir")"
if [[ -z "$output_dir" ]]; then
  output_dir="$input_dir/merged_mp4"
fi
mkdir -p "$output_dir"
output_dir="$(to_abs_path "$output_dir")"

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/dashcam-merge.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

files_list="$tmp_root/all_files.txt"
find "$input_dir" -type f \( -iname '*.ts' \) | LC_ALL=C sort > "$files_list"

if [[ ! -s "$files_list" ]]; then
  echo "Error: no .ts/.TS files found under: $input_dir" >&2
  exit 1
fi

groups_list="$tmp_root/groups.txt"
while IFS= read -r file; do
  printf "%s\t%s\n" "$(extract_date "$file")" "$file" >> "$groups_list"
done < "$files_list"

sorted_groups="$tmp_root/groups_sorted.txt"
LC_ALL=C sort "$groups_list" > "$sorted_groups"

video_encoder="$(pick_video_encoder)"

echo "Input folder:  $input_dir"
echo "Output folder: $output_dir"
echo "Chunk size:    $chunk_label ($chunk_seconds seconds)"
echo "Video encoder: $video_encoder"

current_date=""
group_file=""
first_file=""
processed_dates=0

finalize_group() {
  local date_key="$1"
  local concat_list="$2"
  local sample_file="$3"
  local date_dir
  local fps
  local gop
  local raw_args
  local video_args
  local output_pattern

  date_dir="$output_dir/$date_key"
  mkdir -p "$date_dir"

  fps="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nw=1:nk=1 "$sample_file" | awk -F'/' '{ if (NF == 2 && $2 != 0) printf "%d", ($1 / $2) + 0.5; else print 30 }')"
  if [[ -z "$fps" || "$fps" -le 0 ]]; then
    fps=30
  fi
  gop=$((fps * 2))

  raw_args="$(build_video_args "$video_encoder" "$fps" "$gop")"
  raw_args="${raw_args//CHUNK_SECONDS/$chunk_seconds}"
  video_args=()
  while IFS= read -r line; do
    video_args+=("$line")
  done <<EOF
$raw_args
EOF

  output_pattern="$date_dir/${date_key}_part_%03d.mp4"

  echo
  echo "Processing date: $date_key"
  echo "Output pattern:  $output_pattern"

  ffmpeg -hide_banner -loglevel info -y \
    -f concat -safe 0 -fflags +genpts -i "$concat_list" \
    -map 0:v:0 -map '0:a:0?' \
    "${video_args[@]}" \
    -c:a aac -b:a 192k -ar 48000 \
    -f segment \
    -segment_time "$chunk_seconds" \
    -segment_start_number 1 \
    -reset_timestamps 1 \
    -segment_format mp4 \
    -segment_format_options movflags=+faststart \
    "$output_pattern"
}

while IFS=$'\t' read -r date_key file_path; do
  if [[ "$date_key" != "$current_date" ]]; then
    if [[ -n "$current_date" ]]; then
      finalize_group "$current_date" "$group_file" "$first_file"
      processed_dates=$((processed_dates + 1))
    fi

    current_date="$date_key"
    group_file="$tmp_root/${current_date}.ffconcat"
    first_file="$file_path"
    : > "$group_file"
  fi

  printf "file '%s'\n" "$(escape_ffconcat_path "$file_path")" >> "$group_file"
done < "$sorted_groups"

if [[ -n "$current_date" ]]; then
  finalize_group "$current_date" "$group_file" "$first_file"
  processed_dates=$((processed_dates + 1))
fi

echo
echo "Done. Processed $processed_dates date group(s)."
echo "Outputs saved under: $output_dir"
