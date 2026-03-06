#!/usr/bin/env bats
load test_helper/common

@test "init creates config directory structure" {
  run cmd_init "$TEST_DIR/new-config"
  [ "$status" -eq 0 ]
  [ -d "$TEST_DIR/new-config/modules/path" ]
  [ -d "$TEST_DIR/new-config/modules/color" ]
  [ -d "$TEST_DIR/new-config/modules/aliases" ]
  [ -d "$TEST_DIR/new-config/modules/prompt" ]
  [ -d "$TEST_DIR/new-config/modules/git" ]
  [ -d "$TEST_DIR/new-config/packages" ]
}

@test "init creates module bash files" {
  cmd_init "$TEST_DIR/new-config"
  [ -f "$TEST_DIR/new-config/modules/path/bash" ]
  [ -f "$TEST_DIR/new-config/modules/color/bash" ]
  [ -f "$TEST_DIR/new-config/modules/color/bash.macos" ]
  [ -f "$TEST_DIR/new-config/modules/aliases/bash" ]
  [ -f "$TEST_DIR/new-config/modules/prompt/bash" ]
}

@test "init creates deps files with ordering and packages" {
  cmd_init "$TEST_DIR/new-config"
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
  cmd_init "$TEST_DIR/new-config"
  [ -f "$TEST_DIR/new-config/modules/git/gitconfig" ]
  [ -f "$TEST_DIR/new-config/modules/git/links" ]
  run cat "$TEST_DIR/new-config/modules/git/links"
  [[ "$output" == *"gitconfig"* ]]
  [[ "$output" == *".gitconfig"* ]]
}

@test "init creates base package list" {
  cmd_init "$TEST_DIR/new-config"
  [ -f "$TEST_DIR/new-config/packages/packages" ]
  run cat "$TEST_DIR/new-config/packages/packages"
  [[ "$output" == *"git"* ]]
  [[ "$output" == *"curl"* ]]
}

@test "init fails if modules/ already exists" {
  mkdir -p "$TEST_DIR/new-config/modules"
  run cmd_init "$TEST_DIR/new-config"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "init defaults to NOMADIC_DIR/config" {
  cmd_init
  [ -d "$NOMADIC_DIR/config/modules" ]
}
