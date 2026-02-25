#!/usr/bin/env bats
load test_helper/common

@test "sorts modules with no dependencies alphabetically" {
  create_module "charlie"
  create_module "alpha"
  create_module "bravo"

  result="$(run_toposort "$TEST_CONFIG" charlie alpha bravo)"
  [ "$(echo "$result" | sed -n '1p')" = "alpha" ]
  [ "$(echo "$result" | sed -n '2p')" = "bravo" ]
  [ "$(echo "$result" | sed -n '3p')" = "charlie" ]
}

@test "respects after: ordering" {
  create_module "homebrew"
  create_module "packages" "after: homebrew"
  create_module "gnu-sed" "after: packages"

  result="$(run_toposort "$TEST_CONFIG" gnu-sed homebrew packages)"
  [ "$(echo "$result" | sed -n '1p')" = "homebrew" ]
  [ "$(echo "$result" | sed -n '2p')" = "packages" ]
  [ "$(echo "$result" | sed -n '3p')" = "gnu-sed" ]
}

@test "handles diamond dependency" {
  create_module "A"
  create_module "B" "after: A"
  create_module "C" "after: A"
  create_module "D" "after: B C"

  result="$(run_toposort "$TEST_CONFIG" D C B A)"
  [ "$(echo "$result" | sed -n '1p')" = "A" ]
  [ "$(echo "$result" | sed -n '2p')" = "B" ]
  [ "$(echo "$result" | sed -n '3p')" = "C" ]
  [ "$(echo "$result" | sed -n '4p')" = "D" ]
}

@test "detects simple cycle" {
  create_module "foo" "after: bar"
  create_module "bar" "after: foo"

  run bash -c "source '$NOMAD_ROOT/nomad' && load_module_deps '$TEST_CONFIG' foo bar && toposort"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'cycle'
}

@test "detects three-node cycle" {
  create_module "A" "after: C"
  create_module "B" "after: A"
  create_module "C" "after: B"

  run bash -c "source '$NOMAD_ROOT/nomad' && load_module_deps '$TEST_CONFIG' A B C && toposort"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'cycle'
}

@test "ignores dependency on unknown module" {
  create_module "alpha" "after: nonexistent"
  create_module "beta"

  result="$(run_toposort "$TEST_CONFIG" alpha beta)"
  [ "$(echo "$result" | wc -l | tr -d ' ')" = "2" ]
}

@test "handles single module" {
  create_module "solo"

  result="$(run_toposort "$TEST_CONFIG" solo)"
  [ "$result" = "solo" ]
}

@test "handles empty input" {
  _modules=()
  _mod_after=()
  result="$(toposort)"
  [ -z "$result" ]
}

@test "realistic module set" {
  create_module "path"
  create_module "homebrew" "os: macos"
  create_module "packages" "after: homebrew"
  create_module "color"
  create_module "prompt" "after: color"
  create_module "gnu-sed" "after: packages
pkg: gnu-sed
os: macos"
  create_module "neovim" "pkg: nvim"
  create_module "git" "pkg: git"
  create_module "tmux" "pkg: tmux"

  result="$(run_toposort "$TEST_CONFIG" path homebrew packages color prompt gnu-sed neovim git tmux)"

  # Check ordering constraints
  homebrew_pos="$(echo "$result" | grep -n '^homebrew$' | cut -d: -f1)"
  packages_pos="$(echo "$result" | grep -n '^packages$' | cut -d: -f1)"
  gnu_sed_pos="$(echo "$result" | grep -n '^gnu-sed$' | cut -d: -f1)"
  color_pos="$(echo "$result" | grep -n '^color$' | cut -d: -f1)"
  prompt_pos="$(echo "$result" | grep -n '^prompt$' | cut -d: -f1)"

  [ "$homebrew_pos" -lt "$packages_pos" ]
  [ "$packages_pos" -lt "$gnu_sed_pos" ]
  [ "$color_pos" -lt "$prompt_pos" ]
}
