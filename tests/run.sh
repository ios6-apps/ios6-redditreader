#!/bin/bash
# Builds and runs the tests natively on macOS; exits non-zero if anything fails.
#   tests/mux_test.c   the MP4 joiner (src/RRMux.c) on small synthetic fragmented files
#   tests/feed_test.m  Atom feed parsing, link classification, subreddit names, text helpers (Foundation only, UIKit shimmed)
# When ffmpeg is installed there is also an end-to-end check: real H.264 + AAC fragmented files are joined and the result must decode.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/tests
mkdir -p "$OUT"

cc -std=c99 -Wall -Wextra -Wno-unused-parameter -o "$OUT/mux_test" tests/mux_test.c src/RRMux.c
cc -std=c99 -Wall -o "$OUT/mux_cli" tools/mux_cli.c src/RRMux.c
clang -fobjc-arc -Wall -Wno-deprecated-declarations -Itests/shim -Isrc -framework Foundation -framework CoreGraphics \
    tests/feed_test.m src/RRText.m -o "$OUT/feed_test"

(cd "$OUT" && ./mux_test)
"$OUT/feed_test"

if command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null && ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libx264; then
    T=$(mktemp -d)
    trap 'rm -rf "$T"' EXIT
    FRAG=(-movflags frag_keyframe+empty_moov+default_base_moof)
    ffmpeg -loglevel error -y -f lavfi -i testsrc=size=320x240:rate=25:duration=3 -c:v libx264 -bf 2 -g 25 "${FRAG[@]}" "$T/v.mp4"
    ffmpeg -loglevel error -y -f lavfi -i sine=frequency=440:duration=3 -c:a aac "${FRAG[@]}" "$T/a.mp4"
    "$OUT/mux_cli" "$T/v.mp4" "$T/a.mp4" "$T/out.mp4"
    streams=$(ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "$T/out.mp4" | sort | tr '\n' ' ')
    [ "$streams" = "audio video " ] || { echo "ffmpeg check: expected one audio and one video stream, got: $streams"; exit 1; }
    ffmpeg -v error -i "$T/out.mp4" -f null - || { echo "ffmpeg check: the joined file does not decode"; exit 1; }
    frames=$(ffprobe -v error -count_frames -select_streams v -show_entries stream=nb_read_frames -of csv=p=0 "$T/out.mp4")
    [ "$frames" = 75 ] || { echo "ffmpeg check: expected 75 video frames, got $frames"; exit 1; }
    echo "ffmpeg end-to-end check: ok"
else
    echo "ffmpeg with libx264 not found: skipping the end-to-end mux check"
fi
echo "all tests passed"
