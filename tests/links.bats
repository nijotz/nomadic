#!/usr/bin/env bats
load test_helper/common

@test "process_links: creates symlink" {
  create_module "mymod"
  echo "hello" >"$TEST_BINDLE/modules/mymod/myfile"
  printf 'myfile %s/target\n' "$TEST_DIR" >"$TEST_BINDLE/modules/mymod/links"

  process_links "mymod"
  [ -L "$TEST_DIR/target" ]
  [ "$(readlink "$TEST_DIR/target")" = "$TEST_BINDLE/modules/mymod/myfile" ]
}

@test "process_links: expands tilde in target" {
  create_module "mymod"
  echo "hello" >"$TEST_BINDLE/modules/mymod/myfile"
  printf 'myfile ~/.test-nomadic-link\n' >"$TEST_BINDLE/modules/mymod/links"

  local orig_home="$HOME"
  HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  process_links "mymod"
  [ -L "$HOME/.test-nomadic-link" ]
  HOME="$orig_home"
}

@test "process_links: creates parent directories" {
  create_module "mymod"
  echo "hello" >"$TEST_BINDLE/modules/mymod/myfile"
  printf 'myfile %s/deep/nested/dir/target\n' "$TEST_DIR" >"$TEST_BINDLE/modules/mymod/links"

  process_links "mymod"
  [ -L "$TEST_DIR/deep/nested/dir/target" ]
}

@test "process_links: skips when symlink already correct" {
  create_module "mymod"
  echo "hello" >"$TEST_BINDLE/modules/mymod/myfile"
  printf 'myfile %s/target\n' "$TEST_DIR" >"$TEST_BINDLE/modules/mymod/links"

  # Create the correct symlink first
  ln -s "$TEST_BINDLE/modules/mymod/myfile" "$TEST_DIR/target"

  run process_links "mymod"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'already linked'
}

@test "process_links: warns when target exists but is not correct symlink" {
  create_module "mymod"
  echo "hello" >"$TEST_BINDLE/modules/mymod/myfile"
  printf 'myfile %s/target\n' "$TEST_DIR" >"$TEST_BINDLE/modules/mymod/links"

  # Create a regular file at the target
  echo "existing" >"$TEST_DIR/target"

  run process_links "mymod"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'already exists'
  # Target should still be the regular file, not overwritten
  [ ! -L "$TEST_DIR/target" ]
}

@test "process_links --force: backs up existing file and creates symlink" {
  create_module "mymod"
  echo "hello" >"$TEST_BINDLE/modules/mymod/myfile"
  printf 'myfile %s/target\n' "$TEST_DIR" >"$TEST_BINDLE/modules/mymod/links"
  echo "existing content" >"$TEST_DIR/target"

  process_links "mymod" 1

  # Target should now be a symlink
  [ -L "$TEST_DIR/target" ]
  [ "$(readlink "$TEST_DIR/target")" = "$TEST_BINDLE/modules/mymod/myfile" ]
  # Backup should exist with original content
  local backup
  backup="$(ls "$NOMADIC_DIR/backups"/target.* 2>/dev/null | head -1)"
  [ -n "$backup" ]
  [ "$(cat "$backup")" = "existing content" ]
}

@test "process_links --force: backs up wrong symlink and replaces it" {
  create_module "mymod"
  echo "hello" >"$TEST_BINDLE/modules/mymod/myfile"
  printf 'myfile %s/target\n' "$TEST_DIR" >"$TEST_BINDLE/modules/mymod/links"
  ln -s /some/wrong/path "$TEST_DIR/target"

  process_links "mymod" 1

  [ -L "$TEST_DIR/target" ]
  [ "$(readlink "$TEST_DIR/target")" = "$TEST_BINDLE/modules/mymod/myfile" ]
}

@test "process_links: skips blank lines and comments" {
  create_module "mymod"
  echo "hello" >"$TEST_BINDLE/modules/mymod/file1"
  echo "world" >"$TEST_BINDLE/modules/mymod/file2"
  printf '%s\n' "# a comment" "" "file1 $TEST_DIR/t1" "" "# another comment" "file2 $TEST_DIR/t2" \
    >"$TEST_BINDLE/modules/mymod/links"

  process_links "mymod"
  [ -L "$TEST_DIR/t1" ]
  [ -L "$TEST_DIR/t2" ]
}

@test "process_links: missing links file is a no-op" {
  create_module "mymod"

  run process_links "mymod"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "process_links: handles multiple links" {
  create_module "mymod"
  echo "a" >"$TEST_BINDLE/modules/mymod/file1"
  echo "b" >"$TEST_BINDLE/modules/mymod/file2"
  echo "c" >"$TEST_BINDLE/modules/mymod/file3"
  printf '%s\n' "file1 $TEST_DIR/t1" "file2 $TEST_DIR/t2" "file3 $TEST_DIR/t3" \
    >"$TEST_BINDLE/modules/mymod/links"

  process_links "mymod"
  [ -L "$TEST_DIR/t1" ]
  [ -L "$TEST_DIR/t2" ]
  [ -L "$TEST_DIR/t3" ]
}
