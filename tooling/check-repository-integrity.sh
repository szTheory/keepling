#!/usr/bin/env sh
set -eu

repository_root=$(git rev-parse --show-toplevel)
cd "$repository_root"

nested_git=$(find . -mindepth 2 \( -type d -o -type f \) -name .git -print -quit)
if [ -n "$nested_git" ]; then
  echo "Nested Git metadata is not allowed: $nested_git" >&2
  exit 1
fi

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

