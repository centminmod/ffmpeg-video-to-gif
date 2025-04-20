#!/bin/zsh
# Wrapper script for H.264 (CRF 29) conversion via vid2gif_pro
crf=29
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
source "$HOME/.my_scripts/vid2gif_func.sh"

for f in "$@"
do
  dir=$(dirname "$f")
  filename_with_ext=$(basename "$f")
  base="${filename_with_ext%.*}"
  target_filename="${base}-h264_crf${crf}.mp4"
  target_path="${dir}/${target_filename}"

  vid2gif_pro --src "$f" --to-mp4-h264 --crf ${crf} --target "$target_path"
done