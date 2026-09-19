#!/bin/zsh

set -u

action_name="_IMAGE_Convert To JPG-85"
converted_count=0
skipped_count=0

notify() {
  if [[ "${QUICK_ACTION_SUPPRESS_NOTIFICATIONS:-0}" != "1" ]]; then
    /usr/bin/osascript - "$1" "$action_name" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
  fi
}

unique_jpg_path() {
  local source="$1"
  local directory="${source:h}"
  local filename="${source:t}"
  local stem="$filename"
  local candidate
  local number=2

  if [[ "$filename" == *.* && "$filename" != .* ]]; then
    stem="${filename%.*}"
  fi

  candidate="$directory/$stem.jpg"
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$directory/$stem $number.jpg"
    (( number++ ))
  done

  /usr/bin/printf '%s' "$candidate"
}

if (( $# == 0 )); then
  notify "Select one or more images in Finder."
  exit 0
fi

for source in "$@"; do
  if [[ ! -f "$source" ]]; then
    (( skipped_count++ ))
    continue
  fi

  destination="$(unique_jpg_path "${source:A}")"
  if /usr/bin/sips -s format jpeg -s formatOptions 85 "$source" --out "$destination" >/dev/null 2>&1; then
    (( converted_count++ ))
  else
    [[ -e "$destination" ]] && /bin/rm -f "$destination"
    (( skipped_count++ ))
  fi
done

notify "Converted $converted_count image(s) and skipped $skipped_count item(s)."
