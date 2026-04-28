#!/usr/bin/env bats
load test_helper/common

@test "collect_shell_rc: static file is output verbatim" {
  create_module "mymod"
  printf 'export FOO="bar"\n' >"$TEST_BINDLE/modules/mymod/bash"

  result="$(collect_shell_rc "mymod" "bash")"
  echo "$result" | grep -q 'export FOO="bar"'
}

@test "collect_shell_rc: executable file stdout is captured" {
  create_module "mymod"
  printf '#!/usr/bin/env bash\necho "export DYNAMIC=yes"\n' >"$TEST_BINDLE/modules/mymod/bash"
  chmod +x "$TEST_BINDLE/modules/mymod/bash"

  result="$(collect_shell_rc "mymod" "bash")"
  echo "$result" | grep -q 'export DYNAMIC=yes'
}

@test "collect_shell_rc: missing config file produces no output" {
  create_module "mymod"

  result="$(collect_shell_rc "mymod" "bash")"
  [ -z "$result" ]
}

@test "collect_shell_rc: adds module name comment header" {
  create_module "mymod"
  printf 'export FOO="bar"\n' >"$TEST_BINDLE/modules/mymod/bash"

  result="$(collect_shell_rc "mymod" "bash")"
  echo "$result" | grep -q '# --- module: mymod -'
}

@test "collect_shell_rc: executable stderr passes through" {
  create_module "mymod"
  printf '#!/usr/bin/env bash\necho "config line" \necho "debug info" >&2\n' \
    >"$TEST_BINDLE/modules/mymod/bash"
  chmod +x "$TEST_BINDLE/modules/mymod/bash"

  # Capture stdout and stderr separately
  result="$(collect_shell_rc "mymod" "bash" 2>/dev/null)"
  echo "$result" | grep -q 'config line'
  ! echo "$result" | grep -q 'debug info'
}

@test "collect_shell_rc: works with zsh shell name" {
  create_module "mymod"
  printf 'export ZSH_THING="yes"\n' >"$TEST_BINDLE/modules/mymod/zsh"

  result="$(collect_shell_rc "mymod" "zsh")"
  echo "$result" | grep -q 'export ZSH_THING="yes"'
}

@test "collect_shell_rc: platform-specific file used when os matches" {
  create_module "mymod"
  printf 'export GENERIC="yes"\n' >"$TEST_BINDLE/modules/mymod/bash"
  printf 'export MACOS="yes"\n' >"$TEST_BINDLE/modules/mymod/bash.macos"
  g_current_os='macos'
  result="$(collect_shell_rc "mymod" "bash" "macos")"
  echo "$result" | grep -q 'export MACOS="yes"'
  ! echo "$result" | grep -q 'export GENERIC="yes"'
}

@test "collect_shell_rc: linux platform-specific file used on linux" {
  create_module "mymod"
  printf 'export GENERIC="yes"\n' >"$TEST_BINDLE/modules/mymod/bash"
  printf 'export LINUX="yes"\n' >"$TEST_BINDLE/modules/mymod/bash.linux"
  g_current_os='linux'
  result="$(collect_shell_rc "mymod" "bash" "linux")"
  echo "$result" | grep -q 'export LINUX="yes"'
  ! echo "$result" | grep -q 'export GENERIC="yes"'
}

@test "collect_shell_rc: falls back to generic when no platform file" {
  create_module "mymod"
  printf 'export GENERIC="yes"\n' >"$TEST_BINDLE/modules/mymod/bash"

  result="$(collect_shell_rc "mymod" "bash" "macos")"
  echo "$result" | grep -q 'export GENERIC="yes"'
}

@test "collect_shell_rc: wrong os platform file ignored, generic used" {
  create_module "mymod"
  printf 'export GENERIC="yes"\n' >"$TEST_BINDLE/modules/mymod/bash"
  printf 'export MACOS="yes"\n' >"$TEST_BINDLE/modules/mymod/bash.macos"

  result="$(collect_shell_rc "mymod" "bash" "linux")"
  echo "$result" | grep -q 'export GENERIC="yes"'
  ! echo "$result" | grep -q 'export MACOS="yes"'
}
