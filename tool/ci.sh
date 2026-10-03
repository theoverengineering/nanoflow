#!/usr/bin/env bash
# CI for the whole repository: dependencies, formatting, analysis and tests of
# every workspace member and of the Flutter app. Runs from the repository
# root, wherever it is started.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# The members listed under `workspace:` in the root pubspec.
dart_members=()
while IFS= read -r member; do
  dart_members+=("$member")
done < <(sed -n '/^workspace:/,/^[^ ]/s/^  - //p' pubspec.yaml)
# Nothing found would pass with nothing checked.
((${#dart_members[@]})) || {
  echo 'no workspace members found' >&2
  exit 1
}

dart pub get

dart format --output=none --set-exit-if-changed .

dart analyze --fatal-infos "${dart_members[@]}"

# The example's graph file must be what describe reads from its code now.
echo "== describe --check: examples/review"
(cd examples/review && dart run nanoflow_describe --check)

for member in "${dart_members[@]}"; do
  if [[ -d $member/test ]]; then
    echo "== dart test: $member"
    (cd "$member" && dart test)
  fi
done

# The Flutter app is outside the workspace (README «Репозиторий»): it has its
# own dependencies, and flutter checks it.
ui=apps/nanoflow_ui
echo "== flutter: $ui"
(cd "$ui" && flutter pub get && flutter analyze && flutter test)
