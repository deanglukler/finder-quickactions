#!/bin/zsh

set -u

action_name="_PDF_Make File(s) a PDF"
join_tool="/System/Library/Automator/Combine PDF Pages.action/Contents/MacOS/join"

notify() {
  if [[ "${QUICK_ACTION_SUPPRESS_NOTIFICATIONS:-0}" != "1" ]]; then
    /usr/bin/osascript - "$1" "$action_name" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
  fi
}

natural_sort() {
  /usr/bin/perl -e '
    sub key {
      my $value = lc shift;
      $value =~ s{.*/}{};
      return [split /(\d+)/, $value];
    }
    sub natural_compare {
      my ($left, $right) = @_;
      my $a = key($left);
      my $b = key($right);
      my $length = @$a > @$b ? @$a : @$b;
      for my $i (0 .. $length - 1) {
        return -1 if $i >= @$a;
        return 1 if $i >= @$b;
        my ($x, $y) = ($a->[$i], $b->[$i]);
        my $comparison;
        if ($x =~ /^\d+$/ && $y =~ /^\d+$/) {
          $comparison = $x <=> $y;
        } else {
          $comparison = $x cmp $y;
        }
        return $comparison if $comparison;
      }
      return $left cmp $right;
    }
    print "$_\0" for sort { natural_compare($a, $b) } @ARGV;
  ' "$@"
}

if (( $# == 0 )); then
  notify "Select one or more images or PDF files in Finder."
  exit 0
fi

if [[ ! -x "$join_tool" ]]; then
  notify "The built-in macOS PDF joining tool could not be found."
  exit 0
fi

files=()
while IFS= read -r -d '' file; do
  files+=("$file")
done < <(natural_sort "$@")

for file in "${files[@]}"; do
  if [[ ! -f "$file" ]]; then
    notify "Every selected item must be an image or PDF file."
    exit 0
  fi
done

if (( ${#files[@]} == 1 )) && [[ "${files[1]:e:l}" == "pdf" ]]; then
  notify "The selected file is already a PDF."
  exit 0
fi

first="${files[1]:A}"
first_name="${first:t}"
if [[ "$first_name" == *.* && "$first_name" != .* ]]; then
  first_stem="${first_name%.*}"
else
  first_stem="$first_name"
fi

if (( ${#files[@]} == 1 )); then
  suggested_name="$first_stem.pdf"
else
  suggested_name="$first_stem merged.pdf"
fi

destination="${QUICK_ACTION_PDF_DESTINATION:-}"
if [[ -z "$destination" ]]; then
  destination="$(/usr/bin/osascript - "${first:h}" "$suggested_name" <<'APPLESCRIPT'
on run argv
  try
    set destinationFolder to POSIX file (item 1 of argv) as alias
    set chosenFile to choose file name with prompt "Save the PDF as:" default location destinationFolder default name (item 2 of argv)
    return POSIX path of chosenFile
  on error number -128
    return ""
  end try
end run
APPLESCRIPT
)" || exit 0
fi

[[ -n "$destination" ]] || exit 0
if [[ "${destination:e:l}" != "pdf" ]]; then
  destination="$destination.pdf"
fi
destination="${destination:A}"

for file in "${files[@]}"; do
  if [[ "${file:A}" == "$destination" ]]; then
    notify "The output cannot replace one of the selected source files."
    exit 0
  fi
done

work_directory="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/make-pdf-quick-action.XXXXXX")" || {
  notify "A temporary working folder could not be created."
  exit 1
}
temporary="${destination:h}/.${destination:t}.quickaction.$$.pdf"
cleanup() {
  /bin/rm -rf "$work_directory"
  [[ -e "$temporary" ]] && /bin/rm -f "$temporary"
}
trap cleanup EXIT

merge_files=()
image_number=1
for file in "${files[@]}"; do
  if [[ "${file:e:l}" == "pdf" ]]; then
    merge_files+=("$file")
  else
    image_pdf="$work_directory/$image_number.pdf"
    if ! /usr/bin/sips -s format pdf "$file" --out "$image_pdf" >/dev/null 2>&1 || [[ ! -s "$image_pdf" ]]; then
      notify "${file:t} could not be converted to a PDF page."
      exit 1
    fi
    merge_files+=("$image_pdf")
    (( image_number++ ))
  fi
done

if "$join_tool" --output "$temporary" "${merge_files[@]}" >/dev/null 2>&1 && [[ -s "$temporary" ]]; then
  if /bin/mv -f "$temporary" "$destination"; then
    notify "Created ${destination:t}."
    exit 0
  fi
fi

[[ -e "$temporary" ]] && /bin/rm -f "$temporary"
notify "The selected files could not be made into a PDF."
exit 1
