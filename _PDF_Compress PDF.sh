#!/bin/zsh

set -u

action_name="_PDF_Compress PDF"
compressed_count=0
insignificant_count=0
failed_count=0
total_original_bytes=0
total_compressed_bytes=0

notify() {
  if [[ "${QUICK_ACTION_SUPPRESS_NOTIFICATIONS:-0}" != "1" ]]; then
    /usr/bin/osascript - "$1" "$action_name" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
  fi
}

find_ghostscript() {
  local candidate
  for candidate in /opt/homebrew/bin/gs /usr/local/bin/gs; do
    if [[ -x "$candidate" ]]; then
      /usr/bin/printf '%s' "$candidate"
      return 0
    fi
  done

  candidate="$(command -v gs 2>/dev/null || true)"
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  /usr/bin/printf '%s' "$candidate"
}

unique_output_path() {
  local source="$1"
  local directory="${source:h}"
  local filename="${source:t}"
  local stem="$filename"
  local candidate
  local number=2

  if [[ "$filename" == *.* && "$filename" != .* ]]; then
    stem="${filename%.*}"
  fi

  candidate="$directory/$stem-compressed.pdf"
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$directory/$stem-compressed $number.pdf"
    (( number++ ))
  done

  /usr/bin/printf '%s' "$candidate"
}

format_bytes() {
  /usr/bin/awk -v bytes="$1" 'BEGIN {
    if (bytes >= 1073741824) printf "%.1f GB", bytes / 1073741824;
    else if (bytes >= 1048576) printf "%.1f MB", bytes / 1048576;
    else if (bytes >= 1024) printf "%.1f KB", bytes / 1024;
    else printf "%d bytes", bytes;
  }'
}

if (( $# == 0 )); then
  notify "Select one or more PDF files in Finder."
  exit 0
fi

GHOSTSCRIPT="$(find_ghostscript)" || {
  notify "Ghostscript is required. Install it with: brew install ghostscript"
  exit 0
}

for source in "$@"; do
  if [[ ! -f "$source" || "${source:e:l}" != "pdf" ]]; then
    (( failed_count++ ))
    continue
  fi

  source="${source:A}"
  destination="$(unique_output_path "$source")"
  temporary="${destination:h}/.${destination:t}.quickaction.$$.pdf"

  if "$GHOSTSCRIPT" \
      -q -dNOPAUSE -dBATCH -dSAFER \
      -sDEVICE=pdfwrite \
      -dCompatibilityLevel=1.6 \
      -dPDFSETTINGS=/ebook \
      -dDetectDuplicateImages=true \
      -dCompressFonts=true \
      -sOutputFile="$temporary" \
      "$source" >/dev/null 2>&1 && [[ -s "$temporary" ]]; then
    if /bin/mv "$temporary" "$destination"; then
      original_bytes="$(/usr/bin/stat -f %z "$source")"
      compressed_bytes="$(/usr/bin/stat -f %z "$destination")"
      total_original_bytes=$(( total_original_bytes + original_bytes ))
      total_compressed_bytes=$(( total_compressed_bytes + compressed_bytes ))
      reduction="$(/usr/bin/awk -v original="$original_bytes" -v compressed="$compressed_bytes" 'BEGIN { if (original == 0) print 0; else printf "%.2f", ((original - compressed) / original) * 100 }')"
      if /usr/bin/awk -v reduction="$reduction" 'BEGIN { exit !(reduction < 5) }'; then
        (( insignificant_count++ ))
      fi
      (( compressed_count++ ))
    else
      /bin/rm -f "$temporary"
      (( failed_count++ ))
    fi
  else
    [[ -e "$temporary" ]] && /bin/rm -f "$temporary"
    (( failed_count++ ))
  fi
done

if (( compressed_count == 1 )); then
  original_size="$(format_bytes "$total_original_bytes")"
  compressed_size="$(format_bytes "$total_compressed_bytes")"
  reduction="$(/usr/bin/awk -v original="$total_original_bytes" -v compressed="$total_compressed_bytes" 'BEGIN { if (original == 0) print 0; else printf "%.1f", ((original - compressed) / original) * 100 }')"
  if (( insignificant_count == 1 )); then
    notify "Created the compressed PDF ($original_size to $compressed_size). File size could not be reduced significantly ($reduction%)."
  else
    notify "Created the compressed PDF: $original_size to $compressed_size ($reduction% smaller)."
  fi
elif (( compressed_count > 1 )); then
  difference=$(( total_original_bytes - total_compressed_bytes ))
  if (( difference >= 0 )); then
    size_message="Saved $(format_bytes "$difference") total."
  else
    size_message="Outputs are $(format_bytes "$(( -difference ))") larger in total."
  fi
  message="Created $compressed_count compressed PDF(s). $size_message"
  if (( insignificant_count > 0 )); then
    message="$message $insignificant_count file(s) could not be reduced significantly."
  fi
  if (( failed_count > 0 )); then
    message="$message $failed_count failed."
  fi
  notify "$message"
else
  notify "No compressed PDFs were created; $failed_count item(s) failed."
fi
