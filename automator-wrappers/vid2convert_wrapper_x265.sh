#!/bin/zsh
# Wrapper script for H.265 conversion via vid2gif_pro

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
source "$HOME/.my_scripts/vid2gif_func.sh"

for f in "$@"
do
  # --- Prepare output path ---
  dir=$(dirname "$f")
  filename_with_ext=$(basename "$f")
  base="${filename_with_ext%.*}"
  # Define output filename
  target_filename="${base}-h265_crf31.mp4"
  target_path="${dir}/${target_filename}"

  # --- Execute conversion ---
  vid2gif_pro --src "$f" --to-mp4-h265 --crf 31 --target "$target_path"
done