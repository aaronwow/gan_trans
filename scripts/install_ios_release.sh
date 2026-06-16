#!/usr/bin/env bash
set -euo pipefail

device_id="${1:?device id is required}"
app_path="${2:-build/ios/iphoneos/Runner.app}"

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi

identity="$(
  codesign -dv --verbose=4 "$app_path" 2>&1 |
    awk -F= '/^Authority=/ && $2 !~ /Apple Worldwide|Apple Root/ && identity == "" { identity = $2 } END { print identity }'
)"

if [[ -z "$identity" ]]; then
  echo "Could not infer signing identity from $app_path" >&2
  exit 1
fi

entitlements="$(mktemp -t gantrans-entitlements.XXXXXX.plist)"
trap 'rm -f "$entitlements"' EXIT
codesign -d --entitlements :- "$app_path" 2>/dev/null > "$entitlements"

if [[ -d "$app_path/Frameworks" ]]; then
  while IFS= read -r -d '' framework; do
    codesign --force --sign "$identity" "$framework"
  done < <(find "$app_path/Frameworks" -maxdepth 1 -type d -name '*.framework' -print0)
fi

codesign --force --sign "$identity" --entitlements "$entitlements" "$app_path"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"

xcrun devicectl device install app --device "$device_id" "$app_path"
xcrun devicectl device process launch --device "$device_id" "$bundle_id"
