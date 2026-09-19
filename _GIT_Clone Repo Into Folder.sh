#!/bin/zsh

set -u
setopt EXTENDED_GLOB

action_name="_GIT_Clone Repo Into Folder"

notify() {
  if [[ "${QUICK_ACTION_SUPPRESS_NOTIFICATIONS:-0}" != "1" ]]; then
    /usr/bin/osascript - "$1" "$action_name" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
  fi
}

show_error() {
  if [[ "${QUICK_ACTION_SUPPRESS_DIALOGS:-0}" != "1" ]]; then
    /usr/bin/osascript - "$1" "$action_name" <<'APPLESCRIPT'
on run argv
  display alert (item 2 of argv) message (item 1 of argv) as critical buttons {"OK"} default button "OK"
end run
APPLESCRIPT
  fi
}

find_git() {
  local candidate
  for candidate in /opt/homebrew/bin/git /usr/local/bin/git /usr/bin/git; do
    if [[ -x "$candidate" ]]; then
      /usr/bin/printf '%s' "$candidate"
      return 0
    fi
  done

  candidate="$(command -v git 2>/dev/null || true)"
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  /usr/bin/printf '%s' "$candidate"
}

if (( $# != 1 )) || [[ ! -d "$1" ]]; then
  notify "Select exactly one destination folder in Finder."
  exit 0
fi

GIT="$(find_git)" || {
  show_error "Git could not be found. Install it with: brew install git"
  exit 0
}

repo_url="${QUICK_ACTION_GIT_URL:-}"
if [[ -z "$repo_url" ]]; then
  clipboard="$(/usr/bin/pbpaste 2>/dev/null || true)"
  clipboard="${clipboard%%$'\n'*}"
  clipboard="${clipboard[1,2048]}"
  case "$clipboard" in
    https://*|http://*|ssh://*|git@*) suggestion="$clipboard" ;;
    *) suggestion="" ;;
  esac

  repo_url="$(/usr/bin/osascript - "$suggestion" <<'APPLESCRIPT'
on run argv
  try
    set response to display dialog "Enter the SSH or HTTPS URL of the Git repository:" with title "_GIT_Clone Repo Into Folder" default answer (item 1 of argv) buttons {"Cancel", "Clone"} default button "Clone" cancel button "Cancel"
    return text returned of response
  on error number -128
    return ""
  end try
end run
APPLESCRIPT
)" || exit 0
fi

repo_url="${repo_url##[[:space:]]#}"
repo_url="${repo_url%%[[:space:]]#}"
[[ -n "$repo_url" ]] || exit 0

destination_folder="${1:A}"
repo_tail="${repo_url%/}"
repo_tail="${repo_tail%%\?*}"
repo_tail="${repo_tail%%\#*}"
repo_tail="${repo_tail##*/}"
repo_tail="${repo_tail##*:}"
repo_name="${repo_tail%.git}"
[[ -n "$repo_name" ]] || repo_name="repository"

error_log="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/git-clone-quick-action.XXXXXX")" || {
  show_error "A temporary error log could not be created."
  exit 1
}
cleanup() {
  /bin/rm -f "$error_log"
}
trap cleanup EXIT

if GIT_TERMINAL_PROMPT=0 "$GIT" -C "$destination_folder" clone -- "$repo_url" 2>"$error_log"; then
  notify "Cloned $repo_name into ${destination_folder:t}."
  exit 0
fi

error_message="$(/usr/bin/tail -n 8 "$error_log")"
[[ -n "$error_message" ]] || error_message="Git could not clone the repository."
show_error "$error_message"
exit 1
