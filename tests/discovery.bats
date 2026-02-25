#!/usr/bin/env bats
load test_helper/common

@test "discovers modules in modules/ directory" {
  create_module "alpha"
  create_module "beta"
  create_module "gamma"

  run discover_modules "$TEST_CONFIG"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "alpha" ]
  [ "${lines[1]}" = "beta" ]
  [ "${lines[2]}" = "gamma" ]
}

@test "returns sorted module names" {
  create_module "zsh"
  create_module "alpha"
  create_module "middle"

  run discover_modules "$TEST_CONFIG"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "alpha" ]
  [ "${lines[1]}" = "middle" ]
  [ "${lines[2]}" = "zsh" ]
}

@test "skips hidden directories" {
  create_module "visible"
  mkdir -p "$TEST_CONFIG/modules/.hidden"

  run discover_modules "$TEST_CONFIG"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "visible" ]
}

@test "ignores regular files in modules/" {
  create_module "real-module"
  touch "$TEST_CONFIG/modules/README.md"

  run discover_modules "$TEST_CONFIG"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "real-module" ]
}

@test "returns error when modules/ does not exist" {
  rmdir "$TEST_CONFIG/modules"

  run discover_modules "$TEST_CONFIG"
  [ "$status" -eq 1 ]
}

@test "returns success with no output for empty modules/" {
  run discover_modules "$TEST_CONFIG"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
