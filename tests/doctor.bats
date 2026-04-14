#!/usr/bin/env bats
load test_helper/common

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_CONFIG="$TEST_DIR/config"
  NOMADIC_DIR="$TEST_DIR/nomadic"
  ORIG_HOME="$HOME"
  HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  mkdir -p "$TEST_CONFIG/modules"
}

teardown() {
  HOME="$ORIG_HOME"
  rm -rf "$TEST_DIR"
}

# --- check_deps ---------------------------------------------------------------

@test "check_deps: passes with valid deps" {
  create_module "alpha"
  create_module "beta" "after: alpha"
  setup_global_state "$TEST_CONFIG"
  run check_deps
  [ "$status" -eq 0 ]
}

@test "check_deps: warns on unknown after: target" {
  create_module "mymod" "after: nonexistent"
  setup_global_state "$TEST_CONFIG"
  run check_deps
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown module 'nonexistent'"* ]]
}

@test "check_deps: warns on dependency cycle" {
  create_module "alpha" "after: beta"
  create_module "beta" "after: alpha"
  setup_global_state "$TEST_CONFIG"
  run check_deps
  [ "$status" -eq 1 ]
  [[ "$output" == *"cycle"* ]]
}

# --- check_links --------------------------------------------------------------

@test "check_links: passes when symlinks are correct" {
  create_module "mymod"
  echo "content" >"$TEST_CONFIG/modules/mymod/myrc"
  printf 'myrc %s/.myrc\n' "$HOME" >"$TEST_CONFIG/modules/mymod/links"
  ln -s "$TEST_CONFIG/modules/mymod/myrc" "$HOME/.myrc"
  setup_global_state "$TEST_CONFIG"
  run check_links
  [ "$status" -eq 0 ]
}

@test "check_links: warns on missing symlink" {
  create_module "mymod"
  echo "content" >"$TEST_CONFIG/modules/mymod/myrc"
  printf 'myrc %s/.myrc\n' "$HOME" >"$TEST_CONFIG/modules/mymod/links"
  setup_global_state "$TEST_CONFIG"
  run check_links
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing"* ]]
}

@test "check_links: warns when target is a regular file" {
  create_module "mymod"
  echo "content" >"$TEST_CONFIG/modules/mymod/myrc"
  printf 'myrc %s/.myrc\n' "$HOME" >"$TEST_CONFIG/modules/mymod/links"
  echo "not a symlink" >"$HOME/.myrc"
  setup_global_state "$TEST_CONFIG"
  run check_links
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a symlink"* ]]
}

@test "check_links: warns when symlink points to wrong target" {
  create_module "mymod"
  echo "content" >"$TEST_CONFIG/modules/mymod/myrc"
  printf 'myrc %s/.myrc\n' "$HOME" >"$TEST_CONFIG/modules/mymod/links"
  ln -s "/wrong/target" "$HOME/.myrc"
  setup_global_state "$TEST_CONFIG"
  run check_links
  [ "$status" -eq 1 ]
  [[ "$output" == *"points to"* ]]
}

@test "check_links: passes with no links files" {
  create_module "mymod"
  setup_global_state "$TEST_CONFIG"
  run check_links
  [ "$status" -eq 0 ]
}

# --- check_rc -----------------------------------------------------------------

@test "check_rc: passes when rc file exists and bashrc is infected" {
  mkdir -p "$NOMADIC_DIR"
  echo "generated" >"$NOMADIC_DIR/config.bash"
  echo "source $NOMADIC_DIR/config.bash  # NOMADIC_MANAGED" >"$HOME/.bashrc"

  run check_rc
  [ "$status" -eq 0 ]
}

@test "check_rc: warns when rc file is missing" {
  run check_rc
  [ "$status" -eq 1 ]
  [[ "$output" == *"No generated RC file"* ]]
}

@test "check_rc: warns when bashrc not sourcing nomadic" {
  mkdir -p "$NOMADIC_DIR"
  echo "generated" >"$NOMADIC_DIR/config.bash"
  echo "# nothing here" >"$HOME/.bashrc"

  run check_rc
  [ "$status" -eq 1 ]
  [[ "$output" == *"not sourcing nomadic"* ]]
}

# --- check_pkg_manager --------------------------------------------------------

@test "check_pkg_manager: warns when no package manager found" {
  PATH="/nonexistent" run check_pkg_manager
  [ "$status" -eq 1 ]
  [[ "$output" == *"No package manager detected"* ]]
}

@test "check_pkg_manager: warns when nix lacks nix-command feature" {
  # Stub nix to exist but fail on 'profile list'
  local stub_dir="$TEST_DIR/stub"
  mkdir -p "$stub_dir"
  cat >"$stub_dir/nix" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "profile" ]]; then
  exit 1
fi
STUB
  chmod +x "$stub_dir/nix"

  PATH="$stub_dir" run check_pkg_manager
  [ "$status" -eq 1 ]
  [[ "$output" == *"nix detected but"* ]]
  [[ "$output" == *"experimental-features"* ]]
}

# --- cmd_doctor ---------------------------------------------------------------

@test "cmd_doctor: reports all good on healthy config" {
  create_module "mymod"
  printf 'export FOO="bar"\n' >"$TEST_CONFIG/modules/mymod/bash"
  mkdir -p "$NOMADIC_DIR"
  echo "generated" >"$NOMADIC_DIR/config.bash"
  echo "source $NOMADIC_DIR/config.bash  # NOMADIC_MANAGED" >"$HOME/.bashrc"

  # Stub out detect_pkg_manager so check_pkg_manager doesn't hit real nix
  local stub_dir="$TEST_DIR/stub"
  mkdir -p "$stub_dir"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$stub_dir/detect_pkg_manager"

  detect_pkg_manager() { echo "apt"; }
  export -f detect_pkg_manager

  run cmd_doctor "$TEST_CONFIG"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Everything looks good"* ]]

  unset -f detect_pkg_manager
}

@test "cmd_doctor: reports issues" {
  create_module "mymod" "after: nonexistent"
  printf 'myrc %s/.myrc\n' "$HOME" >"$TEST_CONFIG/modules/mymod/links"
  run cmd_doctor "$TEST_CONFIG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"issue(s) found"* ]]
}
