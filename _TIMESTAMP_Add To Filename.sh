#!/bin/zsh

set -u

if (( $# == 0 )); then
  /usr/bin/osascript -e 'display notification "Select one or more files or folders in Finder." with title "_TIMESTAMP_Add To Filename"'
  exit 0
fi

timestamp="$(/bin/date '+%y%m%d-%H%M')"
renamed=0
skipped=0

for item in "$@"; do
  if [[ ! -e "$item" && ! -L "$item" ]]; then
    (( skipped++ ))
    continue
  fi

  folder="${item:h}"
  name="${item:t}"
  stem="$name"
  extension=""

  if [[ ! -d "$item" && "$name" == *.* && "$name" != .* ]]; then
    stem="${name%.*}"
    extension=".${name##*.}"
  fi

  target="$folder/$stem-$timestamp$extension"
  counter=2
  while [[ -e "$target" || -L "$target" ]]; do
    target="$folder/$stem-$timestamp-$counter$extension"
    (( counter++ ))
  done

  if /bin/mv -n "$item" "$target" && [[ ! -e "$item" && ! -L "$item" ]]; then
    (( renamed++ ))
  else
    (( skipped++ ))
  fi
done

/usr/bin/osascript - "$renamed" "$skipped" <<'APPLESCRIPT'
on run argv
  set renamedCount to item 1 of argv
  set skippedCount to item 2 of argv
  display notification ("Renamed " & renamedCount & " item(s); skipped " & skippedCount & ".") with title "_TIMESTAMP_Add To Filename"
end run
APPLESCRIPT
