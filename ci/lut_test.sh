#!/bin/bash
# GPU (--lut) and CPU (video filter) LUT paths of luts.lua must give the same
# picture through the included S-Log3 S-Gamut3.Cine LUT: S-Log3 18% grey
# (10 bit code 420, left half; about 102 in Rec.709) and a brighter grey
# (code 700, right half). Usage: lut_test.sh <mpv> <repo dir>
# Needs an X server (xvfb-run) and ffmpeg.
set -euo pipefail
mpv=$1
repo=$(cd "$2" && pwd)
work=$(mktemp -d)
[ -n "${KEEP:-}" ] || trap 'rm -rf "$work"' EXIT

# 10 bit limited range BT.709: Y=420 | Y=700, Cb=Cr=512.
python3 -c "
import struct,sys
w,h=320,240
y=(struct.pack('<H',420)*(w//2)+struct.pack('<H',700)*(w//2))*h
c=struct.pack('<H',512)*(w*h//4)
sys.stdout.buffer.write((y+c+c)*5)" |
    ffmpeg -loglevel error -f rawvideo -pix_fmt yuv420p10le -s 320x240 -r 25 -i - \
        -c:v ffv1 -color_range tv -colorspace bt709 -color_primaries bt709 \
        -color_trc bt709 "$work/grey.mkv"

mkdir -p "$work/cfg/scripts"
cp "$repo/scripts/luts.lua" "$work/cfg/scripts/"
ln -s "$repo/luts" "$work/cfg/luts"
echo "Sony/S-Log3 S-Gamut3.Cine to Rec709.cube" > "$work/cfg/luts.state"

shot() { # <name> <mpv args...>
    local name=$1; shift
    SHOT="$work/$name.png" timeout 60 "$mpv" --no-config --config-dir="$work/cfg" \
        --config=yes --load-scripts=yes --script="$repo/ci/lut_shot.lua" \
        --vo=gpu-next --gpu-api=opengl --gpu-context=x11egl --gpu-sw \
        --pause --geometry=320x240 --ao=null --osc=no --osd-level=0 \
        "$@" "$work/grey.mkv" 2>&1 | tee "$work/$name.log"
    if grep -E "Lua error|Failed parsing LUT|Could not load" "$work/$name.log"; then
        echo "::error::$name: LUT not loaded"; exit 1
    fi
    # Grey level (R) in the middle of the left and the right half.
    for x in 'iw/4' 'iw*3/4'; do
        ffmpeg -loglevel error -i "$work/$name.png" -vf "crop=1:1:$x:ih/2" \
            -f rawvideo -pix_fmt rgb24 - | od -An -tu1 | awk '{print $1}'
    done | paste -sd' '
}

absdiff() { echo $(( $1 > $2 ? $1 - $2 : $2 - $1 )); }

read -r gpu1 gpu2 < <(shot gpu --script-opts=luts-mode=gpu | tail -1)
grep -q "LUTPROP=.*S-Log3 S-Gamut3.Cine to Rec709.cube" "$work/gpu.log" ||
    { echo "::error::--lut is not set in GPU mode"; exit 1; }
read -r cpu1 cpu2 < <(shot cpu --script-opts=luts-mode=cpu | tail -1)
read -r none1 none2 < <(shot none --script-opts=luts-remember=no | tail -1)
echo "grey 18%: gpu=$gpu1 cpu=$cpu1; bright: gpu=$gpu2 cpu=$cpu2 without LUT=$none2"
if [ "$(absdiff "$gpu1" 102)" -gt 3 ] || [ "$(absdiff "$gpu1" "$cpu1")" -gt 3 ] ||
   [ "$(absdiff "$gpu2" "$cpu2")" -gt 3 ] || [ "$(absdiff "$gpu2" "$none2")" -lt 10 ]; then
    echo "::error::LUT results are wrong: GPU and CPU differ, or 18% grey is not about 102"
    exit 1
fi
