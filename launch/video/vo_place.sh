#!/usr/bin/env bash
# Put the voice-over lines (one audio file each) on the demo's timeline.
#
#   bash launch/video/vo_place.sh path/to/lines            # 01.wav 02.wav ...
#   bash launch/video/vo_place.sh path/to/lines out/my.wav
#
# Reads vo_lines.tsv (id, start second, window, line). For each id it takes
# <dir>/<id>.wav (or .mp3 .m4a .ogg .flac), trims the silence a voice leaves
# at either end, speeds it up to fit its window if it runs long (at most
# MAX_TEMPO, 1.3x), and delays it to its start. Writes out/vo_track.wav, as
# long as the video (TOTAL seconds), for vo_mix.sh.
set -euo pipefail
cd "$(dirname "$0")"
DIR="${1:?usage: bash launch/video/vo_place.sh <folder with 01.wav ...> [out.wav]}"
OUT="${2:-out/vo_track.wav}"
TOTAL="${TOTAL:-81.62}"
MAX_TEMPO="${MAX_TEMPO:-1.3}"
FFPROBE="$(command -v ffprobe || true)"
[ -n "$FFPROBE" ] || FFPROBE="$(dirname "$(command -v ffmpeg)")/ffprobe"
# What a voice leaves as silence at the start and the end of a file.
TRIM="silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.04,areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.12,areverse"

inputs=()
chains=""
labels=""
n=0
late=0
printf '%-4s %7s %7s %7s %6s  %s\n' id start clip window tempo line
while IFS=$'\t' read -r id start win text; do
	case "$id" in '' | \#*) continue ;; esac
	f=""
	for ext in wav mp3 m4a ogg flac; do
		if [ -f "$DIR/$id.$ext" ]; then
			f="$DIR/$id.$ext"
			break
		fi
	done
	if [ -z "$f" ]; then
		printf '%-4s %7s  (no file %s/%s.*)  %s\n' "$id" "$start" "$DIR" "$id" "$text"
		continue
	fi
	# Its length without the silence at both ends.
	tmp="$(mktemp "${TMPDIR:-/tmp}/vo_place.XXXXXX.wav")"
	ffmpeg -v error -y -i "$f" -af "$TRIM" "$tmp" || true
	dur=$("$FFPROBE" -v error -show_entries format=duration -of csv=p=0 "$tmp" 2>/dev/null || echo 0)
	rm -f "$tmp"
	if [ -z "$dur" ] || [ "$dur" = "N/A" ] || awk -v d="$dur" 'BEGIN { exit !(d <= 0.05) }'; then
		printf '%-4s %7s  (%s is silent or unreadable)  %s\n' "$id" "$start" "$f" "$text"
		continue
	fi
	tempo=$(awk -v d="$dur" -v w="$win" -v m="$MAX_TEMPO" 'BEGIN { t = 1; if (d > w && w > 0) { t = d / w; if (t > m) t = m } printf "%.3f", t }')
	note=""
	if awk -v d="$dur" -v t="$tempo" -v w="$win" 'BEGIN { exit !(d / t > w + 0.05) }'; then
		note="  TOO LONG: make this line again, shorter or a bit faster"
		late=$((late + 1))
	fi
	printf '%-4s %7.2f %7.2f %7.2f %6s  %s%s\n' "$id" "$start" "$dur" "$win" "$tempo" "$text" "$note"
	ms=$(awk -v s="$start" 'BEGIN { printf "%d", s * 1000 }')
	inputs+=(-i "$f")
	# Input 0 is the silent base, the length of the video; the lines follow it.
	chains+="[$((n + 1)):a]$TRIM,atempo=$tempo,aformat=sample_rates=48000:channel_layouts=stereo,adelay=${ms}|${ms}[v$n];"
	labels+="[v$n]"
	n=$((n + 1))
done < vo_lines.tsv

if [ "$n" -eq 0 ]; then
	echo "no lines found in $DIR" >&2
	exit 1
fi
mkdir -p "$(dirname "$OUT")"
ffmpeg -v error -y -f lavfi -t "$TOTAL" -i "anullsrc=r=48000:cl=stereo" "${inputs[@]}" \
	-filter_complex "${chains}[0:a]${labels}amix=inputs=$((n + 1)):normalize=0:duration=first[a]" \
	-map "[a]" -ar 48000 -ac 2 "$OUT"
echo "wrote $OUT ($n lines, $TOTAL s)"
if [ "$late" -ne 0 ]; then
	echo "$late line(s) too long for their window"
fi
