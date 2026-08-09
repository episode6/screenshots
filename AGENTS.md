# Publishing screenshots for PR descriptions

This repo hosts screenshots (and other media) so they can be embedded in
GitHub PR descriptions, PR comments, and issues for episode6/ghackett
repos. GitHub's CLI/API can't attach images directly to a PR body, so
files are pushed here and embedded with `media.githubusercontent.com`
URLs.

> These instructions (and `upload.sh`) are duplicated from the
> `publish-screenshots` agent skill in ghackett's `~/.agents` repo, which
> is how agents normally upload here — from another repo's checkout,
> without cloning this one. When editing either copy, update both.

All images and videos are stored in **Git LFS** (enforced by the root
`.gitattributes`). This has two consequences:

- **Never upload media via the plain contents API** (`gh api -X PUT
  .../contents/...` with the file's base64). `.gitattributes` is a
  client-side filter, so that would commit the raw bytes as a regular git
  blob, silently bypassing LFS — exactly what this repo was migrated away
  from. Use `upload.sh` (or a real git-lfs checkout).
- **Embed URLs use the `media.githubusercontent.com` host.**
  `raw.githubusercontent.com` returns the ~130-byte LFS pointer text for
  LFS-tracked files, not the media bytes, so raw URLs render as broken
  images.

## Upload with ./upload.sh (no checkout needed)

`./upload.sh` uploads the bytes through the Git LFS batch API, then
commits only the tiny LFS pointer file via the contents API — it works
from anywhere, no clone of this repo required:

```bash
./upload.sh <local-file> "<source-repo-name>/<branch-or-topic>/<descriptive-name>-$(date +%Y%m%d-%H%M%S).png"
# → prints https://media.githubusercontent.com/media/episode6/screenshots/main/<path>
```

An optional third argument overrides the commit message (default:
`Add <path>`).

Notes:

- **Path convention**: first path segment is the source repo name (e.g.
  `podcast-hacker/...`). Include a timestamp or branch/PR segment so names
  are unique.
- **URL-safe filenames only — validate before uploading.** The dest path
  is used verbatim in the contents-API route and the embed URL, so it must
  contain only `A-Za-z0-9._-` and `/`. Screenshots often arrive with
  spaces in their names (`Screenshot 2026-08-09 at 8.30.12 AM.png`);
  `upload.sh` rejects such paths up front rather than producing a broken
  URL. Sanitize first:

  ```bash
  safe=$(basename "$file" | tr -c 'A-Za-z0-9._\n-' '-')
  ```

- **Unique filenames matter**: the pointer commit fails with HTTP 422 if
  the path already exists. Prefer fresh filenames over overwriting.
- **Auth**: a locally-authenticated `gh` (ghackett) already has write
  access; the script takes its token from `gh auth token`. In CI, a PAT
  with `contents:write` on episode6/screenshots is required.
- **Dependencies**: `gh`, `curl`, `jq`, and `sha256sum`/`shasum` — no
  git-lfs install needed.
- **Videos / screen recordings** may be stored here too (LFS handles them
  fine), but GitHub markdown won't render a video by URL — only videos
  uploaded through GitHub's own attachment CDN render inline. So a video
  pushed here can only be **linked** from a PR, not embedded. If inline
  playback matters, surface the file to the user to drag-drop into the PR
  instead.

## Embed in the PR description or comment

```markdown
![what the screenshot shows](https://media.githubusercontent.com/media/episode6/screenshots/main/<path>)
```

Plain markdown images render at full width. Device screenshots are tall, so
constrain them with an HTML tag instead — width 250–350 reads well:

```html
<img src="https://media.githubusercontent.com/media/episode6/screenshots/main/<path>" width="300" alt="what it shows" />
```

For before/after comparisons, put two `<img>` tags in a markdown table row.

## Verify before linking

New files are served immediately; confirm the media URL returns 200 with an
image/video content-type before embedding it:

```bash
curl -sfI "https://media.githubusercontent.com/media/episode6/screenshots/main/$path" | grep -i content-type
```

## Repo history note

The pre-LFS history was intentionally squashed to a single root commit on
2026-08-09 to purge the old full-size image blobs. Embed URLs from before
that date used `raw.githubusercontent.com` and no longer resolve to image
bytes (the same path on `media.githubusercontent.com` works, since all
file paths were preserved). Never force-push or rewrite this repo's
history again without explicit direction.
