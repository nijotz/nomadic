#!/usr/bin/env bats

# Integration tests — run nomad as a standalone script and verify
# the full pipeline in a subprocess shell.

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_CONFIG="$TEST_DIR/config"
  mkdir -p "$TEST_CONFIG/modules" "$TEST_CONFIG/profiles"
  NOMAD_STATE_DIR="$TEST_DIR/state"
  HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  NOMAD_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: run nomad as a standalone script with isolated env
run_nomad() {
  env HOME="$HOME" NOMAD_STATE_DIR="$NOMAD_STATE_DIR" \
    "$NOMAD_ROOT/nomad" "$@"
}

# Helper: spawn a clean bash that sources the infected ~/.bashrc
run_shell() {
  env HOME="$HOME" NOMAD_STATE_DIR="$NOMAD_STATE_DIR" \
    bash --norc --noprofile -c "source '$HOME/.bashrc' && $1"
}

@test "integration: init, apply, env var active in new shell" {
  # Use a fresh path so init can create the directory structure
  TEST_CONFIG="$TEST_DIR/fresh-config"
  run_nomad init "$TEST_CONFIG"

  # Add a test variable to one of the init-created modules
  printf 'export NOMAD_TEST_VAR="hello"\n' >>"$TEST_CONFIG/modules/path/bash"

  run_nomad apply "$TEST_CONFIG"

  # Verify a new shell sees the variable
  result="$(run_shell 'echo $NOMAD_TEST_VAR')"
  [ "$result" = "hello" ]
}

@test "integration: apply exports from multiple modules visible in shell" {
  mkdir -p "$TEST_CONFIG/modules/alpha" "$TEST_CONFIG/modules/beta"
  printf 'export ALPHA="one"\n' >"$TEST_CONFIG/modules/alpha/bash"
  printf 'export BETA="two"\n' >"$TEST_CONFIG/modules/beta/bash"
  printf 'alpha\nbeta\n' >"$TEST_CONFIG/profiles/default"

  run_nomad apply "$TEST_CONFIG"

  result="$(run_shell 'echo ${ALPHA}-${BETA}')"
  [ "$result" = "one-two" ]
}

@test "integration: symlinks created and config active after apply" {
  mkdir -p "$TEST_CONFIG/modules/dotfiles"
  echo "my config content" >"$TEST_CONFIG/modules/dotfiles/myrc"
  printf 'myrc %s/.myrc\n' "$HOME" >"$TEST_CONFIG/modules/dotfiles/links"
  printf 'export DOTS="yes"\n' >"$TEST_CONFIG/modules/dotfiles/bash"
  printf 'dotfiles\n' >"$TEST_CONFIG/profiles/default"

  run_nomad apply "$TEST_CONFIG"

  # Symlink exists
  [ -L "$HOME/.myrc" ]

  # Config active in new shell
  result="$(run_shell 'echo $DOTS')"
  [ "$result" = "yes" ]
}

@test "integration: dependency ordering preserved in shell" {
  mkdir -p "$TEST_CONFIG/modules/base" "$TEST_CONFIG/modules/app"
  printf 'export BASE="loaded"\n' >"$TEST_CONFIG/modules/base/bash"
  printf 'after: base\n' >"$TEST_CONFIG/modules/app/deps"
  printf 'export APP="${BASE}:app"\n' >"$TEST_CONFIG/modules/app/bash"
  printf 'base\napp\n' >"$TEST_CONFIG/profiles/default"

  run_nomad apply "$TEST_CONFIG"

  result="$(run_shell 'echo $APP')"
  [ "$result" = "loaded:app" ]
}

@test "integration: module with pkg directive does not cause unbound variable" {
  mkdir -p "$TEST_CONFIG/modules/tool"
  printf 'export TOOL="yes"\n' >"$TEST_CONFIG/modules/tool/bash"
  printf 'pkg: some-package\n' >"$TEST_CONFIG/modules/tool/deps"
  printf 'tool\n' >"$TEST_CONFIG/profiles/default"

  # Hide brew so install_module_packages skips without actually installing.
  # The bug was an unbound variable reference that crashed before even
  # reaching the package manager.
  run env HOME="$HOME" NOMAD_STATE_DIR="$NOMAD_STATE_DIR" \
    PATH="/usr/bin:/bin" "$NOMAD_ROOT/nomad" apply --no-packages "$TEST_CONFIG"
  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]]
}
