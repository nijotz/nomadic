#!/usr/bin/env bats
load test_helper/common

@test "filter_by_os: module with no os: constraint passes on any OS" {
  create_module "alpha"
  load_modules "$TEST_CONFIG" "alpha"

  result="$(filter_by_os "macos" "alpha")"
  [ "$result" = "alpha" ]
}

@test "filter_by_os: module with matching os: passes" {
  create_module "brew" "os: macos"
  load_modules "$TEST_CONFIG" "brew"

  result="$(filter_by_os "macos" "brew")"
  [ "$result" = "brew" ]
}

@test "filter_by_os: module with non-matching os: is filtered out" {
  create_module "brew" "os: macos"
  load_modules "$TEST_CONFIG" "brew"

  result="$(filter_by_os "ubuntu" "brew")"
  [ -z "$result" ]
}

@test "filter_by_os: module with multiple os: values" {
  create_module "mymod" "os: macos linux"
  load_modules "$TEST_CONFIG" "mymod"

  result_mac="$(filter_by_os "macos" "mymod")"
  result_ubu="$(filter_by_os "ubuntu" "mymod")"
  [ "$result_mac" = "mymod" ]
  [ "$result_ubu" = "mymod" ]
}

@test "filter_by_os: linux matches ubuntu and arch" {
  create_module "mymod" "os: linux"
  load_modules "$TEST_CONFIG" "mymod"

  result_ubu="$(filter_by_os "ubuntu" "mymod")"
  result_arch="$(filter_by_os "arch" "mymod")"
  result_mac="$(filter_by_os "macos" "mymod")"
  [ "$result_ubu" = "mymod" ]
  [ "$result_arch" = "mymod" ]
  [ -z "$result_mac" ]
}

@test "filter_by_os: filters multiple modules correctly" {
  create_module "alpha"
  create_module "brew" "os: macos"
  create_module "apt" "os: ubuntu"
  load_modules "$TEST_CONFIG" "alpha" "brew" "apt"

  result="$(filter_by_os "macos" "alpha" "brew" "apt")"
  [ "$(echo "$result" | sed -n '1p')" = "alpha" ]
  [ "$(echo "$result" | sed -n '2p')" = "brew" ]
  [ "$(echo "$result" | wc -l | tr -d ' ')" = "2" ]
}

@test "filter_by_os: preserves input order" {
  create_module "charlie"
  create_module "alpha"
  create_module "bravo"
  load_modules "$TEST_CONFIG" "charlie" "alpha" "bravo"

  result="$(filter_by_os "macos" "charlie" "alpha" "bravo")"
  [ "$(echo "$result" | sed -n '1p')" = "charlie" ]
  [ "$(echo "$result" | sed -n '2p')" = "alpha" ]
  [ "$(echo "$result" | sed -n '3p')" = "bravo" ]
}
