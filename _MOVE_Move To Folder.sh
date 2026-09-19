#!/bin/zsh

set -u

app_title="_MOVE_Move To Folder"

if (( $# == 0 )); then
  /usr/bin/osascript -e 'display notification "Select one or more files or folders in Finder." with title "_MOVE_Move To Folder"'
  exit 0
fi

if [[ -n "${QUICK_ACTION_MOVE_DESTINATION:-}" ]]; then
  destination="$QUICK_ACTION_MOVE_DESTINATION"
else
  destination="$(/usr/bin/osascript <<'APPLESCRIPT'
try
  return POSIX path of (choose folder with prompt "Move the selected items to:")
on error number -128
  return ""
end try
APPLESCRIPT
)" || exit 0
fi

destination="${destination%/}"
[[ -n "$destination" ]] || exit 0

if [[ ! -d "$destination" ]]; then
  /usr/bin/osascript -e 'display alert "_MOVE_Move To Folder" message "The destination folder could not be found." as critical'
  exit 1
fi

destination="${destination:A}"
moved=0
skipped=0

unique_target() {
  local source="$1"
  local name="${source:t}"
  local stem="$name"
  local extension=""
  local candidate counter=2

  if [[ ! -d "$source" && "$name" == *.* && "$name" != .* ]]; then
    stem="${name%.*}"
    extension=".${name##*.}"
  fi

  candidate="$destination/$name"
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$destination/$stem $counter$extension"
    (( counter++ ))
  done
  /usr/bin/printf '%s' "$candidate"
}

for item in "$@"; do
  if [[ ! -e "$item" && ! -L "$item" ]]; then
    (( skipped++ ))
    continue
  fi

  source="${item:A}"
  source_parent="${source:h}"

  if [[ "$source_parent" == "$destination" ]]; then
    (( skipped++ ))
    continue
  fi

  if [[ -d "$source" && ( "$destination" == "$source" || "$destination" == "$source/"* ) ]]; then
    (( skipped++ ))
    continue
  fi

  target="$(unique_target "$source")"
  if /bin/mv -n "$source" "$target" && [[ ! -e "$source" && ! -L "$source" ]]; then
    (( moved++ ))
  else
    (( skipped++ ))
  fi
done

/usr/bin/osascript - "$app_title" "$moved" "$skipped" <<'APPLESCRIPT'
on run argv
  display notification ("Moved " & item 2 of argv & " item(s); skipped " & item 3 of argv & ".") with title (item 1 of argv)
end run
APPLESCRIPT
