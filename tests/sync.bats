#!/usr/bin/env bats
load test_helper/common

setup() {
  TEST_DIR="$(mktemp -d)"
  NOMADIC_DIR="$TEST_DIR/nomadic"
  mkdir -p "$NOMADIC_DIR"

  # setup_bindle_repo clones into g_bindle_dir; mirror what cmd_init does.
  g_bindle_dir="$NOMADIC_DIR/bindle"

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

@test "setup_bindle_repo: clones into g_bindle_dir" {
  setup_bindle_repo "$REMOTE_REPO"

  [ -d "$NOMADIC_DIR/bindle/.git" ]
  [ -f "$NOMADIC_DIR/bindle/modules/test/bash" ]
}

@test "setup_bindle_repo: errors if a bindle already exists at target" {
  setup_bindle_repo "$REMOTE_REPO"

  run setup_bindle_repo "$REMOTE_REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already set up"* ]]
}

@test "setup_bindle_repo: clones with submodules" {
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

  setup_bindle_repo "$REMOTE_REPO"

  [ -f "$NOMADIC_DIR/bindle/modules/sub/data.txt" ]
}
