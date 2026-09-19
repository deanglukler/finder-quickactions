#!/bin/zsh

set -u

action_name="_PDF_SPLIT..."
pdf_count=0
page_count=0
failed_count=0

notify() {
  if [[ "${QUICK_ACTION_SUPPRESS_NOTIFICATIONS:-0}" != "1" ]]; then
    /usr/bin/osascript - "$1" "$action_name" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
  fi
}

find_tool() {
  local name="$1"
  local candidate
  for candidate in "/opt/homebrew/bin/$name" "/usr/local/bin/$name"; do
    if [[ -x "$candidate" ]]; then
      /usr/bin/printf '%s' "$candidate"
      return 0
    fi
  done

  candidate="$(command -v "$name" 2>/dev/null || true)"
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
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

file_stem() {
  local filename="$1"
  if [[ "$filename" == *.* && "$filename" != .* ]]; then
    /usr/bin/printf '%s' "${filename%.*}"
  else
    /usr/bin/printf '%s' "$filename"
  fi
}

split_into_pdfs() {
  local source="$1"
  local stem="$(file_stem "${source:t}")"
  local destination="$(unique_folder "${source:h}" "$stem - PDF Pages")"
  local expected_pages
  local -a generated
  local index=1
  local file
  local final_name

  expected_pages="$("$QPDF" --show-npages "$source" 2>/dev/null)" || return 1
  [[ "$expected_pages" == <-> && "$expected_pages" -gt 0 ]] || return 1
  /bin/mkdir "$destination" || return 1

  if ! "$QPDF" --split-pages=1 "$source" "$destination/.page-%d.pdf" >/dev/null 2>&1; then
    /bin/rm -rf "$destination"
    return 1
  fi

  generated=("$destination"/.page-*.pdf(Nn))
  if (( ${#generated[@]} != expected_pages )); then
    /bin/rm -rf "$destination"
    return 1
  fi

  for file in "${generated[@]}"; do
    final_name="$(/usr/bin/printf '%s-%03d.pdf' "$stem" "$index")"
    /bin/mv "$file" "$destination/$final_name" || {
      /bin/rm -rf "$destination"
      return 1
    }
    (( index++ ))
  done

  (( pdf_count++ ))
  page_count=$(( page_count + expected_pages ))
}

split_into_pngs() {
  local source="$1"
  local stem="$(file_stem "${source:t}")"
  local destination="$(unique_folder "${source:h}" "$stem - PNG Pages")"
  local expected_pages
  local -a generated

  expected_pages="$("$QPDF" --show-npages "$source" 2>/dev/null)" || return 1
  [[ "$expected_pages" == <-> && "$expected_pages" -gt 0 ]] || return 1
  /bin/mkdir "$destination" || return 1

  if ! "$GHOSTSCRIPT" \
      -q -dNOPAUSE -dBATCH -dSAFER \
      -sDEVICE=png16m \
      -r150 \
      -dUseCropBox \
      -dTextAlphaBits=4 \
      -dGraphicsAlphaBits=4 \
      -sOutputFile="$destination/$stem-%03d.png" \
      "$source" >/dev/null 2>&1; then
    /bin/rm -rf "$destination"
    return 1
  fi

  generated=("$destination"/*.png(N))
  if (( ${#generated[@]} != expected_pages )); then
    /bin/rm -rf "$destination"
    return 1
  fi

  (( pdf_count++ ))
  page_count=$(( page_count + expected_pages ))
}

if (( $# == 0 )); then
  notify "Select one or more PDF files in Finder."
  exit 0
fi

choice="${QUICK_ACTION_PDF_SPLIT_CHOICE:-}"
if [[ -z "$choice" ]]; then
  choice="$(/usr/bin/osascript <<'APPLESCRIPT'
set choices to {"Split PDF Into Files", "Split PDF Into PNG Files"}
set picked to choose from list choices with title "_PDF_SPLIT..." with prompt "Choose how to split the selected PDF file(s):" default items {"Split PDF Into Files"} OK button name "Split" cancel button name "Cancel"
if picked is false then return ""
return item 1 of picked
APPLESCRIPT
)" || exit 0
fi

QPDF="$(find_tool qpdf)" || {
  notify "qpdf is required. Install it with: brew install qpdf"
  exit 0
}

if [[ "$choice" == "Split PDF Into PNG Files" ]]; then
  GHOSTSCRIPT="$(find_tool gs)" || {
    notify "Ghostscript is required. Install it with: brew install ghostscript"
    exit 0
  }
elif [[ "$choice" != "Split PDF Into Files" ]]; then
  notify "No PDF split action was selected."
  exit 0
fi

for source in "$@"; do
  if [[ ! -f "$source" || "${source:e:l}" != "pdf" ]]; then
    (( failed_count++ ))
    continue
  fi

  source="${source:A}"
  if [[ "$choice" == "Split PDF Into Files" ]]; then
    split_into_pdfs "$source" || (( failed_count++ ))
  else
    split_into_pngs "$source" || (( failed_count++ ))
  fi
done

if (( pdf_count > 0 )); then
  message="Split $pdf_count PDF(s) into $page_count page file(s)."
  if (( failed_count > 0 )); then
    message="$message $failed_count PDF(s) failed."
  fi
  notify "$message"
else
  notify "No page files were created; $failed_count PDF(s) failed."
fi
