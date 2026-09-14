#!/usr/bin/env bats

load helpers/harness

@test "lint: shellcheck is clean across the scripts" {
  if ! command -v shellcheck >/dev/null; then skip "shellcheck not installed"; fi
  run shellcheck "$REPO_ROOT"/bin/omarchy-* "$REPO_ROOT/menu/omarchy-appimage-menu"
  [ "$status" -eq 0 ]
}

@test "lint: shfmt reports no diff at the project style" {
  if ! command -v shfmt >/dev/null; then skip "shfmt not installed"; fi
  run shfmt -d -i 2 -bn "$REPO_ROOT"/bin/omarchy-* "$REPO_ROOT/menu/omarchy-appimage-menu"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
