#!/usr/bin/env bash
# Lay a voice-over on the demo: the voice on top, the video's own sound ducked
# under it while it speaks.
#
#   bash launch/video/vo_mix.sh vo.wav                  # over the music cut
#   BASE=launch/video/out/yeetfleet_demo.mp4 bash launch/video/vo_mix.sh vo.wav
#
# vo.wav is the whole read, starting at 0:00 (VOICEOVER.md has the times); pad
# it with silence in any editor if you recorded it in pieces. Writes
# out/yeetfleet_demo_vo.mp4 (override with OUT=...).
set -euo pipefail
cd "$(dirname "$0")"
VO="${1:?usage: bash launch/video/vo_mix.sh <voice.wav>}"
BASE="${BASE:-out/yeetfleet_demo_music.mp4}"
OUT="${OUT:-out/yeetfleet_demo_vo.mp4}"
ffmpeg -v error -y -i "$BASE" -i "$VO" \
	-filter_complex "[1:a]aformat=sample_rates=48000:channel_layouts=stereo,highpass=f=80,acompressor=threshold=-18dB:ratio=3:makeup=4,asplit[vo][sc];[0:a][sc]sidechaincompress=threshold=0.02:ratio=10:attack=15:release=450[bg];[bg][vo]amix=inputs=2:normalize=0:duration=first[a]" \
	-map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -movflags +faststart "$OUT"
echo "wrote $OUT"
