#!/usr/bin/env sh
set -eu

repository_root=$(git rev-parse --show-toplevel)
cd "$repository_root"

# Nested Git metadata is banned in repository CONTENT. Git-ignored paths are
# not content: SwiftPM checks its dependencies out under `apps/ios/.build/`
# (gitignored), and each checkout legitimately carries its own `.git`. A raw
# `find` does not honour .gitignore, so it failed this whole gate whenever the
# iOS app had simply been built. Check each hit against `git check-ignore` and
# skip the ignored ones; anything not ignored is still a hard failure, so an
# untracked-but-not-ignored nested clone is caught exactly as before.
find . -mindepth 2 \( -type d -o -type f \) -name .git -print | while IFS= read -r nested_git; do
  if git check-ignore -q "$nested_git"; then
    continue
  fi
  echo "Nested Git metadata is not allowed: $nested_git" >&2
  exit 1
done || exit 1

if [ -f .gitmodules ]; then
  echo "Git submodules are not allowed in the Keepling monorepo." >&2
  exit 1
fi

gitlinks=$(git ls-files --stage | awk '$1 == 160000 { print $4 }')
if [ -n "$gitlinks" ]; then
  echo "Tracked gitlinks are not allowed:" >&2
  echo "$gitlinks" >&2
  exit 1
fi

echo "Repository integrity checks passed."

