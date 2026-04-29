#!/usr/bin/env bats
load test_helper/common

# Override common setup - init tests configure their own bindle path per test.
setup() {
  TEST_DIR="$(mktemp -d)"
  NOMADIC_DIR="$TEST_DIR/nomadic"
}

@test "init creates bindle directory structure" {
  g_bindle_dir="$TEST_DIR/new-config"
  run cmd_init
  [ "$status" -eq 0 ]
  [ -d "$TEST_DIR/new-config/modules/path" ]
  [ -d "$TEST_DIR/new-config/modules/color" ]
  [ -d "$TEST_DIR/new-config/modules/aliases" ]
  [ -d "$TEST_DIR/new-config/modules/prompt" ]
  [ -d "$TEST_DIR/new-config/modules/git" ]
  [ -d "$TEST_DIR/new-config/packages" ]
}

@test "init creates module bash files" {
  g_bindle_dir="$TEST_DIR/new-config"
  cmd_init
  [ -f "$TEST_DIR/new-config/modules/path/bash" ]
  [ -f "$TEST_DIR/new-config/modules/color/bash" ]
  [ -f "$TEST_DIR/new-config/modules/color/bash.macos" ]
  [ -f "$TEST_DIR/new-config/modules/aliases/bash" ]
  [ -f "$TEST_DIR/new-config/modules/prompt/bash" ]
}

@test "init creates deps files with ordering and packages" {
  g_bindle_dir="$TEST_DIR/new-config"
  cmd_init
  run cat "$TEST_DIR/new-config/modules/color/deps"
  [ "$output" = "after: path" ]
  run cat "$TEST_DIR/new-config/modules/prompt/deps"
  [ "$output" = "after: color" ]
  run cat "$TEST_DIR/new-config/modules/aliases/deps"
  [ "$output" = "after: color" ]
  run cat "$TEST_DIR/new-config/modules/git/deps"
  [ "$output" = "pkg: git" ]
}

@test "init creates git module with links file" {
  g_bindle_dir="$TEST_DIR/new-config"
  cmd_init
  [ -f "$TEST_DIR/new-config/modules/git/gitconfig" ]
  [ -f "$TEST_DIR/new-config/modules/git/links" ]
  run cat "$TEST_DIR/new-config/modules/git/links"
  [[ "$output" == *"gitconfig"* ]]
  [[ "$output" == *".gitconfig"* ]]
}

@test "init creates base package list" {
  g_bindle_dir="$TEST_DIR/new-config"
  cmd_init
  [ -f "$TEST_DIR/new-config/packages/packages" ]
  run cat "$TEST_DIR/new-config/packages/packages"
  [[ "$output" == *"git"* ]]
  [[ "$output" == *"curl"* ]]
}

@test "init fails if modules/ already exists" {
  mkdir -p "$TEST_DIR/new-config/modules"
  g_bindle_dir="$TEST_DIR/new-config"
  run cmd_init
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "init defaults to NOMADIC_DIR/bindle" {
  cmd_init
  [ -d "$NOMADIC_DIR/bindle/modules" ]
}

@test "init persists path to state file" {
  g_bindle_dir="$TEST_DIR/new-config"
  cmd_init
  [ -f "$NOMADIC_DIR/state/bindle-path" ]
  [ "$(cat "$NOMADIC_DIR/state/bindle-path")" = "$TEST_DIR/new-config" ]
}

@test "init <path> registers existing bindle" {
  mkdir -p "$TEST_DIR/existing/modules"
  run cmd_init "$TEST_DIR/existing"
  [ "$status" -eq 0 ]
  [ "$(cat "$NOMADIC_DIR/state/bindle-path")" = "$TEST_DIR/existing" ]
}

@test "init <path> errors when path is not a bindle" {
  mkdir -p "$TEST_DIR/empty"
  run cmd_init "$TEST_DIR/empty"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No bindle found"* ]]
}

@test "init -B with positional path errors" {
  mkdir -p "$TEST_DIR/foo/modules"
  g_bindle_dir="$TEST_DIR/bar"
  run cmd_init "$TEST_DIR/foo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"both specify where the bindle"* ]]
}
