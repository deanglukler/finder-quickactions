#!/bin/zsh

set -u

if (( $# != 1 )); then
  /usr/bin/osascript -e 'display notification "Select exactly one file or folder in Finder." with title "_COPY..."'
  exit 0
fi

choice="$(/usr/bin/osascript <<'APPLESCRIPT'
set choices to {"Copy Filename With Extension", "Copy As Markdown Link", "Copy Path Surrounded With Backticks"}
set picked to choose from list choices with title "_COPY..." with prompt "Choose what to copy:" default items {"Copy Filename With Extension"} OK button name "Copy" cancel button name "Cancel"
if picked is false then return ""
return item 1 of picked
APPLESCRIPT
)" || exit 0

case "$choice" in
  "Copy Filename With Extension")
    /usr/bin/printf '%s' "${1:t}" | /usr/bin/pbcopy
    ;;
  "Copy As Markdown Link")
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
    /usr/bin/printf '`%s`' "$1" | /usr/bin/pbcopy
    ;;
esac
