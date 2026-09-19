#!/bin/zsh

set -u

action_name="_FOLDER..."
moved_count=0
copied_count=0
deleted_count=0
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

unique_path() {
  local directory="$1"
  local filename="$2"
  local stem="$filename"
  local extension=""
  local number=2
  local candidate

  if [[ "$filename" == *.* && "$filename" != .* ]]; then
    stem="${filename%.*}"
    extension=".${filename##*.}"
  fi

  candidate="$directory/$filename"
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$directory/$stem $number$extension"
    (( number++ ))
  done

  /usr/bin/printf '%s' "$candidate"
}

unique_folder() {
  local parent="$1"
  local name="$2"
  local candidate="$parent/$name"
  local number=2

  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$parent/$name $number"
    (( number++ ))
  done

  /usr/bin/printf '%s' "$candidate"
}

remove_empty_descendants() {
  local root="$1"
  local directory

  while IFS= read -r -d '' directory; do
    if /bin/rmdir "$directory" 2>/dev/null; then
      (( deleted_count++ ))
    fi
  done < <(/usr/bin/find "$root" -depth -mindepth 1 -type d -print0)
}

flatten_in_place() {
  local root="$1"
  local source
  local destination

  while IFS= read -r -d '' source; do
    destination="$(unique_path "$root" "${source:t}")"
    if /bin/mv "$source" "$destination"; then
      (( moved_count++ ))
    else
      (( skipped_count++ ))
    fi
  done < <(/usr/bin/find "$root" -mindepth 2 ! -type d -print0)

  remove_empty_descendants "$root"
}

flatten_as_duplicate() {
  local root="$1"
  local parent="${root:h}"
  local duplicate
  local source
  local destination

  duplicate="$(unique_folder "$parent" "${root:t} Flattened")"
  if ! /bin/mkdir "$duplicate"; then
    (( skipped_count++ ))
    return
  fi

  while IFS= read -r -d '' source; do
    destination="$(unique_path "$duplicate" "${source:t}")"
    if /bin/cp -pP "$source" "$destination"; then
      (( copied_count++ ))
    else
      (( skipped_count++ ))
    fi
  done < <(/usr/bin/find "$root" -mindepth 1 ! -type d -print0)
}

if (( $# == 0 )); then
  notify "Select one or more folders in Finder."
  exit 0
fi

for selected in "$@"; do
  if [[ ! -d "$selected" ]]; then
    notify "Every selected item must be a folder."
    exit 0
  fi
done

choice="${QUICK_ACTION_FOLDER_CHOICE:-}"
if [[ -z "$choice" ]]; then
  choice="$(/usr/bin/osascript <<'APPLESCRIPT'
set choices to {"Flatten Folder In Place", "Flatten Folder As Duplicate", "Delete All Empty Folders"}
set picked to choose from list choices with title "_FOLDER..." with prompt "Choose a folder action:" default items {"Flatten Folder In Place"} OK button name "Run" cancel button name "Cancel"
if picked is false then return ""
return item 1 of picked
APPLESCRIPT
)" || exit 0
fi

case "$choice" in
  "Flatten Folder In Place")
    for selected in "$@"; do
      flatten_in_place "${selected:A}"
    done
    notify "Moved $moved_count file(s), removed $deleted_count empty folder(s), and skipped $skipped_count item(s)."
    ;;
  "Flatten Folder As Duplicate")
    for selected in "$@"; do
      flatten_as_duplicate "${selected:A}"
    done
    notify "Copied $copied_count file(s) and skipped $skipped_count item(s)."
    ;;
  "Delete All Empty Folders")
    for selected in "$@"; do
      remove_empty_descendants "${selected:A}"
    done
    notify "Removed $deleted_count empty folder(s)."
    ;;
  *)
    notify "No folder action was selected."
    ;;
esac
