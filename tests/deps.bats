#!/usr/bin/env bats
load test_helper/common

@test "parses all deps directives" {
  create_module "mymod"
  printf '%s\n' 'after: homebrew packages' 'pkg: gnu-sed neovim' 'cmd: gsed' 'os: macos' \
    >"$TEST_CONFIG/modules/mymod/deps"

  run parse_deps "$TEST_CONFIG/modules/mymod/deps"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'AFTER=homebrew packages'
  echo "$output" | grep -q 'PKG=gnu-sed neovim'
  echo "$output" | grep -q 'CMD=gsed'
  echo "$output" | grep -q 'OS=macos'
}

@test "handles missing deps file gracefully" {
  create_module "nodeps"

  run parse_deps "$TEST_CONFIG/modules/nodeps/deps"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "skips blank lines and comments" {
  create_module "mymod"
  printf '%s\n' '# This is a comment' '' 'after: homebrew' '' '# Another comment' 'pkg: jq' \
    >"$TEST_CONFIG/modules/mymod/deps"

  run parse_deps "$TEST_CONFIG/modules/mymod/deps"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'AFTER=homebrew'
  echo "$output" | grep -q 'PKG=jq'
}

@test "strips inline comments" {
  create_module "mymod"
  printf 'after: homebrew  # needs brew first\n' >"$TEST_CONFIG/modules/mymod/deps"

  run parse_deps "$TEST_CONFIG/modules/mymod/deps"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'AFTER=homebrew'
  ! echo "$output" | grep -q 'needs'
}

@test "warns on unknown directives" {
  create_module "mymod"
  printf '%s\n' 'after: foo' 'bogus: something' >"$TEST_CONFIG/modules/mymod/deps"

  run parse_deps "$TEST_CONFIG/modules/mymod/deps"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'AFTER=foo'
  echo "$output" | grep -q 'WARN'
}

@test "handles deps file with only after:" {
  create_module "mymod" "after: packages"

  run parse_deps "$TEST_CONFIG/modules/mymod/deps"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'AFTER=packages'
  ! echo "$output" | grep -q 'PKG='
  ! echo "$output" | grep -q 'CMD='
  ! echo "$output" | grep -q 'OS='
}

@test "load_module_deps populates all fields" {
  create_module "mymod"
  printf '%s\n' 'after: homebrew packages' 'pkg: jq' >"$TEST_CONFIG/modules/mymod/deps"

  load_module_deps "$TEST_CONFIG" "mymod"
  [ "${_mod_after[0]}" = "homebrew packages" ]
  [ "${_mod_pkg[0]}" = "jq" ]
  [ -z "${_mod_cmd[0]}" ]
  [ -z "${_mod_os[0]}" ]
}

@test "load_module_deps handles missing deps file" {
  create_module "mymod"

  load_module_deps "$TEST_CONFIG" "mymod"
  [ -z "${_mod_after[0]}" ]
  [ -z "${_mod_pkg[0]}" ]
}

@test "load_module_deps loads multiple modules" {
  create_module "alpha" "after: beta"
  create_module "beta" "pkg: jq"

  load_module_deps "$TEST_CONFIG" "alpha" "beta"
  [ "${_mod_after[0]}" = "beta" ]
  [ -z "${_mod_pkg[0]}" ]
  [ -z "${_mod_after[1]}" ]
  [ "${_mod_pkg[1]}" = "jq" ]
}

@test "load_module_deps handles trailing whitespace" {
  create_module "mymod"
  printf 'after: homebrew   \npkg: jq   \n' >"$TEST_CONFIG/modules/mymod/deps"

  load_module_deps "$TEST_CONFIG" "mymod"
  [ "${_mod_after[0]}" = "homebrew" ]
  [ "${_mod_pkg[0]}" = "jq" ]
}
