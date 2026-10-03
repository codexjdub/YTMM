#!/bin/sh
# Publishes the version set in build.sh as a GitHub release, with YTMM-<version>.zip attached.
# Signs with SIGN_IDENTITY (default: codexjdub). Needs the GitHub CLI (gh), signed in.
set -e
cd "$(dirname "$0")"

version=$(sed -n 's/^version=//p' build.sh)
tag="v$version"
zip="YTMM-$version.zip"

# Release only committed, pushed code from main that passed GitHub's build check, and never reuse a version.
[ "$(git branch --show-current)" = main ] || { echo "Release from main."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first."; exit 1; }
git fetch -q --tags origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse "@{upstream}")" ] || { echo "Push your commits first."; exit 1; }
[ "$(gh run list --commit "$(git rev-parse HEAD)" --workflow build.yml --json conclusion -q '.[0].conclusion')" = success ] \
    || { echo "Wait for GitHub's build check to pass for this commit."; exit 1; }
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "$tag already exists; bump version in build.sh."; exit 1; }

SIGN_IDENTITY="${SIGN_IDENTITY:-codexjdub}" ./build.sh

# Leave out file attributes (e.g. iCloud Drive's), which would fail strict signature checks.
rm -f "$zip"
ditto -c -k --norsrc --noextattr --noacl --keepParent YTMM.app "$zip"
sum=$(shasum -a 256 "$zip" | cut -d' ' -f1)

previous=$(git describe --tags --abbrev=0 2>/dev/null || true)
changes=$(git log --format='- %s' ${previous:+"$previous..HEAD"})

gh release create "$tag" "$zip" --target "$(git rev-parse HEAD)" \
    --title "YTMM $version: YouTube Music Menu" --notes "YouTube Music in your Mac's menu bar.

**Changes**
$changes

**Install:** Download \`$zip\`, unzip it, move \`YTMM.app\` to Applications and open it. macOS blocks it the first time because it isn't notarized by Apple. Go to System Settings → Privacy & Security and click **Open Anyway**.

SHA-256 of the zip: \`$sum\`"
rm "$zip"
git fetch -q --tags origin
