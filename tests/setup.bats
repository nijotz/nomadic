#!/usr/bin/env bats
load test_helper/common

@test "run_module_setup: sources setup script" {
  create_module "mymod"
  printf 'touch "%s/setup_ran"\n' "$TEST_DIR" >"$TEST_BINDLE/modules/mymod/setup"
  run_module_setup "mymod"
  [ -f "$TEST_DIR/setup_ran" ]
}

@test "run_module_setup: missing setup file is a no-op" {
  create_module "mymod"

  run run_module_setup "mymod"
  [ "$status" -eq 0 ]
}

@test "run_module_setup: setup script can modify environment" {
  create_module "mymod"
  printf 'SETUP_TEST_VAR="hello_from_setup"\n' >"$TEST_BINDLE/modules/mymod/setup"

  run_module_setup "mymod"
  [ "$SETUP_TEST_VAR" = "hello_from_setup" ]
}

@test "run_module_setup: setup script failure propagates" {
  create_module "mymod"
  printf 'false\n' >"$TEST_BINDLE/modules/mymod/setup"

  run run_module_setup "mymod"
  [ "$status" -ne 0 ]
}
