#!/bin/zsh

set -u

action_name="_CLIPBOARD_Create File From Clipboard"

notify() {
  if [[ "${QUICK_ACTION_SUPPRESS_NOTIFICATIONS:-0}" != "1" ]]; then
    /usr/bin/osascript - "$1" "$action_name" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
  fi
}

if (( $# != 1 )); then
  notify "Select exactly one file or folder in Finder."
  exit 0
fi

item="$1"
if [[ -d "$item" ]]; then
  folder="$item"
elif [[ -f "$item" ]]; then
  folder="${item:h}"
else
  notify "The selected item could not be found."
  exit 1
fi

base="clipboard-$(/bin/date '+%y%m%d-%H%M%S')"
pasteboard_name="${QUICK_ACTION_PASTEBOARD_NAME:-}"

result="$(/usr/bin/osascript -l JavaScript - "$folder" "$base" "$pasteboard_name" <<'JXA'
ObjC.import('AppKit');
ObjC.import('Foundation');

function string(value) {
  if (!value) return '';
  return ObjC.unwrap(value);
}

function uniquePath(folder, base, extension) {
  const manager = $.NSFileManager.defaultManager;
  let name = base + '.' + extension;
  let path = folder + '/' + name;
  let counter = 2;
  while (manager.fileExistsAtPath($(path))) {
    name = base + ' ' + counter + '.' + extension;
    path = folder + '/' + name;
    counter += 1;
  }
  return {name: name, path: path};
}

function writeData(data, destination) {
  return data && $.NSFileManager.defaultManager.createFileAtPathContentsAttributes(
    $(destination),
    data,
    $({})
  );
}

function hasType(pasteboard, type) {
  const types = pasteboard.types;
  if (!types) return false;
  for (let index = 0; index < types.count; index += 1) {
    if (string(types.objectAtIndex(index)) === type) return true;
  }
  return false;
}

function copyFinderItems(pasteboard, folder) {
  const items = pasteboard.pasteboardItems;
  if (!items) return null;

  const manager = $.NSFileManager.defaultManager;
  const sources = [];
  const names = {};
  const conflicts = [];

  for (let index = 0; index < items.count; index += 1) {
    const value = items.objectAtIndex(index).stringForType($('public.file-url'));
    if (!value) continue;
    const url = $.NSURL.URLWithString(value);
    if (!url || !url.isFileURL) continue;
    const source = string(url.path);
    const name = string(url.lastPathComponent);
    if (!source || !name || !manager.fileExistsAtPath($(source))) continue;
    const target = folder + '/' + name;
    if (names[name] || manager.fileExistsAtPath($(target))) conflicts.push(name);
    names[name] = true;
    sources.push({source: source, target: target});
  }

  if (sources.length === 0) return null;
  if (conflicts.length > 0) {
    return 'conflict\t' + conflicts.join(', ');
  }

  for (let index = 0; index < sources.length; index += 1) {
    const error = Ref();
    if (!manager.copyItemAtPathToPathError($(sources[index].source), $(sources[index].target), error)) {
      return 'error\tA Finder item could not be copied.';
    }
  }
  return 'ok\tCopied ' + sources.length + (sources.length === 1 ? ' item.' : ' items.');
}

function run(argv) {
  const folder = argv[0].replace(/\/$/, '') || '/';
  const base = argv[1];
  const pasteboardName = argv[2];
  const pasteboard = pasteboardName
    ? $.NSPasteboard.pasteboardWithName($(pasteboardName))
    : $.NSPasteboard.generalPasteboard;

  const copiedItems = copyFinderItems(pasteboard, folder);
  if (copiedItems) return copiedItems;

  let data = hasType(pasteboard, 'com.adobe.pdf')
    ? pasteboard.dataForType($('com.adobe.pdf'))
    : null;
  if (data) {
    const destination = uniquePath(folder, base, 'pdf');
    return writeData(data, destination.path)
      ? 'ok\tCreated ' + destination.name + '.'
      : 'error\tThe PDF could not be written.';
  }

  data = hasType(pasteboard, 'public.png')
    ? pasteboard.dataForType($('public.png'))
    : null;
  if (data) {
    const destination = uniquePath(folder, base, 'png');
    return writeData(data, destination.path)
      ? 'ok\tCreated ' + destination.name + '.'
      : 'error\tThe image could not be written.';
  }

  data = hasType(pasteboard, 'public.tiff')
    ? pasteboard.dataForType($('public.tiff'))
    : null;
  if (data) {
    const representation = $.NSBitmapImageRep.imageRepWithData(data);
    const png = representation
      ? representation.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $({}))
      : null;
    const destination = uniquePath(folder, base, 'png');
    return writeData(png, destination.path)
      ? 'ok\tCreated ' + destination.name + '.'
      : 'error\tThe image could not be converted to PNG.';
  }

  let text = null;
  const textTypes = [
    'public.utf8-plain-text',
    'public.utf16-external-plain-text',
    'public.plain-text',
    'NSStringPboardType'
  ];
  for (let index = 0; index < textTypes.length; index += 1) {
    if (hasType(pasteboard, textTypes[index])) {
      text = pasteboard.stringForType($(textTypes[index]));
      if (text) break;
    }
  }
  if (!text && hasType(pasteboard, 'public.rtf')) {
    const attributes = Ref();
    const richText = $.NSAttributedString.alloc.initWithRTFDocumentAttributes(
      pasteboard.dataForType($('public.rtf')),
      attributes
    );
    if (richText) text = richText.string;
  }
  if (!text && hasType(pasteboard, 'public.html')) {
    const attributes = Ref();
    const richText = $.NSAttributedString.alloc.initWithHTMLDocumentAttributes(
      pasteboard.dataForType($('public.html')),
      attributes
    );
    if (richText) text = richText.string;
  }
  if (text) {
    const destination = uniquePath(folder, base, 'txt');
    const textData = $(string(text)).dataUsingEncoding($.NSUTF8StringEncoding);
    const written = writeData(textData, destination.path);
    return written
      ? 'ok\tCreated ' + destination.name + '.'
      : 'error\tThe text could not be written.';
  }

  return 'empty\tThe clipboard does not contain a supported file, image, PDF, or text value.';
}
JXA
)" || {
  notify "The clipboard could not be read."
  exit 1
}

result_status="${result%%$'\t'*}"
message="${result#*$'\t'}"
case "$result_status" in
  ok)
    notify "$message"
    ;;
  conflict)
    notify "Nothing was copied because these names already exist: $message"
    exit 1
    ;;
  empty|error)
    notify "$message"
    exit 1
    ;;
  *)
    notify "The clipboard returned an unexpected result."
    exit 1
    ;;
esac
