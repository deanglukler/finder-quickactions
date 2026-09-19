#!/bin/zsh

set -u

action_name="_VIDEO_Convert to MP4-960px"
converted_count=0
failed_count=0

notify() {
  if [[ "${QUICK_ACTION_SUPPRESS_NOTIFICATIONS:-0}" != "1" ]]; then
    /usr/bin/osascript - "$1" "$action_name" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
  fi
}

find_ffmpeg() {
  local candidate
  for candidate in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
    if [[ -x "$candidate" ]]; then
      /usr/bin/printf '%s' "$candidate"
      return 0
    fi
  done

  candidate="$(command -v ffmpeg 2>/dev/null || true)"
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  /usr/bin/printf '%s' "$candidate"
}

unique_output_path() {
  local source="$1"
  local directory="${source:h}"
  local filename="${source:t}"
  local stem="$filename"
  local candidate
  local number=2

  if [[ "$filename" == *.* && "$filename" != .* ]]; then
    stem="${filename%.*}"
  fi

  candidate="$directory/$stem-960px.mp4"
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$directory/$stem-960px $number.mp4"
    (( number++ ))
  done

  /usr/bin/printf '%s' "$candidate"
}

if (( $# == 0 )); then
  notify "Select one or more video files in Finder."
  exit 0
fi

FFMPEG="$(find_ffmpeg)" || {
  notify "FFmpeg is required. Install it with: brew install ffmpeg"
  exit 0
}

notify "Converting $# video file(s) to 960px MP4."

for source in "$@"; do
  if [[ ! -f "$source" ]]; then
    (( failed_count++ ))
    continue
  fi

  source="${source:A}"
  destination="$(unique_output_path "$source")"
  temporary="${destination:h}/.${destination:t}.quickaction.$$.mp4"

  if "$FFMPEG" \
      -hide_banner -loglevel error -nostdin -y \
      -i "$source" \
      -map 0:v:0 -map '0:a?' \
      -map_metadata 0 \
      -vf "scale='min(960,iw)':'min(960,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2" \
      -c:v libx264 -preset medium -crf 20 \
      -pix_fmt yuv420p \
      -c:a aac -b:a 192k \
      -movflags +faststart \
      "$temporary" && [[ -s "$temporary" ]]; then
    if /bin/mv "$temporary" "$destination"; then
      (( converted_count++ ))
    else
      /bin/rm -f "$temporary"
      (( failed_count++ ))
    fi
  else
    [[ -e "$temporary" ]] && /bin/rm -f "$temporary"
    (( failed_count++ ))
  fi
done

if (( converted_count > 0 )); then
  message="Converted $converted_count video file(s) to 960px MP4."
  if (( failed_count > 0 )); then
    message="$message $failed_count failed."
  fi
  notify "$message"
else
  notify "No MP4 files were created; $failed_count item(s) failed."
fi
