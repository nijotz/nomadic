#!/usr/bin/env bats
load test_helper/common

@test "filter_by_os: module with no os: constraint passes on any OS" {
  create_module "alpha"
  load_modules "$TEST_CONFIG" "alpha"

  filter_by_os "macos"
  [ "${#_mod_name[@]}" -eq 1 ]
  [ "${_mod_name[0]}" = "alpha" ]
}

@test "filter_by_os: module with matching os: passes" {
  create_module "brew" "os: macos"
  load_modules "$TEST_CONFIG" "brew"

  filter_by_os "macos"
  [ "${#_mod_name[@]}" -eq 1 ]
  [ "${_mod_name[0]}" = "brew" ]
}

@test "filter_by_os: module with non-matching os: is filtered out" {
  create_module "brew" "os: macos"
  load_modules "$TEST_CONFIG" "brew"

  filter_by_os "ubuntu"
  [ "${#_mod_name[@]}" -eq 0 ]
}

@test "filter_by_os: module with multiple os: values" {
  create_module "mymod" "os: macos linux"
  load_modules "$TEST_CONFIG" "mymod"

  filter_by_os "macos"
  [ "${#_mod_name[@]}" -eq 1 ]

  load_modules "$TEST_CONFIG" "mymod"
  filter_by_os "ubuntu"
  [ "${#_mod_name[@]}" -eq 1 ]
}

@test "filter_by_os: linux matches ubuntu and arch" {
  create_module "mymod" "os: linux"

  load_modules "$TEST_CONFIG" "mymod"
  filter_by_os "ubuntu"
  [ "${#_mod_name[@]}" -eq 1 ]

  load_modules "$TEST_CONFIG" "mymod"
  filter_by_os "arch"
  [ "${#_mod_name[@]}" -eq 1 ]

  load_modules "$TEST_CONFIG" "mymod"
  filter_by_os "macos"
  [ "${#_mod_name[@]}" -eq 0 ]
}

@test "filter_by_os: filters multiple modules correctly" {
  create_module "alpha"
  create_module "brew" "os: macos"
  create_module "apt" "os: ubuntu"
  load_modules "$TEST_CONFIG" "alpha" "brew" "apt"

  filter_by_os "macos"
  [ "${#_mod_name[@]}" -eq 2 ]
  [ "${_mod_name[0]}" = "alpha" ]
  [ "${_mod_name[1]}" = "brew" ]
}

@test "filter_by_os: preserves load order" {
  create_module "charlie"
  create_module "alpha"
  create_module "bravo"
  load_modules "$TEST_CONFIG" "charlie" "alpha" "bravo"

  filter_by_os "macos"
  [ "${#_mod_name[@]}" -eq 3 ]
  [ "${_mod_name[0]}" = "charlie" ]
  [ "${_mod_name[1]}" = "alpha" ]
  [ "${_mod_name[2]}" = "bravo" ]
}

@test "filter_by_os: also filters _mod_pkg globals" {
  create_module "htop" "pkg: htop"
  create_module "iterm2" "$(printf 'os: macos\npkg: iterm2')"
  load_modules "$TEST_CONFIG" "htop" "iterm2"

  filter_by_os "ubuntu"
  [ "${#_mod_name[@]}" -eq 1 ]
  [ "${_mod_pkg[0]}" = "htop" ]
}
