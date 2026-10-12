#!/usr/bin/env bash
# Record gameplay takes with Movie Maker (launch/tools/demo_reel.gd) at
# 2400x1080 (20:9, a phone in landscape), then turn each into an H.264 MP4 and drop the big AVI.
#
#   bash launch/video/render_takes.sh [take[:seconds] ...]   (default: all)
#
# A temporary override.cfg makes the window 2400x1080 even on a smaller
# screen; it is removed when the script ends, whatever happens.
set -euo pipefail
cd "$(dirname "$0")/../.."
GD="${GD:-/c/Users/hmmm/Godot_v4.7-stable_win64_console.exe}"
OUT=launch/video/takes
mkdir -p "$OUT"
trap 'rm -f override.cfg' EXIT
printf '[display]\nwindow/size/window_width_override=2400\nwindow/size/window_height_override=1080\nwindow/size/borderless=true\n[editor]\nmovie_writer/mjpeg_quality=0.95\n' > override.cfg

TAKES=("$@")
[ ${#TAKES[@]} -eq 0 ] && TAKES=(home:9 fight:26 boss:24 swarm:20 map:6 garage:6)
for t in "${TAKES[@]}"; do
	name="${t%%:*}"; secs="${t#*:}"; [ "$secs" = "$t" ] && secs=20
	echo "--- $name ($secs s)"
	"$GD" --path . --fixed-fps 60 --write-movie "$OUT/$name.avi" \
		--script launch/tools/demo_reel.gd -- "$name" "$secs" 2>&1 | grep -E "^\[reel\]|SCRIPT ERROR|Parse Error" || true
	ffmpeg -v error -y -i "$OUT/$name.avi" -c:v libx264 -preset fast -crf 17 -pix_fmt yuv420p \
		-c:a aac -b:a 192k "$OUT/$name.mp4"
	rm -f "$OUT/$name.avi"
	ls -la "$OUT/$name.mp4"
done
