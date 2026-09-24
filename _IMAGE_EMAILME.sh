#!/bin/zsh

set -u

action_name="_IMAGE_EMAILME"
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

find_magick() {
  local candidate

  if [[ -n "${QUICK_ACTION_MAGICK_OVERRIDE:-}" ]]; then
    [[ -x "$QUICK_ACTION_MAGICK_OVERRIDE" ]] || return 1
    /usr/bin/printf '%s' "$QUICK_ACTION_MAGICK_OVERRIDE"
    return 0
  fi

  for candidate in /opt/homebrew/bin/magick /usr/local/bin/magick; do
    if [[ -x "$candidate" ]]; then
      /usr/bin/printf '%s' "$candidate"
      return 0
    fi
  done

  candidate="$(command -v magick 2>/dev/null || true)"
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

  candidate="$directory/$stem-EMAILME.jpg"
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$directory/$stem-EMAILME $number.jpg"
    (( number++ ))
  done

  /usr/bin/printf '%s' "$candidate"
}

if (( $# == 0 )); then
  notify "Select one or more images in Finder."
  exit 0
fi

MAGICK="$(find_magick)" || {
  notify "ImageMagick is required. Run z_quickaction.health to install it."
  exit 1
}

for source in "$@"; do
  if [[ ! -f "$source" ]]; then
    (( skipped_count++ ))
    continue
  fi

  source="${source:A}"
  destination="$(unique_output_path "$source")"
  if "$MAGICK" "$source" \
    -auto-orient \
    -colorspace sRGB \
    -resize '1280x1280>' \
    -background white \
    -alpha remove \
    -alpha off \
    -strip \
    -sampling-factor 4:2:0 \
    -interlace Plane \
    -quality 80 \
    "$destination" >/dev/null 2>&1; then
    (( converted_count++ ))
  else
    [[ -e "$destination" ]] && /bin/rm -f "$destination"
    (( skipped_count++ ))
  fi
done

notify "Created $converted_count email-ready photo(s) and skipped $skipped_count item(s)."

(( converted_count > 0 ))
