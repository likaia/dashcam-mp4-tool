# Dashcam MP4 Tool

把海康行车记录仪 `.ts/.TS` 切片转成适合 macOS QuickTime Player 播放的 `.mp4`。

脚本： [merge_dashcam_ts.sh](/Users/likai/Desktop/dashcam-mp4-tool/merge_dashcam_ts.sh)

双击运行版： [run_dashcam_merge.command](/Users/likai/Desktop/dashcam-mp4-tool/run_dashcam_merge.command)

## 功能

- 支持传入输入目录，默认当前目录
- 自动按文件名中的日期分组，并按日期创建输出文件夹
- 支持输出分段长度：`10m`、`30m`、`1h`
- 输出编码固定为 `H.264 + AAC`，兼容 QuickTime Player
- macOS 上优先使用 `h264_videotoolbox` 硬件编码

## 用法

```bash
cd /Users/likai/Desktop/dashcam-mp4-tool
chmod +x ./merge_dashcam_ts.sh
chmod +x ./run_dashcam_merge.command

./merge_dashcam_ts.sh
./merge_dashcam_ts.sh --input-dir /Users/likai/Desktop/video
./merge_dashcam_ts.sh --input-dir /Users/likai/Desktop/video --chunk 30m
./merge_dashcam_ts.sh --input-dir /Users/likai/Desktop/video --output-dir /Users/likai/Desktop/video/output --chunk 1h

./run_dashcam_merge.command
./run_dashcam_merge.command --input-dir /Users/likai/Desktop/video --chunk 30m
```

## `.command` 说明

- 双击 `run_dashcam_merge.command` 会先打开终端窗口
- 之后会弹出 Finder 文件夹选择框
- 选完文件夹后，会回到终端继续输入分段长度和输出目录

说明：
`.command` 是 macOS 通过 Terminal 启动的，所以严格来说无法做到“先打开 Finder，再打开终端窗口”。如果你需要这个顺序，应该做成 `.app` 包装器。

## 输出示例

如果源文件日期是 `2026-03-08`，默认会输出到：

```text
<输入目录>/merged_mp4/2026-03-08/2026-03-08_part_001.mp4
```
