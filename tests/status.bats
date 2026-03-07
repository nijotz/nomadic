#!/usr/bin/env bats
load test_helper/common

setup() {
  TEST_DIR="$(mktemp -d)"
  NOMADIC_DIR="$TEST_DIR/nomadic"
  mkdir -p "$NOMADIC_DIR"

  # Create a git-backed config directory
  CONFIG_DIR="$TEST_DIR/config"
  mkdir -p "$CONFIG_DIR/modules/test"
  printf 'export TEST="yes"\n' >"$CONFIG_DIR/modules/test/bash"
  git -C "$CONFIG_DIR" init 2>/dev/null
  git -C "$CONFIG_DIR" add -A
  git -C "$CONFIG_DIR" commit -m "initial" 2>/dev/null
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "check_config_drift: clean repo returns 0" {
  run check_config_drift "$CONFIG_DIR"
  [ "$status" -eq 0 ]
}

@test "check_config_drift: uncommitted changes returns 1" {
  printf 'modified\n' >"$CONFIG_DIR/modules/test/bash"

  run check_config_drift "$CONFIG_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes"* ]]
}

@test "check_config_drift: staged changes returns 1" {
  printf 'modified\n' >"$CONFIG_DIR/modules/test/bash"
  git -C "$CONFIG_DIR" add -A

  run check_config_drift "$CONFIG_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes"* ]]
}

@test "check_config_drift: untracked files returns 1" {
  printf 'new file\n' >"$CONFIG_DIR/modules/test/newfile"

  run check_config_drift "$CONFIG_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"untracked files"* ]]
}

@test "check_config_drift: non-git directory returns 0" {
  local plain_dir="$TEST_DIR/plain"
  mkdir -p "$plain_dir"

  run check_config_drift "$plain_dir"
  [ "$status" -eq 0 ]
}

@test "check_config_drift: unpushed commits returns 1" {
  # Set up a bare remote and push
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=protocol.file.allow
  export GIT_CONFIG_VALUE_0=always

  local remote="$TEST_DIR/remote.git"
  git init --bare "$remote" 2>/dev/null
  git -C "$CONFIG_DIR" remote add origin "$remote"
  git -C "$CONFIG_DIR" push -u origin main 2>/dev/null

  # Make a local commit without pushing
  printf 'new content\n' >"$CONFIG_DIR/modules/test/bash"
  git -C "$CONFIG_DIR" add -A
  git -C "$CONFIG_DIR" commit -m "local only" 2>/dev/null

  run check_config_drift "$CONFIG_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unpushed commit"* ]]
}

@test "check_config_drift: behind remote returns 1" {
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=protocol.file.allow
  export GIT_CONFIG_VALUE_0=always

  local remote="$TEST_DIR/remote.git"
  git init --bare "$remote" 2>/dev/null
  git -C "$CONFIG_DIR" remote add origin "$remote"
  git -C "$CONFIG_DIR" push -u origin main 2>/dev/null

  # Push a commit from another clone
  local other="$TEST_DIR/other"
  git clone "$remote" "$other" 2>/dev/null
  printf 'from other\n' >"$other/modules/test/bash"
  git -C "$other" add -A
  git -C "$other" commit -m "remote change" 2>/dev/null
  git -C "$other" push 2>/dev/null

  run check_config_drift "$CONFIG_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"behind remote"* ]]
}

@test "cmd_status: reports clean config" {
  run cmd_status "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]]
}

@test "cmd_status: reports dirty config" {
  printf 'modified\n' >"$CONFIG_DIR/modules/test/bash"

  run cmd_status "$CONFIG_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uncommitted changes"* ]]
}
