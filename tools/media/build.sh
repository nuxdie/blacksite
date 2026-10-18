#!/usr/bin/env bash
# Turn a --media capture into the README's images:
#   godot --path . -- --media=/tmp/media && tools/media/build.sh /tmp/media
# Stills become 1280-wide JPEGs (PNG where there is UI text), clips become 800-wide GIFs.
set -euo pipefail
src="${1:?capture dir}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/docs/media"
mkdir -p "$out"
for f in "$src"/*.png; do
    name="$(basename "$f" .png)"
    case "$name" in
        title|deck) ffmpeg -loglevel error -y -i "$f" -vf "scale=1280:-1:flags=lanczos" "$out/$name.png" ;;
        *) ffmpeg -loglevel error -y -i "$f" -vf "scale=1280:-1:flags=lanczos" -q:v 3 "$out/$name.jpg" ;;
    esac
done
for d in "$src"/*/; do
    name="$(basename "$d")"
    ffmpeg -loglevel error -y -framerate 20 -i "$d/%04d.png" \
        -vf "fps=12,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
        "$out/$name.gif"
done
python3 "$root/tools/media/banner.py"
ls -la "$out"
