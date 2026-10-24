#!/usr/bin/env bash
# Publishes a signed build to GitHub Pages (branch gh-pages), one folder per tag.
#
# The branch is rewritten as a single orphan commit on every publish so IPA files never pile up in the
# history. Only folders that contain build.json are kept (the branch may have been created from the
# source code), all stable builds from main are kept, and only the newest MAX_BRANCH_BUILDS branch builds
# survive. If another build publishes at the same time, the push is rejected by --force-with-lease and
# the whole publish is retried on top of the new state.
#
# Required environment:
#   TAG CHANNEL(stable|branch) BASE_URL IPA_PATH ICON_57 ICON_512 APP_NAME BUNDLE_ID
#   MARKETING_VERSION BUILD_NUMBER COMMIT_TITLE COMMIT_SHA BRANCH
# Optional environment:
#   REPOSITORY RUN_URL DEVICES MAX_BRANCH_BUILDS(20) REMOTE(origin) PAGES_BRANCH(gh-pages)
set -euo pipefail

: "${TAG:?}" "${CHANNEL:?}" "${BASE_URL:?}" "${IPA_PATH:?}" "${ICON_57:?}" "${ICON_512:?}"
: "${APP_NAME:?}" "${BUNDLE_ID:?}" "${MARKETING_VERSION:?}" "${BUILD_NUMBER:?}"
: "${COMMIT_TITLE:?}" "${COMMIT_SHA:?}" "${BRANCH:?}"
REPOSITORY="${REPOSITORY:-}"
RUN_URL="${RUN_URL:-}"
DEVICES="${DEVICES:-}"
MAX_BRANCH_BUILDS="${MAX_BRANCH_BUILDS:-20}"
REMOTE="${REMOTE:-origin}"
PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"
MAX_ATTEMPTS=6

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_DIR_ABSOLUTE="$(git rev-parse --absolute-git-dir)"
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-github-actions[bot]}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-$GIT_AUTHOR_NAME}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-$GIT_AUTHOR_EMAIL}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. Prepare the folder of this build once; every attempt copies it into a fresh checkout of the site.
STAGE="$WORK/stage/$TAG"
mkdir -p "$STAGE"
cp "$IPA_PATH" "$STAGE/Itinerary.ipa"
cp "$ICON_57" "$STAGE/icon-57.png"
cp "$ICON_512" "$STAGE/icon-512.png"
python3 "$SCRIPT_DIR/pages.py" build \
  --dir "$STAGE" \
  --base-url "$BASE_URL" \
  --tag "$TAG" \
  --channel "$CHANNEL" \
  --app-name "$APP_NAME" \
  --bundle-id "$BUNDLE_ID" \
  --version "$MARKETING_VERSION" \
  --build-number "$BUILD_NUMBER" \
  --commit-title "$COMMIT_TITLE" \
  --commit-sha "$COMMIT_SHA" \
  --branch "$BRANCH" \
  --repository "$REPOSITORY" \
  --run-url "$RUN_URL" \
  --devices "$DEVICES"

# Runs git against this repository's object database, with the site folder as the work tree and a
# private index, so the checkout of the source code is never touched.
site_git() {
  GIT_INDEX_FILE="$WORK/index" git --git-dir="$GIT_DIR_ABSOLUTE" --work-tree="$SITE" -C "$SITE" "$@"
}

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  echo "Publishing $TAG to $PAGES_BRANCH (attempt $attempt/$MAX_ATTEMPTS)"
  SITE="$WORK/site"
  rm -rf "$SITE" "$WORK/index"
  mkdir -p "$SITE"

  # 2. Start from the current content of the branch, if it exists.
  lease=""
  if git ls-remote --exit-code --heads "$REMOTE" "$PAGES_BRANCH" >/dev/null 2>&1; then
    git fetch --no-tags --depth 1 "$REMOTE" "+refs/heads/$PAGES_BRANCH:refs/remotes/$REMOTE/$PAGES_BRANCH"
    lease="$(git rev-parse "refs/remotes/$REMOTE/$PAGES_BRANCH")"
    git archive --format=tar "$lease" | tar -xf - -C "$SITE"
  fi

  # 3. Keep only build folders; everything else (old home page, source code) is regenerated or dropped.
  for entry in "$SITE"/* "$SITE"/.[!.]*; do
    [ -e "$entry" ] || continue
    if [ -d "$entry" ] && [ -f "$entry/build.json" ]; then
      continue
    fi
    rm -rf "$entry"
  done

  # 4. Add this build, prune old branch builds and render the home page.
  rm -rf "${SITE:?}/$TAG"
  cp -R "$STAGE" "$SITE/$TAG"
  python3 "$SCRIPT_DIR/pages.py" index \
    --site "$SITE" \
    --app-name "$APP_NAME" \
    --max-branch-builds "$MAX_BRANCH_BUILDS"
  touch "$SITE/.nojekyll"

  # 5. Commit everything as a single orphan commit. --force keeps *.ipa even if a .gitignore excludes it.
  site_git add -A --force .
  tree="$(site_git write-tree)"
  commit="$(git commit-tree "$tree" -m "Publish $TAG")"

  # 6. Push only if nobody else published since we fetched (empty lease = branch must not exist yet).
  if git push --force-with-lease="refs/heads/$PAGES_BRANCH:$lease" "$REMOTE" "$commit:refs/heads/$PAGES_BRANCH"; then
    echo "Published $TAG: ${BASE_URL%/}/$TAG/"
    exit 0
  fi
  echo "Push rejected, probably because another build published at the same time. Retrying…"
  sleep $((attempt * 5))
done

echo "::error::Could not publish $TAG to $PAGES_BRANCH after $MAX_ATTEMPTS attempts."
exit 1
