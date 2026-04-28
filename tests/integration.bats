#!/usr/bin/env bats

# Integration tests - run nomadic as a standalone script and verify
# the full pipeline in a subprocess shell.

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_BINDLE="$TEST_DIR/config"
  mkdir -p "$TEST_BINDLE/modules" "$TEST_BINDLE/profiles"
  NOMADIC_DIR="$TEST_DIR/state"
  HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  NOMADIC_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: run nomadic as a standalone script with isolated env
run_nomadic() {
  env HOME="$HOME" NOMADIC_HOME="$NOMADIC_DIR" \
    "$NOMADIC_ROOT/nomadic" "$@"
}

# Helper: spawn a clean bash that sources the infected ~/.bashrc
run_shell() {
  env HOME="$HOME" NOMADIC_HOME="$NOMADIC_DIR" \
    bash --norc --noprofile -c "source '$HOME/.bashrc' && $1"
}

@test "integration: init, apply, env var active in new shell" {
  # Use a fresh path so init can create the directory structure
  TEST_BINDLE="$TEST_DIR/fresh-config"
  run_nomadic init "$TEST_BINDLE"

  # Add a test variable to one of the init-created modules
  printf 'export NOMADIC_TEST_VAR="hello"\n' >>"$TEST_BINDLE/modules/path/bash"

  run_nomadic apply -P "$TEST_BINDLE"

  # Verify a new shell sees the variable
  result="$(run_shell 'echo $NOMADIC_TEST_VAR')"
  [ "$result" = "hello" ]
}

@test "integration: apply exports from multiple modules visible in shell" {
  mkdir -p "$TEST_BINDLE/modules/alpha" "$TEST_BINDLE/modules/beta"
  printf 'export ALPHA="one"\n' >"$TEST_BINDLE/modules/alpha/bash"
  printf 'export BETA="two"\n' >"$TEST_BINDLE/modules/beta/bash"
  printf 'alpha\nbeta\n' >"$TEST_BINDLE/profiles/default"

  run_nomadic apply -P "$TEST_BINDLE"

  result="$(run_shell 'echo ${ALPHA}-${BETA}')"
  [ "$result" = "one-two" ]
}

@test "integration: symlinks created and config active after apply" {
  mkdir -p "$TEST_BINDLE/modules/dotfiles"
  echo "my config content" >"$TEST_BINDLE/modules/dotfiles/myrc"
  printf 'myrc %s/.myrc\n' "$HOME" >"$TEST_BINDLE/modules/dotfiles/links"
  printf 'export DOTS="yes"\n' >"$TEST_BINDLE/modules/dotfiles/bash"
  printf 'dotfiles\n' >"$TEST_BINDLE/profiles/default"

  run_nomadic apply -P "$TEST_BINDLE"

  # Symlink exists
  [ -L "$HOME/.myrc" ]

  # Config active in new shell
  result="$(run_shell 'echo $DOTS')"
  [ "$result" = "yes" ]
}

@test "integration: dependency ordering preserved in shell" {
  mkdir -p "$TEST_BINDLE/modules/base" "$TEST_BINDLE/modules/app"
  printf 'export BASE="loaded"\n' >"$TEST_BINDLE/modules/base/bash"
  printf 'after: base\n' >"$TEST_BINDLE/modules/app/deps"
  printf 'export APP="${BASE}:app"\n' >"$TEST_BINDLE/modules/app/bash"
  printf 'base\napp\n' >"$TEST_BINDLE/profiles/default"

  run_nomadic apply -P "$TEST_BINDLE"

  result="$(run_shell 'echo $APP')"
  [ "$result" = "loaded:app" ]
}

@test "integration: apply with git URL containing submodules" {
  export GIT_CONFIG_COUNT=3
  export GIT_CONFIG_KEY_0=protocol.file.allow
  export GIT_CONFIG_VALUE_0=always
  export GIT_CONFIG_KEY_1=user.email
  export GIT_CONFIG_VALUE_1=test@test.com
  export GIT_CONFIG_KEY_2=user.name
  export GIT_CONFIG_VALUE_2=Test

  # Create a submodule repo
  local sub_remote="$TEST_DIR/sub.git"
  git init --bare "$sub_remote" 2>/dev/null
  local sub_work="$TEST_DIR/sub-work"
  git clone "$sub_remote" "$sub_work" 2>/dev/null
  printf 'submodule data\n' >"$sub_work/init.lua"
  git -C "$sub_work" add -A
  git -C "$sub_work" commit -m "sub init" 2>/dev/null
  git -C "$sub_work" push 2>/dev/null

  # Create a config repo with a submodule inside modules/
  local bindle_remote="$TEST_DIR/config-remote.git"
  git init --bare "$bindle_remote" 2>/dev/null
  local bindle_work="$TEST_DIR/config-work"
  git clone "$bindle_remote" "$bindle_work" 2>/dev/null
  mkdir -p "$bindle_work/modules/shell"
  printf 'export SUB_TEST="yes"\n' >"$bindle_work/modules/shell/bash"
  git -C "$bindle_work" add -A
  git -C "$bindle_work" commit -m "add shell module" 2>/dev/null
  git -C "$bindle_work" submodule add "$sub_remote" modules/nvim 2>/dev/null
  git -C "$bindle_work" commit -m "add nvim submodule" 2>/dev/null
  git -C "$bindle_work" push 2>/dev/null

  # Apply via git URL - this is where the bug was: submodule checkout
  # output got mixed into the config path
  run env HOME="$HOME" NOMADIC_HOME="$NOMADIC_DIR" \
    GIT_CONFIG_COUNT=3 \
    GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
    GIT_CONFIG_KEY_1=user.email GIT_CONFIG_VALUE_1=test@test.com \
    GIT_CONFIG_KEY_2=user.name GIT_CONFIG_VALUE_2=Test \
    "$NOMADIC_ROOT/nomadic" apply --no-packages "file://$bindle_remote"
  [ "$status" -eq 0 ]
  [ -f "$NOMADIC_DIR/bindle/modules/nvim/init.lua" ]
}

@test "integration: module with pkg directive does not cause unbound variable" {
  mkdir -p "$TEST_BINDLE/modules/tool"
  printf 'export TOOL="yes"\n' >"$TEST_BINDLE/modules/tool/bash"
  printf 'pkg: some-package\n' >"$TEST_BINDLE/modules/tool/deps"
  printf 'tool\n' >"$TEST_BINDLE/profiles/default"

  # Run apply with a pkg: directive. The bug was an unbound variable
  # reference that crashed when _mod_pkg was set but empty-ish.
  # --no-packages skips bulk install; we just need the script to not crash.
  run env HOME="$HOME" NOMADIC_HOME="$NOMADIC_DIR" \
    "$NOMADIC_ROOT/nomadic" apply --no-packages "$TEST_BINDLE"
  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]]
}
