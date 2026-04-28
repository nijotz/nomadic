#!/usr/bin/env bats
load test_helper/common

setup() {
  TEST_DIR="$(mktemp -d)"
  NOMADIC_DIR="$TEST_DIR/nomadic"
  mkdir -p "$NOMADIC_DIR"

  # Allow local file:// transport for submodule tests
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=protocol.file.allow
  export GIT_CONFIG_VALUE_0=always

  # Create a bare git repo to act as the "remote"
  REMOTE_REPO="$TEST_DIR/remote.git"
  git init --bare "$REMOTE_REPO" 2>/dev/null

  # Create a working copy, add a commit, push to bare repo
  WORK_DIR="$TEST_DIR/work"
  git clone "$REMOTE_REPO" "$WORK_DIR" 2>/dev/null
  mkdir -p "$WORK_DIR/modules/test"
  printf 'export TEST="yes"\n' >"$WORK_DIR/modules/test/bash"
  git -C "$WORK_DIR" add -A
  git -C "$WORK_DIR" commit -m "initial" 2>/dev/null
  git -C "$WORK_DIR" push 2>/dev/null
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "setup_config_repo: clones repo to NOMADIC_DIR/config" {
  setup_config_repo "$REMOTE_REPO"

  [ "$g_config_dir" = "$NOMADIC_DIR/config" ]
  [ -d "$NOMADIC_DIR/config/.git" ]
  [ -f "$NOMADIC_DIR/config/modules/test/bash" ]
}

@test "setup_config_repo: persists path to state file" {
  setup_config_repo "$REMOTE_REPO"

  [ -f "$NOMADIC_DIR/state/config-path" ]
  [ "$(cat "$NOMADIC_DIR/state/config-path")" = "$NOMADIC_DIR/config" ]
}

@test "setup_config_repo: errors if repo already exists with same URL" {
  setup_config_repo "$REMOTE_REPO"

  run setup_config_repo "$REMOTE_REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already set up"* ]]
}

@test "setup_config_repo: errors if remote URL differs" {
  setup_config_repo "$REMOTE_REPO"

  run setup_config_repo "/some/other/repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"points to"* ]]
}

@test "setup_config_repo: clones with submodules" {
  # Create a repo to use as a submodule
  SUB_REPO="$TEST_DIR/sub.git"
  git init --bare "$SUB_REPO" 2>/dev/null
  SUB_WORK="$TEST_DIR/sub-work"
  git clone "$SUB_REPO" "$SUB_WORK" 2>/dev/null
  printf 'submodule content\n' >"$SUB_WORK/data.txt"
  git -C "$SUB_WORK" add -A
  git -C "$SUB_WORK" commit -m "sub initial" 2>/dev/null
  git -C "$SUB_WORK" push 2>/dev/null

  # Add it as a submodule in the main repo
  git -C "$WORK_DIR" submodule add "$SUB_REPO" modules/sub 2>/dev/null
  git -C "$WORK_DIR" commit -m "add submodule" 2>/dev/null
  git -C "$WORK_DIR" push 2>/dev/null

  setup_config_repo "$REMOTE_REPO"

  [ -f "$NOMADIC_DIR/config/modules/sub/data.txt" ]
}
