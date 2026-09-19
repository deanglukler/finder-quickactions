#!/bin/zsh

set -u

action_name="_OPEN_In Zed"

notify() {
  if [[ "${QUICK_ACTION_SUPPRESS_NOTIFICATIONS:-0}" != "1" ]]; then
    /usr/bin/osascript - "$1" "$action_name" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
  fi
}

find_zed_cli() {
  local candidate

  if [[ -n "${QUICK_ACTION_ZED_CLI:-}" && -x "$QUICK_ACTION_ZED_CLI" ]]; then
    /usr/bin/printf '%s' "$QUICK_ACTION_ZED_CLI"
    return 0
  fi

  for candidate in \
    "/Applications/Zed.app/Contents/MacOS/cli" \
    "$HOME/Applications/Zed.app/Contents/MacOS/cli" \
    "/opt/homebrew/bin/zed" \
    "/usr/local/bin/zed"; do
    if [[ -x "$candidate" ]]; then
      /usr/bin/printf '%s' "$candidate"
      return 0
    fi
  done

  candidate="$(command -v zed 2>/dev/null || true)"
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  /usr/bin/printf '%s' "$candidate"
}

if (( $# == 0 )); then
  notify "Select one folder or one or more files in Finder."
  exit 0
fi

folder_count=0
file_count=0
paths=()

for selected in "$@"; do
  if [[ -d "$selected" ]]; then
    (( folder_count++ ))
  elif [[ -f "$selected" ]]; then
    (( file_count++ ))
  else
    notify "Every selected item must be an existing file or folder."
    exit 0
  fi
  paths+=("${selected:A}")
done

if (( folder_count == 1 && file_count == 0 && $# == 1 )); then
  :
elif (( folder_count == 0 && file_count >= 1 )); then
  :
else
  notify "Select either one folder or one or more files."
  exit 0
fi

ZED_CLI="$(find_zed_cli)" || {
  notify "Zed could not be found. Install it with: brew install --cask zed"
  exit 0
}

if [[ "${QUICK_ACTION_ZED_SYNCHRONOUS:-0}" == "1" ]]; then
  "$ZED_CLI" "${paths[@]}"
else
  "$ZED_CLI" "${paths[@]}" >/dev/null 2>&1 &!
fi
