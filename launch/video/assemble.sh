#!/usr/bin/env bash
# Cut the Yeetfleet demo video together: 1920x1080, 60 fps, H.264, in two
# versions. Both have the game's own sounds in the gameplay and the UI sound
# effects on every animated part (render_scenes.sh --sfx).
#
#   bash launch/video/assemble.sh   -> launch/video/out/yeetfleet_demo.mp4        (no music: for your own)
#   ONLY="wallet shop" bash launch/video/assemble.sh   (remake just those segments, then join)
#                                      launch/video/out/yeetfleet_demo_music.mp4  (the game's songs, music.mjs)
#
# Inputs:
#   launch/video/takes/<take>.mp4        gameplay (render_takes.sh), 2400x1080
#   launch/video/out/scenes/<scene>.*    the animated parts (render_scenes.sh)
#   launch/video/clips/<slot>.mp4        YOUR phone recordings (scrcpy). Until
#                                        one is there its slot shows a
#                                        placeholder. Any length or shape: it
#                                        is fitted into the phone's screen and
#                                        sped up (up to MAX_SPEED, 8x) to the
#                                        slot's length, so none of it is cut
#                                        off; shorter ones hold their last
#                                        frame. It keeps its sound.
# Slots: wallet (9 s), daily (10 s), board (5 s), shop (10 s). The captions
# over each are timed in scenes.html (SLOTS); docs/demo-script.md says what
# to film for each.
set -euo pipefail
cd "$(dirname "$0")"
OUT=out
SC=$OUT/scenes
SEG=$OUT/seg
mkdir -p "$SEG" clips
# The phone's screen in the frame (scenes.html HOLE).
HX=160; HY=64; HW=1600; HH=720
ENC=(-c:v libx264 -preset medium -crf 16 -pix_fmt yuv420p -r 60 -c:a aac -b:a 192k -ar 48000 -ac 2)

dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
# A scene's sound effects (render_scenes.sh writes them).
fx() {
	[ -f "$SC/$1.sfx.wav" ] || { echo "no $SC/$1.sfx.wav: run bash launch/video/render_scenes.sh --sfx" >&2; exit 1; }
	echo "$SC/$1.sfx.wav"
}

# A full-frame scene, with its sound effects.
full() {
	local name=$1 out=$2
	[ $SKIP = 1 ] && return 0
	ffmpeg -v error -y -i "$SC/$name.mp4" -i "$(fx "$name")" \
		-map 0:v -map 1:a -shortest "${ENC[@]}" "$out"
}

# An overlay scene over a gameplay take from [start] s, with the take's sound
# and the overlay's sound effects.
over() {
	local name=$1 take=$2 start=$3 out=$4
	[ $SKIP = 1 ] && return 0
	local d; d=$(dur "$SC/$name.color.mp4")
	ffmpeg -v error -y -ss "$start" -t "$d" -i "takes/$take.mp4" -i "$SC/$name.color.mp4" -i "$SC/$name.mask.mp4" -i "$(fx "$name")" \
		-filter_complex "color=c=black:s=1920x1080:r=60:d=$d[bg];[0:v]scale=$HW:$HH:flags=lanczos,setpts=PTS-STARTPTS[g];[bg][g]overlay=$HX:$HY[b];[1:v][2:v]alphamerge[o];[b][o]overlay=0:0[v];[0:a]asetpts=PTS-STARTPTS,volume=0.85,afade=t=in:d=0.08,afade=t=out:st=$(awk "BEGIN{print $d - 0.12}"):d=0.12[ga];[ga][3:a]amix=inputs=2:normalize=0:duration=first[a]" \
		-map "[v]" -map "[a]" -t "$d" "${ENC[@]}" "$out"
}

# When Phantom's pop-up is on the phone (its portrait sheet, black either side
# of it in the landscape recording), as a ffmpeg enable expression in the slot's
# own seconds ($2 = the speed-up). Empty when it never is.
stamp_enable() {
	ffmpeg -v error -i "$1" -vf "fps=5,crop=700:1080:0:0,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" -an -f null - |
		awk -v f="$2" '
		function emit() { if (e - s >= 1.0) { printf "%sbetween(t,%.3f,%.3f)", (n++ ? "+" : ""), s / f, e / f } }
		/pts_time/ { split($0, a, "pts_time:"); t = a[2] + 0 }
		/YAVG/ { split($0, b, "="); y = b[2] + 0
			if (y < 22) { if (!on) { s = t; on = 1 } e = t + 0.2 } else if (on) { on = 0; emit() } }
		END { if (on) emit() }'
}

# A phone slot: your clip if it's in clips/, else the placeholder still.
slot() {
	local name=$1 out=$2
	[ $SKIP = 1 ] && return 0
	local d; d=$(dur "$SC/slot_$name.color.mp4")
	local clip="clips/$name.mp4"
	if [ -f "$clip" ]; then
		# A clip longer than the slot is sped up to fit (at most MAX_SPEED, 8x).
		local cd f at
		cd=$(dur "$clip")
		f=$(awk "BEGIN{f=$cd/$d; if (f<1) f=1; if (f>${MAX_SPEED:-8}) f=${MAX_SPEED:-8}; printf \"%.4f\", f}")
		at="atempo=1"
		awk "BEGIN{exit !($f>2)}" && at="atempo=2,atempo=$(awk "BEGIN{printf \"%.4f\", $f/2}")" || at="atempo=$f"
		echo "    (your clip: $clip, ${cd}s -> ${d}s at ${f}x)"
		local fit="scale=$HW:$HH:force_original_aspect_ratio=decrease:flags=lanczos,pad=$HW:$HH:(ow-iw)/2:(oh-ih)/2:black,setsar=1,setpts=PTS/$f,fps=60"
		local audio="[0:a]$at,apad,atrim=0:$d,asetpts=PTS-STARTPTS[ca];[ca][3:a]amix=inputs=2:normalize=0:duration=first[a]"
		ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$clip" | grep -q . || audio="[3:a]atrim=0:$d[a]"
		# Phantom's sheet is small in a landscape recording: while it is up it is
		# also pasted over the phone as a big tilted paper stamp.
		local en; en=$(stamp_enable "$clip" "$f")
		local stamp="[b][o]overlay=0:0[v]"
		local src="[0:v]$fit"
		if [ -n "$en" ]; then
			echo "    (phantom stamp: $en)"
			src="[0:v]split=2[c1][c2];[c1]$fit"
			stamp="[b][o]overlay=0:0[v0];[c2]crop=480:780:964:300,scale=468:760:flags=lanczos,setsar=1,setpts=PTS/$f,fps=60,tpad=stop_mode=clone:stop_duration=$d,trim=0:$d,setpts=PTS-STARTPTS,pad=iw+28:ih+28:14:14:color=0xf3ead6,pad=iw+14:ih+14:7:7:color=0x15101f,format=rgba,rotate=a=-0.035:ow=rotw(-0.035):oh=roth(-0.035):c=none,split[s1][s2];[s2]colorchannelmixer=rr=0:gg=0:bb=0:aa=0.5[sh];[v0][sh]overlay=x=(W-w)/2+16:y=$HY+$HH/2-h/2+16:enable='$en'[v1];[v1][s1]overlay=x=(W-w)/2:y=$HY+$HH/2-h/2:enable='$en'[v]"
		fi
		ffmpeg -v error -y -i "$clip" -i "$SC/slot_$name.color.mp4" -i "$SC/slot_$name.mask.mp4" -i "$(fx "slot_$name")" \
			-filter_complex "color=c=black:s=1920x1080:r=60:d=$d[bg];$src,tpad=stop_mode=clone:stop_duration=$d,trim=0:$d,setpts=PTS-STARTPTS[g];[bg][g]overlay=$HX:$HY[b];[1:v][2:v]alphamerge[o];$stamp;$audio" \
			-map "[v]" -map "[a]" -t "$d" "${ENC[@]}" "$out"
	else
		ffmpeg -v error -y -loop 1 -framerate 60 -t "$d" -i "$SC/ph_${name}_0.png" -i "$SC/slot_$name.color.mp4" -i "$SC/slot_$name.mask.mp4" \
			-i "$(fx "slot_$name")" \
			-filter_complex "[1:v][2:v]alphamerge[o];[0:v][o]overlay=0:0[v]" \
			-map "[v]" -map 3:a -t "$d" "${ENC[@]}" "$out"
	fi
}

# The studio splash from the intro take, the phone's 20:9 letterboxed on black.
splash() {
	local out=$1 d=$2
	[ $SKIP = 1 ] && return 0
	ffmpeg -v error -y -t "$d" -i takes/intro.mp4 \
		-vf "scale=1920:864:flags=lanczos,pad=1920:1080:0:108:black,setsar=1" \
		-af "afade=t=out:st=$(awk "BEGIN{print $d - 0.15}"):d=0.15" "${ENC[@]}" "$out"
}

# The cut. Gameplay in-points were picked from the takes' contact sheets.
LIST=$SEG/list.txt
: > "$LIST"
n=0
# The next segment's file, into $F (and the join list). With ONLY="title end"
# (segment names), the others are kept as they are if already made.
SKIP=0
seg() {
	n=$((n + 1)); F=$(printf "%s/%02d_%s.mp4" "$SEG" "$n" "$1"); echo "file '$(basename "$F")'" >> "$LIST"
	SKIP=0
	[ -n "${ONLY:-}" ] && [[ " $ONLY " != *" $1 "* ]] && [ -f "$F" ] && SKIP=1
	[ $SKIP = 1 ] && echo "--- $(basename "$F") (kept)" || echo "--- $(basename "$F")"
}

seg splash; splash "$F" "${SPLASH_LEN:-1.4}"
seg hook; over hook boss "${HOOK_IN:-8.5}" "$F"
seg title; full title "$F"
seg play; over play fight "${PLAY_IN:-3.5}" "$F"
seg home; over home intro "${HOME_IN:-6.5}" "$F"
seg wallet; slot wallet "$F"
seg daily; full daily "$F"
seg daily_phone; slot daily "$F"
seg ranked; over ranked swarm "${RANKED_IN:-6.0}" "$F"
seg board; slot board "$F"
seg skr; full skr "$F"
seg shop; slot shop "$F"
seg arch; full arch "$F"
seg seeker; full seeker "$F"
seg end; full end "$F"

echo "--- joining"
ffmpeg -v error -y -f concat -safe 0 -i "$LIST" -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -r 60 \
	-c:a aac -b:a 192k -movflags +faststart "$OUT/yeetfleet_demo.mp4"
ls -la "$OUT/yeetfleet_demo.mp4"
echo "length: $(dur "$OUT/yeetfleet_demo.mp4") s"

# Where each segment starts, for the songs' cuts (music.mjs).
t=0
: > "$SEG/times.txt"
while read -r _ f; do
	f=${f//\'/}
	d=$(dur "$SEG/$f")
	name=${f#*_}
	echo "${name%.mp4} $t $d" >> "$SEG/times.txt"
	t=$(awk "BEGIN{print $t + $d}")
done < "$LIST"
echo "--- checking that the win fanfare isn't in the cut"
node nowin_check.mjs "$OUT/yeetfleet_demo.mp4"
echo "--- the music version"
node music.mjs "$SEG/times.txt" "$OUT/yeetfleet_demo.mp4" "$OUT/yeetfleet_demo_music.mp4"
ls -la "$OUT/yeetfleet_demo_music.mp4"
