#!/usr/bin/env bats
load test_helper/common

@test "detect_pkg_manager finds brew on macOS" {
  # This test assumes macOS with brew installed; skip otherwise
  if ! command -v brew &>/dev/null; then
    skip "brew not installed"
  fi
  run detect_pkg_manager
  [ "$status" -eq 0 ]
  [ "$output" = "brew" ]
}

@test "detect_pkg_manager returns 1 when nothing found" {
  # Override PATH to hide all package managers
  PATH="/usr/bin/false_dir_that_does_not_exist" run detect_pkg_manager
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "read_package_list reads names, skips comments and blanks" {
  local pkg_file="$TEST_DIR/packages"
  cat >"$pkg_file" <<'EOF'
# Base packages
htop
jq

# Network tools
curl
wget
EOF

  run read_package_list "$pkg_file"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "htop" ]
  [ "${lines[1]}" = "jq" ]
  [ "${lines[2]}" = "curl" ]
  [ "${lines[3]}" = "wget" ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "collect_packages gathers from _mod_pkg globals" {
  create_module "git" "pkg: git"
  create_module "tmux" "pkg: tmux"
  create_module "vim"

  load_module_deps "$TEST_CONFIG" "git" "tmux" "vim"
  run collect_packages
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "git" ]
  [ "${lines[1]}" = "tmux" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "collect_packages deduplicates" {
  create_module "alpha" "pkg: jq curl"
  create_module "beta" "pkg: curl wget"

  load_module_deps "$TEST_CONFIG" "alpha" "beta"
  run collect_packages
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "jq" ]
  [ "${lines[1]}" = "curl" ]
  [ "${lines[2]}" = "wget" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "collect_packages splits space-separated values" {
  create_module "multi" "pkg: htop jq curl"

  load_module_deps "$TEST_CONFIG" "multi"
  run collect_packages
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "htop" ]
  [ "${lines[1]}" = "jq" ]
  [ "${lines[2]}" = "curl" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "resolve_packages maps names via map file" {
  local map_file="$TEST_DIR/brew.map"
  cat >"$map_file" <<'EOF'
fd=fd-find
ripgrep=ripgrep-all
EOF

  run resolve_packages "$map_file" fd ripgrep htop
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "fd-find" ]
  [ "${lines[1]}" = "ripgrep-all" ]
  [ "${lines[2]}" = "htop" ]
}

@test "resolve_packages passes through unmapped names" {
  local map_file="$TEST_DIR/brew.map"
  cat >"$map_file" <<'EOF'
fd=fd-find
EOF

  run resolve_packages "$map_file" htop jq curl
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "htop" ]
  [ "${lines[1]}" = "jq" ]
  [ "${lines[2]}" = "curl" ]
}

@test "resolve_packages handles missing map file" {
  run resolve_packages "/nonexistent/map" htop jq curl
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "htop" ]
  [ "${lines[1]}" = "jq" ]
  [ "${lines[2]}" = "curl" ]
}

@test "is_pkg_installed checks _installed_casks for cask: prefix" {
  _installed_pkgs=$'git\njq'
  _installed_casks=$'iterm2\nfirefox'

  run is_pkg_installed "cask:iterm2"
  [ "$status" -eq 0 ]

  run is_pkg_installed "cask:firefox"
  [ "$status" -eq 0 ]

  run is_pkg_installed "cask:chrome"
  [ "$status" -eq 1 ]

  # Regular packages still check _installed_pkgs
  run is_pkg_installed "git"
  [ "$status" -eq 0 ]

  run is_pkg_installed "vim"
  [ "$status" -eq 1 ]
}

@test "install_packages partitions cask vs formula for brew" {
  local -a brew_calls=()
  brew() { brew_calls+=("$*"); }
  export -f brew

  install_packages brew htop "cask:iterm2" jq "cask:firefox"

  [ "${#brew_calls[@]}" -eq 2 ]
  [ "${brew_calls[0]}" = "install htop jq" ]
  [ "${brew_calls[1]}" = "install --cask iterm2 firefox" ]

  unset -f brew
}

@test "resolve_packages handles comments and blank lines in map file" {
  local map_file="$TEST_DIR/apt.map"
  cat >"$map_file" <<'EOF'
# APT name overrides

fd=fd-find

# ripgrep is the same
EOF

  run resolve_packages "$map_file" fd ripgrep
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "fd-find" ]
  [ "${lines[1]}" = "ripgrep" ]
}
