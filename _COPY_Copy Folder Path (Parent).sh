#!/bin/zsh

set -u

if (( $# != 1 )); then
  /usr/bin/osascript -e 'display notification "Select exactly one file or folder in Finder." with title "_COPY_Copy Folder Path (Parent)"'
  exit 0
fi

/usr/bin/printf '%s' "${1:h}" | /usr/bin/pbcopy
