#!/bin/zsh

set -u

notify() {
  if [[ "${QUICK_ACTION_SUPPRESS_NOTIFICATIONS:-0}" != "1" ]]; then
    /usr/bin/osascript - "$1" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title "_COPY..."
end run
APPLESCRIPT
  fi
}

show_conflicts() {
  if [[ "${QUICK_ACTION_SUPPRESS_DIALOGS:-0}" != "1" ]]; then
    /usr/bin/osascript - "$1" <<'APPLESCRIPT'
on run argv
  display dialog "Nothing was copied because these names already exist in the destination:" & return & return & (item 1 of argv) with title "_COPY..." buttons {"OK"} default button "OK"
end run
APPLESCRIPT
  fi
}

if (( $# == 0 )); then
  notify "Select at least one file or folder in Finder."
  exit 0
fi

if [[ -n "${QUICK_ACTION_COPY_CHOICE:-}" ]]; then
  choice="$QUICK_ACTION_COPY_CHOICE"
else
  choice="$(/usr/bin/osascript <<'APPLESCRIPT'
set choices to {"Copy Filename With Extension", "Copy As Markdown Link", "Copy Path Surrounded With Backticks", "Copy Selected To Folder"}
set picked to choose from list choices with title "_COPY..." with prompt "Choose what to copy:" default items {"Copy Filename With Extension"} OK button name "Copy" cancel button name "Cancel"
if picked is false then return ""
return item 1 of picked
APPLESCRIPT
)" || exit 0
fi

case "$choice" in
  "Copy Filename With Extension")
    if (( $# != 1 )); then
      notify "Select exactly one file or folder for this option."
      exit 0
    fi
    /usr/bin/printf '%s' "${1:t}" | /usr/bin/pbcopy
    ;;
  "Copy As Markdown Link")
    if (( $# != 1 )); then
      notify "Select exactly one file or folder for this option."
      exit 0
    fi
    markdown="$(/usr/bin/osascript -l JavaScript - "$1" <<'JXA'
ObjC.import('Foundation');
function run(argv) {
  const url = $.NSURL.fileURLWithPath($(argv[0]));
  const label = ObjC.unwrap(url.lastPathComponent).replace(/[\\\[\]]/g, '\\$&');
  return '[' + label + '](' + ObjC.unwrap(url.absoluteString) + ')';
}
JXA
)" || exit 1
    /usr/bin/printf '%s' "$markdown" | /usr/bin/pbcopy
    ;;
  "Copy Path Surrounded With Backticks")
    if (( $# != 1 )); then
      notify "Select exactly one file or folder for this option."
      exit 0
    fi
    /usr/bin/printf '`%s`' "$1" | /usr/bin/pbcopy
    ;;
  "Copy Selected To Folder")
    if [[ -n "${QUICK_ACTION_COPY_DESTINATION:-}" ]]; then
      destination="$QUICK_ACTION_COPY_DESTINATION"
    else
      destination="$(/usr/bin/osascript <<'APPLESCRIPT'
try
  return POSIX path of (choose folder with prompt "Choose where to copy the selected items:")
on error number -128
  return ""
end try
APPLESCRIPT
)" || exit 0
    fi
    [[ -n "$destination" ]] || exit 0
    [[ -d "$destination" ]] || {
      notify "The selected destination is not a folder."
      exit 1
    }

    destination="${destination%/}"
    [[ -n "$destination" ]] || destination="/"

    typeset -A selected_names
    conflicts=()
    for source in "$@"; do
      name="${source:t}"
      target="$destination/$name"
      if [[ -e "$target" || -L "$target" || -n "${selected_names[$name]-}" ]]; then
        conflicts+=("$name")
      fi
      selected_names[$name]=1
    done

    if (( ${#conflicts[@]} > 0 )); then
      conflict_list="${(j:$'\n':)conflicts}"
      show_conflicts "$conflict_list"
      exit 1
    fi

    for source in "$@"; do
      name="${source:t}"
      if ! /usr/bin/ditto "$source" "$destination/$name"; then
        notify "Copy failed while copying $name."
        exit 1
      fi
    done
    notify "Copied $# item(s) to ${destination:t}."
    ;;
esac
