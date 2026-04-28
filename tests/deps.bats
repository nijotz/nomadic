#!/usr/bin/env bats
load test_helper/common

@test "load_modules populates all fields" {
  create_module "mymod"
  printf '%s\n' 'after: homebrew packages' 'pkg: jq' >"$TEST_BINDLE/modules/mymod/deps"

  load_modules "$TEST_BINDLE" "mymod"
  [ "${g_module_after[0]}" = "homebrew packages" ]
  [ "${g_module_pkg[0]}" = "jq" ]
  [ -z "${g_module_os[0]}" ]
}

@test "load_modules handles missing deps file" {
  create_module "mymod"

  load_modules "$TEST_BINDLE" "mymod"
  [ -z "${g_module_after[0]}" ]
  [ -z "${g_module_pkg[0]}" ]
}

@test "load_modules loads multiple modules" {
  create_module "alpha" "after: beta"
  create_module "beta" "pkg: jq"

  load_modules "$TEST_BINDLE" "alpha" "beta"
  [ "${g_module_after[0]}" = "beta" ]
  [ -z "${g_module_pkg[0]}" ]
  [ -z "${g_module_after[1]}" ]
  [ "${g_module_pkg[1]}" = "jq" ]
}

@test "load_modules handles trailing whitespace" {
  create_module "mymod"
  printf 'after: homebrew   \npkg: jq   \n' >"$TEST_BINDLE/modules/mymod/deps"

  load_modules "$TEST_BINDLE" "mymod"
  [ "${g_module_after[0]}" = "homebrew" ]
  [ "${g_module_pkg[0]}" = "jq" ]
}

@test "load_modules skips blank lines and comments" {
  create_module "mymod"
  printf '%s\n' '# comment' '' 'after: homebrew' '' '# another' 'pkg: jq' \
    >"$TEST_BINDLE/modules/mymod/deps"

  load_modules "$TEST_BINDLE" "mymod"
  [ "${g_module_after[0]}" = "homebrew" ]
  [ "${g_module_pkg[0]}" = "jq" ]
}

@test "load_modules strips inline comments" {
  create_module "mymod"
  printf 'after: homebrew  # needs brew first\n' >"$TEST_BINDLE/modules/mymod/deps"

  load_modules "$TEST_BINDLE" "mymod"
  [ "${g_module_after[0]}" = "homebrew" ]
}

@test "load_modules warns on unknown directives" {
  create_module "mymod"
  printf '%s\n' 'after: foo' 'bogus: something' >"$TEST_BINDLE/modules/mymod/deps"

  run load_modules "$TEST_BINDLE" "mymod"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'WARN'
}
