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

  load_modules "$TEST_CONFIG" "git" "tmux" "vim"
  run collect_packages
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "git" ]
  [ "${lines[1]}" = "tmux" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "collect_packages deduplicates" {
  create_module "alpha" "pkg: jq curl"
  create_module "beta" "pkg: curl wget"

  load_modules "$TEST_CONFIG" "alpha" "beta"
  run collect_packages
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "jq" ]
  [ "${lines[1]}" = "curl" ]
  [ "${lines[2]}" = "wget" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "collect_packages splits space-separated values" {
  create_module "multi" "pkg: htop jq curl"

  load_modules "$TEST_CONFIG" "multi"
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

@test "install_packages prefixes nixpkgs# for nix" {
  local -a nix_calls=()
  nix() { nix_calls+=("$*"); }
  export -f nix

  install_packages nix htop jq curl

  [ "${#nix_calls[@]}" -eq 1 ]
  [ "${nix_calls[0]}" = "profile install nixpkgs#htop nixpkgs#jq nixpkgs#curl" ]

  unset -f nix
}

@test "snapshot_installed_packages parses older nix profile list output (no Name)" {
  local stub_dir="$TEST_DIR/stub"
  mkdir -p "$stub_dir"
  # Older nix (e.g. 2.18) omits Name: entirely
  cat >"$stub_dir/nix" <<'STUB'
#!/usr/bin/env bash
if [[ "$1 $2" == "profile list" ]]; then
  printf 'Index:              0\n'
  printf 'Flake attribute:    legacyPackages.x86_64-linux.fzf\n'
  printf 'Original flake URL: flake:nixpkgs\n'
  printf '\n'
  printf 'Index:              1\n'
  printf 'Flake attribute:    legacyPackages.x86_64-linux.git\n'
  printf 'Original flake URL: flake:nixpkgs\n'
fi
STUB
  chmod +x "$stub_dir/nix"

  detect_pkg_manager() { echo "nix"; }
  PATH="$stub_dir:$PATH" snapshot_installed_packages
  [ "$(echo "$_installed_pkgs" | sed -n '1p')" = "fzf" ]
  [ "$(echo "$_installed_pkgs" | sed -n '2p')" = "git" ]
}

@test "snapshot_installed_packages parses newer nix profile list output (with Name)" {
  local stub_dir="$TEST_DIR/stub"
  mkdir -p "$stub_dir"
  # Newer nix emits ANSI-bolded Name: lines alongside Flake attribute:
  cat >"$stub_dir/nix" <<'STUB'
#!/usr/bin/env bash
if [[ "$1 $2" == "profile list" ]]; then
  printf 'Name:               \033[1mfzf\033[0m\n'
  printf 'Flake attribute:    legacyPackages.x86_64-linux.fzf\n'
  printf '\n'
  printf 'Name:               \033[1mgit\033[0m\n'
  printf 'Flake attribute:    legacyPackages.x86_64-linux.git\n'
fi
STUB
  chmod +x "$stub_dir/nix"

  detect_pkg_manager() { echo "nix"; }
  PATH="$stub_dir:$PATH" snapshot_installed_packages
  [ "$(echo "$_installed_pkgs" | sed -n '1p')" = "fzf" ]
  [ "$(echo "$_installed_pkgs" | sed -n '2p')" = "git" ]
}

@test "snapshot_installed_packages errors when nix lacks nix-command" {
  # Stub nix to exist but fail on 'profile list'
  local stub_dir="$TEST_DIR/stub"
  mkdir -p "$stub_dir"
  cat >"$stub_dir/nix" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$stub_dir/nix"

  detect_pkg_manager() { echo "nix"; }
  PATH="$stub_dir:$PATH" run snapshot_installed_packages
  [ "$status" -eq 1 ]
  [[ "$output" == *"nix detected but"* ]]
  [[ "$output" == *"experimental-features"* ]]
}

@test "snapshot_installed_packages includes unversioned names for brew versioned formula" {
  local stub_dir="$TEST_DIR/stub"
  mkdir -p "$stub_dir"
  cat >"$stub_dir/brew" <<'STUB'
#!/usr/bin/env bash
if [[ "$1 $2" == "list --formula" ]]; then
  printf 'python@3.14\ngit\n'
fi
STUB
  chmod +x "$stub_dir/brew"

  PATH="$stub_dir:$PATH" snapshot_installed_packages
  echo "$_installed_pkgs" | grep -qx "python@3.14"
  echo "$_installed_pkgs" | grep -qx "python"
  echo "$_installed_pkgs" | grep -qx "git"
}

@test "is_pkg_installed matches unversioned name when brew has versioned formula" {
  # Reproduces a bug where "pkg: python" would try to reinstall because
  # brew lists it as "python@3.14" and the exact match failed.
  _installed_pkgs=$'git\npython@3.14\npython'
  _pkg_manager="brew"

  run is_pkg_installed "python"
  [ "$status" -eq 0 ]
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

@test "install_all_packages reads both base and OS-specific package files" {
  mkdir -p "$TEST_CONFIG/packages"
  cat >"$TEST_CONFIG/packages/packages" <<'EOF'
htop
jq
EOF
  cat >"$TEST_CONFIG/packages/packages.macos" <<'EOF'
scroll-reverser
alt-tab
EOF

  # Save originals
  eval "$(declare -f detect_pkg_manager | sed 's/detect_pkg_manager/orig_detect_pkg_manager/')"
  eval "$(declare -f install_packages | sed 's/install_packages/orig_install_packages/')"

  # Stub detect_pkg_manager to return brew (no actual brew needed)
  detect_pkg_manager() { echo "brew"; }
  # Stub install_packages to print what it receives (skip actual install)
  install_packages() {
    shift
    printf '%s\n' "$@"
  }
  g_current_os="macos"
  run install_all_packages
  [ "$status" -eq 0 ]
  [[ "$output" == *"htop"* ]]
  [[ "$output" == *"jq"* ]]
  [[ "$output" == *"scroll-reverser"* ]]
  [[ "$output" == *"alt-tab"* ]]

  # Restore
  eval "$(declare -f orig_detect_pkg_manager | sed 's/orig_detect_pkg_manager/detect_pkg_manager/')"
  eval "$(declare -f orig_install_packages | sed 's/orig_install_packages/install_packages/')"
}

@test "collect_packages excludes packages from OS-filtered modules" {
  # Reproduces a bug where packages from OS-filtered modules (e.g. iterm2 on
  # a macOS-only module) leaked into collect_packages because load_modules was
  # called with all modules before OS filtering, and filter_by_os didn't update
  # the globals that collect_packages reads from.
  create_module "htop" "pkg: htop"
  create_module "iterm2" "$(printf 'os: macos\npkg: iterm2')"

  load_modules "$TEST_CONFIG" "htop" "iterm2"
  filter_by_os "ubuntu"

  run collect_packages
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "htop" ]
  [ "${#lines[@]}" -eq 1 ]
}
