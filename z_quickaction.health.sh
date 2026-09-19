#!/bin/zsh

set -u

action_name="z_quickaction.health"
formulae=(imagemagick exiftool ghostscript qpdf ffmpeg git)

notify() {
  if [[ "${QUICK_ACTION_SUPPRESS_NOTIFICATIONS:-0}" != "1" ]]; then
    /usr/bin/osascript - "$1" "$action_name" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
  fi
}

find_brew() {
  local candidate

  if [[ -n "${QUICK_ACTION_BREW_OVERRIDE:-}" ]]; then
    if [[ -x "$QUICK_ACTION_BREW_OVERRIDE" ]]; then
      /usr/bin/printf '%s' "$QUICK_ACTION_BREW_OVERRIDE"
      return 0
    fi
    return 1
  fi

  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" ]]; then
      /usr/bin/printf '%s' "$candidate"
      return 0
    fi
  done

  candidate="$(command -v brew 2>/dev/null || true)"
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  /usr/bin/printf '%s' "$candidate"
}

formula_command() {
  case "$1" in
    imagemagick) /usr/bin/printf '%s' magick ;;
    exiftool) /usr/bin/printf '%s' exiftool ;;
    ghostscript) /usr/bin/printf '%s' gs ;;
    qpdf) /usr/bin/printf '%s' qpdf ;;
    ffmpeg) /usr/bin/printf '%s' ffmpeg ;;
    git) /usr/bin/printf '%s' git ;;
  esac
}

formula_display_name() {
  case "$1" in
    imagemagick) /usr/bin/printf '%s' ImageMagick ;;
    exiftool) /usr/bin/printf '%s' ExifTool ;;
    ghostscript) /usr/bin/printf '%s' Ghostscript ;;
    qpdf) /usr/bin/printf '%s' qpdf ;;
    ffmpeg) /usr/bin/printf '%s' FFmpeg ;;
    git) /usr/bin/printf '%s' Git ;;
  esac
}

formula_healthy() {
  local brew="$1"
  local formula="$2"
  local prefix
  local command_name
  local executable

  prefix="$("$brew" --prefix "$formula" 2>/dev/null)" || return 1
  command_name="$(formula_command "$formula")"
  executable="$prefix/bin/$command_name"
  [[ -x "$executable" ]] || return 1

  case "$formula" in
    imagemagick) "$executable" -version >/dev/null 2>&1 ;;
    exiftool) "$executable" -ver >/dev/null 2>&1 ;;
    ghostscript) "$executable" --version >/dev/null 2>&1 ;;
    qpdf) "$executable" --version >/dev/null 2>&1 ;;
    ffmpeg) "$executable" -version >/dev/null 2>&1 ;;
    git) "$executable" --version >/dev/null 2>&1 ;;
  esac
}

zed_healthy() {
  local candidate

  if [[ -n "${QUICK_ACTION_ZED_CLI_OVERRIDE:-}" ]]; then
    [[ -x "$QUICK_ACTION_ZED_CLI_OVERRIDE" ]] && "$QUICK_ACTION_ZED_CLI_OVERRIDE" --version >/dev/null 2>&1
    return $?
  fi

  for candidate in \
    "/Applications/Zed.app/Contents/MacOS/cli" \
    "$HOME/Applications/Zed.app/Contents/MacOS/cli"; do
    if [[ -x "$candidate" ]] && "$candidate" --version >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

collect_missing() {
  local brew=""
  local formula
  missing_items=()

  if ! brew="$(find_brew)"; then
    missing_items+=(Homebrew)
    for formula in "${formulae[@]}"; do
      missing_items+=("$(formula_display_name "$formula")")
    done
  else
    for formula in "${formulae[@]}"; do
      formula_healthy "$brew" "$formula" || missing_items+=("$(formula_display_name "$formula")")
    done
  fi

  zed_healthy || missing_items+=(Zed)
}

install_homebrew() {
  local installer

  /usr/bin/printf '\nHomebrew is not installed. Starting the official interactive installer.\n'
  /usr/bin/printf 'The installer may request your administrator password and install Apple Command Line Tools.\n\n'

  if [[ -n "${QUICK_ACTION_HOMEBREW_INSTALLER:-}" ]]; then
    /bin/bash "$QUICK_ACTION_HOMEBREW_INSTALLER"
    return $?
  fi

  installer="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/homebrew-install.XXXXXX")" || return 1
  if ! /usr/bin/curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" -o "$installer"; then
    /bin/rm -f "$installer"
    return 1
  fi
  /bin/bash "$installer"
  status=$?
  /bin/rm -f "$installer"
  return $status
}

install_dependencies() {
  local brew=""
  local formula
  local display_name
  local -a failures

  failures=()
  if ! brew="$(find_brew)"; then
    install_homebrew || {
      /usr/bin/printf '\nHomebrew installation failed. Review the messages above and run this Quick Action again.\n'
      notify "Homebrew installation failed. Review Terminal for details."
      return 1
    }
    brew="$(find_brew)" || {
      /usr/bin/printf '\nHomebrew finished but its executable could not be found.\n'
      notify "Homebrew could not be found after installation."
      return 1
    }
  fi

  /usr/bin/printf '\nUsing Homebrew: %s\n' "$brew"
  for formula in "${formulae[@]}"; do
    display_name="$(formula_display_name "$formula")"
    if formula_healthy "$brew" "$formula"; then
      /usr/bin/printf '✓ %s is already installed and working.\n' "$display_name"
      continue
    fi

    if "$brew" list --versions "$formula" >/dev/null 2>&1; then
      /usr/bin/printf 'Repairing %s...\n' "$display_name"
      "$brew" reinstall "$formula" || failures+=("$display_name")
    else
      /usr/bin/printf 'Installing %s...\n' "$display_name"
      "$brew" install "$formula" || failures+=("$display_name")
    fi
  done

  if zed_healthy; then
    /usr/bin/printf '✓ Zed is already installed and working.\n'
  elif "$brew" list --cask zed >/dev/null 2>&1; then
    /usr/bin/printf 'Repairing Zed...\n'
    "$brew" reinstall --cask zed || failures+=(Zed)
  else
    /usr/bin/printf 'Installing Zed...\n'
    "$brew" install --cask zed || failures+=(Zed)
  fi

  /usr/bin/printf '\nVerifying Quick Action dependencies...\n'
  for formula in "${formulae[@]}"; do
    display_name="$(formula_display_name "$formula")"
    if formula_healthy "$brew" "$formula"; then
      /usr/bin/printf '✓ %s\n' "$display_name"
    else
      /usr/bin/printf '✗ %s\n' "$display_name"
      (( ${failures[(Ie)$display_name]} )) || failures+=("$display_name")
    fi
  done
  if zed_healthy; then
    /usr/bin/printf '✓ Zed\n'
  else
    /usr/bin/printf '✗ Zed\n'
    (( ${failures[(Ie)Zed]} )) || failures+=(Zed)
  fi

  if (( ${#failures[@]} == 0 )); then
    /usr/bin/printf '\nAll Quick Action dependencies are installed and working.\n'
    notify "All Quick Action dependencies are installed and working."
    return 0
  fi

  /usr/bin/printf '\nInstallation finished with failures: %s\n' "${(j:, :)failures}"
  notify "Some dependencies failed verification. Review Terminal for details."
  return 1
}

if [[ "${1:-}" == "--install" ]]; then
  install_dependencies
  exit $?
fi

collect_missing
if (( ${#missing_items[@]} == 0 )); then
  notify "All Quick Action dependencies are already installed and working."
  exit 0
fi

missing_list=""
for item in "${missing_items[@]}"; do
  missing_list="$missing_list${missing_list:+$'\n'}• $item"
done

if [[ "${QUICK_ACTION_INSTALLER_AUTO_CONFIRM:-0}" != "1" ]]; then
  confirmed="$(/usr/bin/osascript - "$missing_list" <<'APPLESCRIPT'
on run argv
  try
    display dialog "The following Quick Action dependencies need to be installed or repaired:" & return & return & (item 1 of argv) & return & return & "Installation will open in Terminal." with title "z_quickaction.health" buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel"
    return "yes"
  on error number -128
    return "no"
  end try
end run
APPLESCRIPT
)" || exit 0
  [[ "$confirmed" == "yes" ]] || exit 0
fi

script_path="${0:A}"
if [[ "${QUICK_ACTION_INSTALLER_SYNCHRONOUS:-0}" == "1" ]]; then
  "$script_path" --install
  exit $?
fi

/usr/bin/osascript - "$script_path" <<'APPLESCRIPT'
on run argv
  set commandText to quoted form of (item 1 of argv) & " --install"
  tell application "Terminal"
    activate
    do script commandText
  end tell
end run
APPLESCRIPT
