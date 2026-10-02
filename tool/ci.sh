#!/usr/bin/env bash
# CI for the whole workspace: dependencies, formatting, analysis and tests of
# every member. Runs from the repository root, wherever it is started.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

ui=apps/nanoflow_ui

has_ui() { [[ -f $ui/pubspec.yaml ]]; }

# The members listed under `workspace:` in the root pubspec, but the Flutter
# app: flutter checks that one.
dart_members=()
while IFS= read -r member; do
  [[ $member == "$ui" ]] || dart_members+=("$member")
done < <(sed -n '/^workspace:/,/^[^ ]/s/^  - //p' pubspec.yaml)
# Nothing found would pass with nothing checked.
((${#dart_members[@]})) || {
  echo 'no workspace members found' >&2
  exit 1
}

# A workspace with a Flutter member resolves only through flutter.
if has_ui; then
  flutter pub get
else
  dart pub get
fi

dart format --output=none --set-exit-if-changed .

dart analyze --fatal-infos "${dart_members[@]}"
if has_ui; then
  (cd "$ui" && flutter analyze)
fi

for member in "${dart_members[@]}"; do
  if [[ -d $member/test ]]; then
    echo "== dart test: $member"
    (cd "$member" && dart test)
  fi
done
if has_ui; then
  echo "== flutter test: $ui"
  (cd "$ui" && flutter test)
fi
