#!/bin/zsh

set -u

if (( $# == 0 )); then
  /usr/bin/osascript -e 'display notification "No Finder items were selected." with title "_COPY_Copy Full Path"'
  exit 0
fi

{
  /usr/bin/printf '%s' "$1"
  shift
  for path in "$@"; do
    /usr/bin/printf '\n%s' "$path"
  done
} | /usr/bin/pbcopy
