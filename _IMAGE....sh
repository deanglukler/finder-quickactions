#!/bin/zsh

set -u

action_name="_IMAGE..."
converted_count=0
skipped_count=0
EXIFTOOL_USE_PERL=0

notify() {
  if [[ "${QUICK_ACTION_SUPPRESS_NOTIFICATIONS:-0}" != "1" ]]; then
    /usr/bin/osascript - "$1" "$action_name" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
  fi
}

find_tool() {
  local name="$1"
  local candidate

  for candidate in "/opt/homebrew/bin/$name" "/usr/local/bin/$name"; do
    if [[ -x "$candidate" ]]; then
      /usr/bin/printf '%s' "$candidate"
      return 0
    fi
  done

  candidate="$(command -v "$name" 2>/dev/null || true)"
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  /usr/bin/printf '%s' "$candidate"
}

split_filename() {
  local filename="$1"
  FILE_STEM="$filename"
  FILE_EXTENSION=""

  if [[ "$filename" == *.* && "$filename" != .* ]]; then
    FILE_STEM="${filename%.*}"
    FILE_EXTENSION=".${filename##*.}"
  fi
}

unique_output_path() {
  local source="$1"
  local suffix="$2"
  local extension="$3"
  local directory="${source:h}"
  local filename="${source:t}"
  local candidate
  local number=2

  split_filename "$filename"
  candidate="$directory/$FILE_STEM$suffix$extension"
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$directory/$FILE_STEM$suffix $number$extension"
    (( number++ ))
  done

  /usr/bin/printf '%s' "$candidate"
}

convert_image() {
  local source="$1"
  local format="$2"
  local max_size="$3"
  local suffix="$4"
  local extension="$5"
  local destination
  local -a arguments

  destination="$(unique_output_path "$source" "$suffix" "$extension")"
  arguments=("$source" -auto-orient -resize "${max_size}x${max_size}>")
  if [[ "$format" == "jpg" || "$format" == "webp" ]]; then
    arguments+=(-quality 85)
  fi
  arguments+=("$destination")

  if "$MAGICK" "${arguments[@]}" >/dev/null 2>&1; then
    (( converted_count++ ))
  else
    [[ -e "$destination" ]] && /bin/rm -f "$destination"
    (( skipped_count++ ))
  fi
}

resize_image() {
  local source="$1"
  local geometry="$2"
  local suffix="$3"
  local filename="${source:t}"
  local destination

  split_filename "$filename"
  destination="$(unique_output_path "$source" "$suffix" "$FILE_EXTENSION")"
  if "$MAGICK" "$source" -auto-orient -resize "$geometry" "$destination" >/dev/null 2>&1; then
    (( converted_count++ ))
  else
    [[ -e "$destination" ]] && /bin/rm -f "$destination"
    (( skipped_count++ ))
  fi
}

remove_metadata() {
  local source="$1"
  local filename="${source:t}"
  local destination

  split_filename "$filename"
  destination="$(unique_output_path "$source" "-no-metadata" "$FILE_EXTENSION")"
  if /bin/cp -pP "$source" "$destination" && run_exiftool -all= -overwrite_original_in_place "$destination" >/dev/null 2>&1; then
    (( converted_count++ ))
  else
    [[ -e "$destination" ]] && /bin/rm -f "$destination"
    (( skipped_count++ ))
  fi
}

run_exiftool() {
  if (( EXIFTOOL_USE_PERL )); then
    /usr/bin/perl "$EXIFTOOL" "$@"
  else
    "$EXIFTOOL" "$@"
  fi
}

if (( $# == 0 )); then
  notify "Select one or more images in Finder."
  exit 0
fi

for source in "$@"; do
  if [[ ! -f "$source" ]]; then
    notify "Every selected item must be an image file."
    exit 0
  fi
done

choice="${QUICK_ACTION_IMAGE_CHOICE:-}"
if [[ -z "$choice" ]]; then
  choice="$(/usr/bin/osascript <<'APPLESCRIPT'
set choices to {"Convert JPG-85-1920px", "Convert JPG-85-960px", "Convert JPG-85-480px", "Convert PNG-1920px", "Convert PNG-960px", "Convert PNG-480px", "Convert WEBP-1920px", "Convert WEBP-960px", "Convert WEBP-480px", "Resize 50 Percent", "Resize 256px Thumbnail", "Remove Metadata"}
set picked to choose from list choices with title "_IMAGE..." with prompt "Choose an image action:" default items {"Convert JPG-85-1920px"} OK button name "Run" cancel button name "Cancel"
if picked is false then return ""
return item 1 of picked
APPLESCRIPT
)" || exit 0
fi

case "$choice" in
  "Convert JPG-85-1920px"|"Convert JPG-85-960px"|"Convert JPG-85-480px"|\
  "Convert PNG-1920px"|"Convert PNG-960px"|"Convert PNG-480px"|\
  "Convert WEBP-1920px"|"Convert WEBP-960px"|"Convert WEBP-480px"|\
  "Resize 50 Percent"|"Resize 256px Thumbnail")
    MAGICK="$(find_tool magick)" || {
      notify "ImageMagick is required. Install it with: brew install imagemagick"
      exit 0
    }
    ;;
  "Remove Metadata")
    EXIFTOOL="$(find_tool exiftool)" || {
      notify "ExifTool is required. Install it with: brew install exiftool"
      exit 0
    }
    if ! "$EXIFTOOL" -ver >/dev/null 2>&1; then
      if [[ -x /usr/bin/perl ]] && /usr/bin/perl "$EXIFTOOL" -ver >/dev/null 2>&1; then
        EXIFTOOL_USE_PERL=1
      else
        notify "ExifTool is installed but cannot run. Reinstall it with: brew reinstall exiftool"
        exit 0
      fi
    fi
    ;;
  *)
    notify "No image action was selected."
    exit 0
    ;;
esac

for source in "$@"; do
  source="${source:A}"
  case "$choice" in
    "Convert JPG-85-1920px") convert_image "$source" jpg 1920 "-JPG-85-1920px" ".jpg" ;;
    "Convert JPG-85-960px")  convert_image "$source" jpg 960  "-JPG-85-960px"  ".jpg" ;;
    "Convert JPG-85-480px")  convert_image "$source" jpg 480  "-JPG-85-480px"  ".jpg" ;;
    "Convert PNG-1920px")    convert_image "$source" png 1920 "-PNG-1920px"    ".png" ;;
    "Convert PNG-960px")     convert_image "$source" png 960  "-PNG-960px"     ".png" ;;
    "Convert PNG-480px")     convert_image "$source" png 480  "-PNG-480px"     ".png" ;;
    "Convert WEBP-1920px")   convert_image "$source" webp 1920 "-WEBP-1920px"  ".webp" ;;
    "Convert WEBP-960px")    convert_image "$source" webp 960  "-WEBP-960px"   ".webp" ;;
    "Convert WEBP-480px")    convert_image "$source" webp 480  "-WEBP-480px"   ".webp" ;;
    "Resize 50 Percent")     resize_image "$source" "50%" "-50-percent" ;;
    "Resize 256px Thumbnail") resize_image "$source" "256x256>" "-256px-thumbnail" ;;
    "Remove Metadata")       remove_metadata "$source" ;;
  esac
done

notify "Created $converted_count image(s) and skipped $skipped_count item(s)."
