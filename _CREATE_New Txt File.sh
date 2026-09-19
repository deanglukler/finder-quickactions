#!/bin/zsh

set -euo pipefail
setopt noclobber

if (( $# != 1 )); then
  /usr/bin/osascript -e 'display notification "Select exactly one file or folder in Finder." with title "_CREATE_New Txt File"'
  exit 0
fi

item="$1"
if [[ -d "$item" ]]; then
  folder="$item"
elif [[ -f "$item" ]]; then
  folder="${item:h}"
else
  /usr/bin/osascript -e 'display notification "The selected item could not be found." with title "_CREATE_New Txt File"'
  exit 1
fi

base="$(/bin/date '+%y%m%d-%H%M')"
target="$folder/$base.txt"
counter=2
while [[ -e "$target" ]]; do
  target="$folder/$base $counter.txt"
  (( counter++ ))
done

: > "$target"
/usr/bin/open -a TextEdit "$target"
