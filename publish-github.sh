#!/bin/bash
# Creates the public GitHub repo "perch", pushes the code, and publishes Perch.dmg as a release.
#
#   bash publish-github.sh            first time: create repo + release v2.0
#   VERSION=2.1 bash publish-github.sh   later: push changes + new release
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${VERSION:-2.0}"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub's command-line tool isn't installed. Run:  brew install gh"
  echo "then:  gh auth login   and run this again."
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "Sign in to GitHub first:  gh auth login"
  exit 1
fi

OWNER="$(gh api user -q .login)"
# Point the build-from-source instructions at your account
sed -i '' "s#YOUR-GITHUB-USERNAME#${OWNER}#g" README.md

# Keep the version in the app in step with the release
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist

echo "Building Perch.dmg…"
bash make-dmg.sh

if [ ! -d .git ]; then
  git init -q
  git branch -M main
fi
git add -A
git commit -q -m "Perch $VERSION" || echo "(nothing new to commit)"

if ! gh repo view "$OWNER/perch" >/dev/null 2>&1; then
  gh repo create perch --public --source . --remote origin \
    --description "A clean, fast macOS app for the cameras on your NVR. Works with Reolink." --push
else
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$OWNER/perch.git"
  git push -u origin main
fi

gh release create "v$VERSION" build/Perch.dmg \
  --title "Perch $VERSION" \
  --notes "Download **Perch.dmg**, open it and drag Perch to Applications. See the README for first-run steps (Open Anyway, ffmpeg, NVR settings)."

echo ""
echo "Done: https://github.com/$OWNER/perch"
