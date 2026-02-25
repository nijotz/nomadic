#!/usr/bin/env bats
load test_helper/common

@test "process_links: creates symlink" {
  create_module "mymod"
  echo "hello" >"$TEST_CONFIG/modules/mymod/myfile"
  printf 'myfile %s/target\n' "$TEST_DIR" >"$TEST_CONFIG/modules/mymod/links"

  process_links "$TEST_CONFIG" "mymod"
  [ -L "$TEST_DIR/target" ]
  [ "$(readlink "$TEST_DIR/target")" = "$TEST_CONFIG/modules/mymod/myfile" ]
}

@test "process_links: expands tilde in target" {
  create_module "mymod"
  echo "hello" >"$TEST_CONFIG/modules/mymod/myfile"
  printf 'myfile ~/.test-nomad-link\n' >"$TEST_CONFIG/modules/mymod/links"

  local orig_home="$HOME"
  HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  process_links "$TEST_CONFIG" "mymod"
  [ -L "$HOME/.test-nomad-link" ]
  HOME="$orig_home"
}

@test "process_links: creates parent directories" {
  create_module "mymod"
  echo "hello" >"$TEST_CONFIG/modules/mymod/myfile"
  printf 'myfile %s/deep/nested/dir/target\n' "$TEST_DIR" >"$TEST_CONFIG/modules/mymod/links"

  process_links "$TEST_CONFIG" "mymod"
  [ -L "$TEST_DIR/deep/nested/dir/target" ]
}

@test "process_links: skips when symlink already correct" {
  create_module "mymod"
  echo "hello" >"$TEST_CONFIG/modules/mymod/myfile"
  printf 'myfile %s/target\n' "$TEST_DIR" >"$TEST_CONFIG/modules/mymod/links"

  # Create the correct symlink first
  ln -s "$TEST_CONFIG/modules/mymod/myfile" "$TEST_DIR/target"

  run process_links "$TEST_CONFIG" "mymod"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'already linked'
}

@test "process_links: warns when target exists but is not correct symlink" {
  create_module "mymod"
  echo "hello" >"$TEST_CONFIG/modules/mymod/myfile"
  printf 'myfile %s/target\n' "$TEST_DIR" >"$TEST_CONFIG/modules/mymod/links"

  # Create a regular file at the target
  echo "existing" >"$TEST_DIR/target"

  run process_links "$TEST_CONFIG" "mymod"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'already exists'
  # Target should still be the regular file, not overwritten
  [ ! -L "$TEST_DIR/target" ]
}

@test "process_links: skips blank lines and comments" {
  create_module "mymod"
  echo "hello" >"$TEST_CONFIG/modules/mymod/file1"
  echo "world" >"$TEST_CONFIG/modules/mymod/file2"
  printf '%s\n' "# a comment" "" "file1 $TEST_DIR/t1" "" "# another comment" "file2 $TEST_DIR/t2" \
    >"$TEST_CONFIG/modules/mymod/links"

  process_links "$TEST_CONFIG" "mymod"
  [ -L "$TEST_DIR/t1" ]
  [ -L "$TEST_DIR/t2" ]
}

@test "process_links: missing links file is a no-op" {
  create_module "mymod"

  run process_links "$TEST_CONFIG" "mymod"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "process_links: handles multiple links" {
  create_module "mymod"
  echo "a" >"$TEST_CONFIG/modules/mymod/file1"
  echo "b" >"$TEST_CONFIG/modules/mymod/file2"
  echo "c" >"$TEST_CONFIG/modules/mymod/file3"
  printf '%s\n' "file1 $TEST_DIR/t1" "file2 $TEST_DIR/t2" "file3 $TEST_DIR/t3" \
    >"$TEST_CONFIG/modules/mymod/links"

  process_links "$TEST_CONFIG" "mymod"
  [ -L "$TEST_DIR/t1" ]
  [ -L "$TEST_DIR/t2" ]
  [ -L "$TEST_DIR/t3" ]
}
