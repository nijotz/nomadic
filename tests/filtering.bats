#!/usr/bin/env bats
load test_helper/common

@test "filter_by_os: module with no os: constraint passes on any OS" {
  create_module "alpha"
  load_modules
  g_current_os="macos"
  filter_by_os
  [ "${#g_module_name[@]}" -eq 1 ]
  [ "${g_module_name[0]}" = "alpha" ]
}

@test "filter_by_os: module with matching os: passes" {
  create_module "brew" "os: macos"
  load_modules
  g_current_os="macos"
  filter_by_os
  [ "${#g_module_name[@]}" -eq 1 ]
  [ "${g_module_name[0]}" = "brew" ]
}

@test "filter_by_os: module with non-matching os: is filtered out" {
  create_module "brew" "os: macos"
  load_modules
  g_current_os="ubuntu"
  filter_by_os
  [ "${#g_module_name[@]}" -eq 0 ]
}

@test "filter_by_os: module with multiple os: values" {
  create_module "mymod" "os: macos linux"

  g_current_os="macos"
  load_modules
  filter_by_os
  [ "${#g_module_name[@]}" -eq 1 ]

  g_current_os="ubuntu"
  load_modules
  filter_by_os
  [ "${#g_module_name[@]}" -eq 1 ]
}

@test "filter_by_os: linux matches ubuntu and arch" {
  create_module "mymod" "os: linux"

  g_current_os="ubuntu"
  load_modules
  filter_by_os
  [ "${#g_module_name[@]}" -eq 1 ]

  g_current_os="arch"
  load_modules
  filter_by_os
  [ "${#g_module_name[@]}" -eq 1 ]

  g_current_os="macos"
  load_modules
  filter_by_os
  [ "${#g_module_name[@]}" -eq 0 ]
}

@test "filter_by_os: filters multiple modules correctly" {
  create_module "alpha"
  create_module "brew" "os: macos"
  create_module "apt" "os: ubuntu"

  g_current_os="macos"
  load_modules
  filter_by_os
  [ "${#g_module_name[@]}" -eq 2 ]
  [ "${g_module_name[0]}" = "alpha" ]
  [ "${g_module_name[1]}" = "brew" ]
}

@test "filter_by_os: preserves load order" {
  create_module "alpha"
  create_module "bravo"
  create_module "charlie"

  g_current_os="macos"
  load_modules
  filter_by_os
  [ "${#g_module_name[@]}" -eq 3 ]
  [ "${g_module_name[0]}" = "alpha" ]
  [ "${g_module_name[1]}" = "bravo" ]
  [ "${g_module_name[2]}" = "charlie" ]
}

@test "filter_by_os: also filters g_module_pkg globals" {
  create_module "htop" "pkg: htop"
  create_module "iterm2" "$(printf 'os: macos\npkg: iterm2')"

  g_current_os="ubuntu"
  load_modules
  filter_by_os
  [ "${#g_module_name[@]}" -eq 1 ]
  [ "${g_module_pkg[0]}" = "htop" ]
}
