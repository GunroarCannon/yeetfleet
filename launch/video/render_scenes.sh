#!/usr/bin/env bash
# Render every animated part of the demo video (scenes.html) for assemble.sh:
# full-frame scenes to H.264, overlays to a colour + mask pair, the slot
# placeholders to stills; and each scene's sound effects (its cues, mixed by
# sfx.mjs from the game's own sounds) to <scene>.sfx.wav.
#
#   bash launch/video/render_scenes.sh [scene ...]         (default: all)
#   bash launch/video/render_scenes.sh --sfx [scene ...]   (only the sounds: seconds, no frames)
set -euo pipefail
cd "$(dirname "$0")/../.."
SC=launch/video/out/scenes
mkdir -p "$SC"
SFX_ONLY=0
[ "${1:-}" = "--sfx" ] && { SFX_ONLY=1; shift; }
FULL=" title daily skr arch seeker end "
OVER=" hook play home ranked slot_wallet slot_daily slot_board slot_shop "
STILL=" ph_wallet ph_daily ph_board ph_shop "
ALL=($FULL $OVER $STILL)
[ $# -gt 0 ] && ALL=("$@")
sounds() {
	node launch/video/render.mjs "$1" "$SC/$1.cues.json" --cues
	node launch/video/sfx.mjs "$SC/$1.cues.json" "$SC/$1.sfx.wav"
}
for s in "${ALL[@]}"; do
	if [[ "$FULL" == *" $s "* ]]; then
		[ $SFX_ONLY = 1 ] || node launch/video/render.mjs "$s" "$SC/$s.mp4"
		sounds "$s"
	elif [[ "$OVER" == *" $s "* ]]; then
		[ $SFX_ONLY = 1 ] || node launch/video/render.mjs "$s" "$SC/$s.alpha"
		sounds "$s"
	elif [[ "$STILL" == *" $s "* ]]; then
		[ $SFX_ONLY = 1 ] || node launch/video/render.mjs "$s" "$SC/$s.png" --at 0
	else
		echo "unknown scene $s" >&2
		exit 1
	fi
done
