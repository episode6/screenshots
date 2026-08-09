#!/usr/bin/env bash
# Upload a media file to episode6/screenshots as a Git LFS object — without
# cloning the repo — and print the embeddable URL.
#
# The repo stores all images/videos in Git LFS (.gitattributes), and the
# GitHub contents API can't create LFS objects (it would commit the raw
# bytes as a regular blob, bypassing LFS). So this script does the LFS
# dance manually:
#   1. Ask the repo's LFS server for an upload location (batch API)
#   2. PUT the file bytes to that location (skipped if already stored)
#   3. Commit a tiny LFS pointer file via the contents API
#
# Usage: upload.sh <local-file> <dest-path-in-repo> [<commit-message>]
# Prints the media.githubusercontent.com URL for embedding on success.
set -euo pipefail

file="${1:?usage: upload.sh <local-file> <dest-path-in-repo> [<commit-message>]}"
path="${2:?usage: upload.sh <local-file> <dest-path-in-repo> [<commit-message>]}"
message="${3:-Add $path}"

repo="episode6/screenshots"
branch="main"

# The dest path is used verbatim in the contents-API route and the embed
# URL, so it must be URL-safe. Screenshots often arrive with spaces in
# their names ("Screenshot 2026-08-09 at ...") — catch that here instead
# of producing a broken URL.
case "$path" in
  */ | /* | *..* | *[!A-Za-z0-9./_-]*)
    echo "error: dest path '$path' must contain only letters, numbers, '.', '-', '_' and '/'" >&2
    echo "hint: sanitize the name first, e.g.: \$(basename \"\$file\" | tr -c 'A-Za-z0-9._\\n-' '-')" >&2
    exit 1
    ;;
esac

if command -v sha256sum >/dev/null; then
  oid=$(sha256sum "$file" | cut -d' ' -f1)
else # macOS
  oid=$(shasum -a 256 "$file" | cut -d' ' -f1)
fi
size=$(wc -c < "$file" | tr -d ' ')
token=$(gh auth token)

# 1. Batch API: where do these bytes go?
batch=$(curl -sf -u "x:$token" \
  -H 'Accept: application/vnd.git-lfs+json' \
  -H 'Content-Type: application/vnd.git-lfs+json' \
  -d "{\"operation\":\"upload\",\"transfers\":[\"basic\"],\"objects\":[{\"oid\":\"$oid\",\"size\":$size}]}" \
  "https://github.com/$repo.git/info/lfs/objects/batch")

err=$(jq -r '.objects[0].error.message // empty' <<<"$batch")
if [ -n "$err" ]; then
  echo "LFS batch error: $err" >&2
  exit 1
fi

# Build "-H key: value" curl args from an action's header map.
action_headers() {
  jq -r ".objects[0].actions.$1.header // {} | to_entries[] | \"\(.key): \(.value)\"" <<<"$batch"
}

# 2. Upload the bytes (no upload action == server already has this object).
upload_href=$(jq -r '.objects[0].actions.upload.href // empty' <<<"$batch")
if [ -n "$upload_href" ]; then
  hdr_args=()
  while IFS= read -r h; do [ -n "$h" ] && hdr_args+=(-H "$h"); done < <(action_headers upload)
  curl -sf -X PUT "${hdr_args[@]}" -H 'Content-Type: application/octet-stream' \
    --data-binary @"$file" "$upload_href" > /dev/null

  verify_href=$(jq -r '.objects[0].actions.verify.href // empty' <<<"$batch")
  if [ -n "$verify_href" ]; then
    hdr_args=()
    while IFS= read -r h; do [ -n "$h" ] && hdr_args+=(-H "$h"); done < <(action_headers verify)
    curl -sf -X POST "${hdr_args[@]}" \
      -H 'Accept: application/vnd.git-lfs+json' \
      -H 'Content-Type: application/vnd.git-lfs+json' \
      -d "{\"oid\":\"$oid\",\"size\":$size}" "$verify_href" > /dev/null
  fi
fi

# 3. Commit the pointer file (fails with HTTP 422 if the path already
#    exists — pick a fresh filename rather than overwriting).
pointer=$(printf 'version https://git-lfs.github.com/spec/v1\noid sha256:%s\nsize %s\n' "$oid" "$size")
printf '%s' "$pointer" | base64 | tr -d '\n' | \
  gh api -X PUT "repos/$repo/contents/$path" \
    -f message="$message" -F content=@- > /dev/null

echo "https://media.githubusercontent.com/media/$repo/$branch/$path"
