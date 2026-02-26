#!/usr/bin/env bats
load test_helper/common

@test "init creates config directory structure" {
  run cmd_init "$TEST_DIR/new-config"
  [ "$status" -eq 0 ]
  [ -d "$TEST_DIR/new-config/profiles" ]
  [ -d "$TEST_DIR/new-config/modules/path" ]
  [ -d "$TEST_DIR/new-config/modules/color" ]
  [ -d "$TEST_DIR/new-config/modules/prompt" ]
}

@test "init creates default profile" {
  cmd_init "$TEST_DIR/new-config"
  [ -f "$TEST_DIR/new-config/profiles/default" ]
  run cat "$TEST_DIR/new-config/profiles/default"
  [[ "$output" == *"path"* ]]
  [[ "$output" == *"color"* ]]
  [[ "$output" == *"prompt"* ]]
}

@test "init creates module bash files" {
  cmd_init "$TEST_DIR/new-config"
  [ -f "$TEST_DIR/new-config/modules/path/bash" ]
  [ -f "$TEST_DIR/new-config/modules/color/bash" ]
  [ -f "$TEST_DIR/new-config/modules/prompt/bash" ]
}

@test "init creates deps files with after: directives" {
  cmd_init "$TEST_DIR/new-config"
  run cat "$TEST_DIR/new-config/modules/color/deps"
  [ "$output" = "after: path" ]
  run cat "$TEST_DIR/new-config/modules/prompt/deps"
  [ "$output" = "after: color" ]
}

@test "init fails if modules/ already exists" {
  mkdir -p "$TEST_DIR/new-config/modules"
  run cmd_init "$TEST_DIR/new-config"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "init defaults to ~/.nomad" {
  HOME="$TEST_DIR" cmd_init
  [ -d "$TEST_DIR/.nomad/modules" ]
  [ -d "$TEST_DIR/.nomad/profiles" ]
}
