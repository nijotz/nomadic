#!/usr/bin/env bash
set -euo pipefail

# --- Constants / Globals ------------------------------------------------------

NOMAD_VERSION="0.1.0"
NOMAD_STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nomad"

# Global parallel arrays, populated by load_module_deps. All share the same
# index. Use parallel indexed arrays instead of associative arrays for bash 3.2
# compatibility, which is the macOS default.
_mod_name=()
_mod_after=()
_mod_pkg=()
_mod_cmd=()
_mod_os=()

# --- Utility Functions --------------------------------------------------------

log() {
  echo "[nomad] $*" >&2
}

warn() {
  echo "[nomad] WARN: $*" >&2
}

error() {
  echo "[nomad] ERROR: $*" >&2
  exit 1
}

# Strip leading and trailing whitespace from a string.
# Usage: trim "  hello  " => "hello"
trim() {
  local s="$1"
  # Remove leading whitespace
  s="${s#"${s%%[![:space:]]*}"}"
  # Remove trailing whitespace
  s="${s%"${s##*[![:space:]]}"}"
  echo "$s"
}

# Strip trailing comments from a string.
# Usage: trim "hello   # greeting" => "hello   "
trim_comment() {
  local s="$1"
  s="${s%%#*}"
  echo "$s"
}

# Find the index of a value in an array. Bash has no built-in for this,
# so we do a linear scan. Returns the 0-based index via stdout, or
# returns 1 if not found.
# Usage: index_of "needle" "${haystack[@]}"
index_of() {
  local needle="$1"
  shift
  local i=0
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      echo "$i"
      return 0
    fi
    ((i += 1))
  done
  return 1
}

# --- OS Detection -------------------------------------------------------------

detect_os() {
  local uname
  uname="$(uname -s)"
  case "$uname" in
    Darwin) echo "macos" ;;
    Linux)
      if [[ -f /etc/os-release ]]; then
        local id
        id="$(. /etc/os-release && echo "${ID:-linux}")"
        case "$id" in
          ubuntu | debian) echo "ubuntu" ;;
          arch | manjaro) echo "arch" ;;
          *) echo "linux" ;;
        esac
      else
        echo "linux"
      fi
      ;;
    *) echo "unknown" ;;
  esac
}

# --- Modules ------------------------------------------------------------------

discover_modules() {
  local config_dir="$1"
  local modules_dir="$config_dir/modules"

  if [[ ! -d "$modules_dir" ]]; then
    warn "No modules directory found at $modules_dir"
    return 1
  fi

  local -a names=()
  for dir in "$modules_dir"/*/; do
    [[ -d "$dir" ]] || continue
    local name
    name="$(basename "$dir")"
    [[ "$name" == .* ]] && continue
    names+=("$name")
  done

  if ((${#names[@]} > 0)); then
    printf '%s\n' "${names[@]}" | sort
  fi
}

# Parse all module deps files once and populate global parallel arrays.
# After calling this, the following arrays are set
#   _mod_name[i]  = module name
#   _mod_after[i] = "after:" value (space-separated module names)
#   _mod_pkg[i]   = "pkg:" value (space-separated package names)
#   _mod_cmd[i]   = "cmd:" value
#   _mod_os[i]    = "os:" value
load_module_deps() {
  local config_dir="$1"
  shift

  _mod_name=("$@")
  _mod_after=()
  _mod_pkg=()
  _mod_cmd=()
  _mod_os=()

  local mod
  for mod in "$@"; do
    local deps_file="$config_dir/modules/$mod/deps"
    local after="" pkg="" cmd="" os=""

    if [[ -f "$deps_file" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(trim_comment "$line")"
        line="$(trim "$line")"
        [[ -z "$line" ]] && continue

        case "$line" in
          after:*) after="$(trim "${line#after:}")" ;;
          pkg:*) pkg="$(trim "${line#pkg:}")" ;;
          cmd:*) cmd="$(trim "${line#cmd:}")" ;;
          os:*) os="$(trim "${line#os:}")" ;;
          *) warn "Unknown directive in $deps_file: $line" ;;
        esac
      done <"$deps_file"
    fi

    _mod_after+=("$after")
    _mod_pkg+=("$pkg")
    _mod_cmd+=("$cmd")
    _mod_os+=("$os")
  done
}

# Filter a list of module names by OS compatibility.
# Reads _mod_os[] from globals (populated by load_module_deps).
# Modules with no os: constraint pass on any OS. "linux" in a module's
# os: field matches ubuntu, arch, debian, etc.
filter_by_os() {
  local os_name="$1"
  shift

  local mod
  for mod in "$@"; do
    local idx
    if ! idx="$(index_of "$mod" "${_mod_name[@]}")"; then
      continue
    fi

    local mod_os="${_mod_os[$idx]}"

    # No OS constraint — passes on any OS
    if [[ -z "$mod_os" ]]; then
      echo "$mod"
      continue
    fi

    # Check if current OS matches any listed OS
    local os_item
    for os_item in $mod_os; do
      if [[ "$os_item" == "$os_name" ]]; then
        echo "$mod"
        continue 2
      fi
      # "linux" is a catch-all that matches any Linux distro
      if [[ "$os_item" == "linux" ]]; then
        case "$os_name" in
          ubuntu | arch | debian | manjaro | linux)
            echo "$mod"
            continue 3
            ;;
        esac
      fi
    done
  done
}

# Check if a module's cmd: requirement is satisfied.
# Returns 0 if no requirement or command exists, 1 if missing.
check_cmd() {
  local mod="$1"
  local idx
  if ! idx="$(index_of "$mod" "${_mod_name[@]}")"; then
    return 0
  fi

  local cmd="${_mod_cmd[$idx]}"
  if [[ -z "$cmd" ]]; then
    return 0
  fi

  if command -v "$cmd" &>/dev/null; then
    return 0
  fi

  warn "Module '$mod' requires command '$cmd' which is not installed (skipping)"
  return 1
}

# Source a module's setup script if present.
# Setup scripts run in the current shell so they can modify the environment
# (e.g., install homebrew and update PATH).
run_setup() {
  local config_dir="$1"
  local mod="$2"
  local setup_file="$config_dir/modules/$mod/setup"

  if [[ ! -f "$setup_file" ]]; then
    return 0
  fi

  log "Running setup for $mod"
  . "$setup_file"
}

# Process a module's links file, creating symlinks.
# Each line in the links file: <source> <target>
#   source — relative to the module directory
#   target — absolute path, ~ expanded to $HOME
# Existing correct symlinks are skipped. Existing non-symlink targets
# are warned about and skipped.
process_links() {
  local config_dir="$1"
  local mod="$2"
  local links_file="$config_dir/modules/$mod/links"

  if [[ ! -f "$links_file" ]]; then
    return 0
  fi

  local module_dir="$config_dir/modules/$mod"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim_comment "$line")"
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue

    local src tgt
    read -r src tgt <<<"$line"

    # Resolve source to absolute path
    src="$module_dir/$src"

    # Expand ~ in target
    tgt="${tgt/#\~/$HOME}"

    # Create parent directory if needed
    mkdir -p "$(dirname "$tgt")"

    # Check existing target
    if [[ -e "$tgt" ]] || [[ -L "$tgt" ]]; then
      if [[ -L "$tgt" ]] && [[ "$(readlink "$tgt")" == "$src" ]]; then
        log "$mod: $tgt already linked"
        continue
      fi
      warn "$mod: $tgt already exists, skipping"
      continue
    fi

    ln -s "$src" "$tgt"
    log "$mod: linked $tgt -> $src"
  done <"$links_file"
}

# Collect shell config for a module. Outputs the config content to stdout.
# Non-executable files are concatenated verbatim. Executable files are
# run and their stdout is captured (they inherit the current environment,
# so prior modules' exports are visible).
collect_shell_config() {
  local config_dir="$1"
  local mod="$2"
  local shell="$3"
  local os="${4:-}"
  local config_file="$config_dir/modules/$mod/$shell.$os"

  if [[ -z "$os" ]] || [[ ! -f "$config_file" ]]; then
    config_file="$config_dir/modules/$mod/$shell"
  fi

  if [[ ! -f "$config_file" ]]; then
    return 0
  fi

  local header="# --- module: $mod "
  local pad=$((80 - ${#header}))
  # Repeat "-" $pad times: create $pad spaces with printf, then replace each with -
  local dashes
  printf -v dashes '%*s' "$pad" ''
  dashes="${dashes// /-}"
  echo "${header}${dashes}"

  if [[ -x "$config_file" ]]; then
    "$config_file"
  else
    cat "$config_file"
  fi

  echo ""
}

# --- Topological Sort ---------------------------------------------------------

# Topological sort using Kahn's algorithm (BFS-based).
#
# Reads from the global arrays populated by load_module_deps:
#   _mod_name[]    — module names
#   _mod_after[]  — each module's "after:" dependencies
#
# Outputs module names in dependency order. Modules with no ordering
# constraint between them are sorted alphabetically for determinism.
#
# Detects cycles: if not all modules can be placed, reports which are stuck.
# Unknown dependencies (e.g. "after: homebrew" when homebrew isn't in the
# module list) are warned about and skipped — this keeps configs portable
# across machines where some modules may not exist.
toposort() {
  local count=${#_mod_name[@]}

  if ((count == 0)); then
    return 0
  fi

  # Build parallel arrays for the graph. Ideally these would be associative
  # arrays keyed by module name, but bash 3.2 only supports integer indices.
  #   indegree[i] = number of unresolved dependencies for _mod_name[i]
  #   edges[i]    = space-separated names of modules that depend on _mod_name[i]
  local -a indegree=()
  local -a edges=()
  local i
  for ((i = 0; i < count; i++)); do
    indegree+=(0)
    edges+=("")
  done

  # Build the dependency graph from the pre-loaded after data.
  # "after: X" means X must come before this module, so we add an edge
  # from X -> this module (X is a prerequisite).
  for ((i = 0; i < count; i++)); do
    local after="${_mod_after[$i]}"
    if [[ -n "$after" ]]; then
      for dep in $after; do
        local dep_idx
        if dep_idx="$(index_of "$dep" "${_mod_name[@]}")"; then
          # Add this module as a successor of dep
          edges[$dep_idx]="${edges[$dep_idx]:+${edges[$dep_idx]} }${_mod_name[$i]}"
          # This module has one more incoming edge
          indegree[$i]=$((${indegree[$i]} + 1))
        else
          warn "Module '${_mod_name[$i]}' depends on unknown module '$dep' (skipping dependency)"
        fi
      done
    fi
  done

  # Seed the queue with modules that have no dependencies (indegree 0).
  # Sort alphabetically so the output is deterministic.
  local -a queue=()
  for ((i = 0; i < count; i++)); do
    if ((${indegree[$i]} == 0)); then
      queue+=("${_mod_name[$i]}")
    fi
  done
  local sorted_queue
  sorted_queue="$(printf '%s\n' "${queue[@]}" | sort)"
  queue=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && queue+=("$line")
  done <<<"$sorted_queue"

  # Process the queue: pop a module, add it to the result, then decrement
  # the in-degree of all its successors. Any successor that drops to 0
  # is added to the queue (alphabetically for stable ordering).
  local -a result=()
  while ((${#queue[@]} > 0)); do
    # Pop the first module from the queue
    local current="${queue[0]}"
    queue=("${queue[@]:1}")
    result+=("$current")

    local cur_idx
    cur_idx="$(index_of "$current" "${_mod_name[@]}")"

    # For each module that depends on current, decrement its in-degree
    local -a newly_free=()
    if [[ -n "${edges[$cur_idx]}" ]]; then
      for successor in ${edges[$cur_idx]}; do
        local succ_idx
        succ_idx="$(index_of "$successor" "${_mod_name[@]}")"
        indegree[$succ_idx]=$((${indegree[$succ_idx]} - 1))
        if ((${indegree[$succ_idx]} == 0)); then
          newly_free+=("$successor")
        fi
      done
    fi

    # Add newly unblocked modules to the queue, sorted for determinism
    if ((${#newly_free[@]} > 0)); then
      local sorted_free
      sorted_free="$(printf '%s\n' "${newly_free[@]}" | sort)"
      while IFS= read -r line; do
        [[ -n "$line" ]] && queue+=("$line")
      done <<<"$sorted_free"
    fi
  done

  # If we couldn't place all modules, there's a cycle. Report which
  # modules still have unresolved dependencies.
  if ((${#result[@]} != count)); then
    warn "Dependency cycle detected among modules:"
    for ((i = 0; i < count; i++)); do
      if ((${indegree[$i]} > 0)); then
        warn "  ${_mod_name[$i]} (blocked)"
      fi
    done
    return 1
  fi

  printf '%s\n' "${result[@]}"
}

# --- RC File Management -------------------------------------------------------

# Write accumulated shell config content to the RC file.
# Reads content from stdin. Creates the state directory if needed.
generate_rc() {
  local shell="$1"
  local rc_file="$NOMAD_STATE_DIR/config.$shell"

  mkdir -p "$NOMAD_STATE_DIR"

  {
    echo "# Generated by nomad — do not edit"
    echo ""
    cat
  } >"$rc_file"
}

# Add a source line to the user's shell rc file.
# Idempotent — checks for # NOMAD_MANAGED marker before adding.
infect_rc() {
  local shell="$1"
  local rc_file

  case "$shell" in
    bash) rc_file="$HOME/.bashrc" ;;
    zsh) rc_file="$HOME/.zshrc" ;;
    fish) rc_file="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/nomad.fish" ;;
    *) error "Unknown shell: $shell" ;;
  esac

  # Already infected — nothing to do
  if [[ -f "$rc_file" ]] && grep -q '# NOMAD_MANAGED' "$rc_file"; then
    return 0
  fi

  mkdir -p "$(dirname "$rc_file")"

  local source_line="source $NOMAD_STATE_DIR/config.$shell  # NOMAD_MANAGED"
  echo "$source_line" >>"$rc_file"
}

# --- Package Management ------------------------------------------------------

# Detect which package manager is available.
# Checks in priority order: brew > apt > pacman.
# Outputs the name and returns 0, or returns 1 if none found.
detect_pkg_manager() {
  local mgr
  for mgr in brew apt pacman; do
    if command -v "$mgr" &>/dev/null; then
      echo "$mgr"
      return 0
    fi
  done
  return 1
}

# Read a flat package list file (one name per line).
# Skips blank lines and # comments. Outputs names to stdout.
read_package_list() {
  local file="$1"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim_comment "$line")"
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue
    echo "$line"
  done <"$file"
}

# Collect all package names from _mod_pkg[] globals.
# Splits space-separated values and deduplicates.
# Outputs one package name per line.
collect_packages() {
  local -a seen=()
  local i
  for ((i = 0; i < ${#_mod_pkg[@]}; i++)); do
    local pkgs="${_mod_pkg[$i]}"
    [[ -z "$pkgs" ]] && continue
    local pkg
    for pkg in $pkgs; do
      local found=0
      local s
      for s in "${seen[@]+"${seen[@]}"}"; do
        if [[ "$s" == "$pkg" ]]; then
          found=1
          break
        fi
      done
      if ((found == 0)); then
        seen+=("$pkg")
        echo "$pkg"
      fi
    done
  done
}

# Resolve abstract package names to concrete ones using a map file.
# Map file format: abstract=concrete (one per line).
# Unmapped names pass through as-is. Missing map file = all pass-through.
resolve_packages() {
  local map_file="$1"
  shift

  local -a map_from=()
  local -a map_to=()

  if [[ -f "$map_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="$(trim_comment "$line")"
      line="$(trim "$line")"
      [[ -z "$line" ]] && continue
      local abstract="${line%%=*}"
      local concrete="${line#*=}"
      map_from+=("$(trim "$abstract")")
      map_to+=("$(trim "$concrete")")
    done <"$map_file"
  fi

  local name
  for name in "$@"; do
    local mapped=0
    local j
    for ((j = 0; j < ${#map_from[@]}; j++)); do
      if [[ "${map_from[$j]}" == "$name" ]]; then
        echo "${map_to[$j]}"
        mapped=1
        break
      fi
    done
    if ((mapped == 0)); then
      echo "$name"
    fi
  done
}

# Run the install command for the detected package manager.
install_packages() {
  local pkg_manager="$1"
  shift

  log "Installing packages via $pkg_manager: $*"

  case "$pkg_manager" in
    brew)
      local -a formulas=() casks=()
      local pkg
      for pkg in "$@"; do
        if [[ "$pkg" == cask:* ]]; then
          casks+=("${pkg#cask:}")
        else
          formulas+=("$pkg")
        fi
      done
      ((${#formulas[@]} > 0)) && brew install "${formulas[@]}"
      ((${#casks[@]} > 0)) && brew install --cask "${casks[@]}"
      ;;
    apt) sudo apt install -y "$@" ;;
    pacman) sudo pacman -S --noconfirm "$@" ;;
    *) error "Unknown package manager: $pkg_manager" ;;
  esac
}

# Snapshot installed packages for the detected package manager.
# Sets global _installed_pkgs (newline-separated list) and _pkg_manager.
_installed_pkgs=""
_installed_casks=""
_pkg_manager=""

snapshot_installed_packages() {
  if ! _pkg_manager="$(detect_pkg_manager)"; then
    return 0
  fi

  case "$_pkg_manager" in
    brew)
      _installed_pkgs="$(brew list --formula -1 2>/dev/null)"
      _installed_casks="$(brew list --cask -1 2>/dev/null)"
      ;;
    apt) _installed_pkgs="$(dpkg-query -W -f '${Package}\n' 2>/dev/null)" ;;
    pacman) _installed_pkgs="$(pacman -Qq 2>/dev/null)" ;;
  esac
}

# Check if a package is already installed (against the snapshot).
is_pkg_installed() {
  local pkg="$1"
  if [[ "$pkg" == cask:* ]]; then
    echo "$_installed_casks" | grep -qx "${pkg#cask:}"
  else
    echo "$_installed_pkgs" | grep -qx "$pkg"
  fi
}

# Install a module's pkg: packages, skipping any already installed.
install_module_packages() {
  local config_dir="$1"
  local mod="$2"

  [[ -z "$_pkg_manager" ]] && return 0

  local idx
  if ! idx="$(index_of "$mod" "${_mod_name[@]}")"; then
    return 0
  fi

  local pkgs="${_mod_pkg[$idx]}"
  [[ -z "$pkgs" ]] && return 0

  local map_file="$config_dir/packages/$_pkg_manager.map"
  local -a missing=()
  local pkg
  for pkg in $pkgs; do
    local resolved
    resolved="$(resolve_packages "$map_file" "$pkg")"
    if is_pkg_installed "$resolved"; then
      log "$mod: package '$resolved' already installed"
    else
      missing+=("$resolved")
    fi
  done

  if ((${#missing[@]} > 0)); then
    install_packages "$_pkg_manager" "${missing[@]}"
    # Update snapshot so subsequent modules see newly installed packages
    local pkg
    for pkg in "${missing[@]}"; do
      if [[ "$pkg" == cask:* ]]; then
        _installed_casks="${_installed_casks}"$'\n'"${pkg#cask:}"
      else
        _installed_pkgs="${_installed_pkgs}"$'\n'"${pkg}"
      fi
    done
  fi
}

# Discover and install all packages from module deps and package lists.
# Detects the package manager, collects packages, resolves names, and installs.
install_all_packages() {
  local config_dir="$1"

  local pkg_manager
  if ! pkg_manager="$(detect_pkg_manager)"; then
    warn "No package manager found (brew, apt, pacman)"
    return 0
  fi

  local -a all_pkgs=()

  # Collect module pkg: declarations
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && all_pkgs+=("$pkg")
  done < <(collect_packages)

  # Read base package list
  local pkg_list="$config_dir/packages/packages"
  if [[ -f "$pkg_list" ]]; then
    while IFS= read -r pkg; do
      [[ -n "$pkg" ]] && all_pkgs+=("$pkg")
    done < <(read_package_list "$pkg_list")
  fi

  if ((${#all_pkgs[@]} == 0)); then
    return 0
  fi

  # Resolve through map file
  local map_file="$config_dir/packages/$pkg_manager.map"
  local -a resolved=()
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && resolved+=("$pkg")
  done < <(resolve_packages "$map_file" "${all_pkgs[@]}")

  install_packages "$pkg_manager" "${resolved[@]}"
}

# --- Init ---------------------------------------------------------------------

cmd_init() {
  local target="${1:-$HOME/.nomad}"

  if [[ -d "$target/modules" ]]; then
    error "Config directory already exists at $target/modules"
  fi

  log "Initializing nomad config at $target"

  mkdir -p "$target/profiles"
  mkdir -p "$target/modules/path"
  mkdir -p "$target/modules/color"
  mkdir -p "$target/modules/prompt"

  cat >"$target/profiles/default" <<'PROFILE'
path
color
prompt
PROFILE

  cat >"$target/modules/path/bash" <<'SHELL'
# PATH setup — add your custom paths here
export PATH="$HOME/.local/bin:$PATH"
SHELL

  cat >"$target/modules/color/bash" <<'SHELL'
# Color support
if command -v dircolors &>/dev/null; then
  eval "$(dircolors -b)"
fi
alias ls='ls --color=auto'
alias grep='grep --color=auto'
SHELL

  printf 'after: path\n' >"$target/modules/color/deps"

  cat >"$target/modules/prompt/bash" <<'SHELL'
# Simple prompt
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
SHELL

  printf 'after: color\n' >"$target/modules/prompt/deps"

  log "Created config with 3 example modules: path, color, prompt"
  log "Edit profiles/default to choose which modules to enable"
}

# --- Apply --------------------------------------------------------------------

cmd_apply() {
  local skip_packages=0
  local config_dir=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-packages|-P) skip_packages=1 ;;
      *) config_dir="$1" ;;
    esac
    shift
  done

  # Resolve config directory: explicit arg → remembered path → current dir
  if [[ -z "$config_dir" ]]; then
    local remembered="$NOMAD_STATE_DIR/state/config-path"
    if [[ -f "$remembered" ]]; then
      config_dir="$(cat "$remembered")"
    else
      config_dir="$HOME/.nomad"
    fi
  fi

  if [[ ! -d "$config_dir/modules" ]]; then
    error "No modules directory at $config_dir/modules"
  fi

  log "Applying config from $config_dir"

  # Discover all modules
  local -a all_modules=()
  while IFS= read -r mod; do
    all_modules+=("$mod")
  done < <(discover_modules "$config_dir")

  if ((${#all_modules[@]} == 0)); then
    log "No modules found"
    return 0
  fi

  # Load deps and sort
  load_module_deps "$config_dir" "${all_modules[@]}"
  local -a ordered=()
  while IFS= read -r mod; do
    ordered+=("$mod")
  done < <(toposort)

  # Filter by OS
  local current_os
  current_os="$(detect_os)"
  local -a filtered=()
  while IFS= read -r mod; do
    [[ -n "$mod" ]] && filtered+=("$mod")
  done < <(filter_by_os "$current_os" "${ordered[@]}")

  # Detect which shells are installed
  local has_bash=0 has_fish=0 has_zsh=0
  command -v bash &>/dev/null && has_bash=1
  command -v fish &>/dev/null && has_fish=1
  command -v zsh &>/dev/null && has_zsh=1

  # Snapshot installed packages once so per-module installs can check quickly
  snapshot_installed_packages

  # Temp files for accumulating shell config
  local rc_bash rc_fish rc_zsh
  rc_bash="$(mktemp)"
  rc_fish="$(mktemp)"
  rc_zsh="$(mktemp)"
  trap 'rm -f "${rc_bash:-}" "${rc_fish:-}" "${rc_zsh:-}"' EXIT

  # Process each module in dependency order
  for mod in "${filtered[@]}"; do
    # Install module's declared packages before checking cmd availability
    install_module_packages "$config_dir" "$mod"

    if ! check_cmd "$mod"; then
      continue
    fi

    log "Applying module: $mod"

    run_setup "$config_dir" "$mod"
    process_links "$config_dir" "$mod"

    ((has_bash)) && collect_shell_config "$config_dir" "$mod" "bash" "$current_os" >>"$rc_bash"
    ((has_fish)) && collect_shell_config "$config_dir" "$mod" "fish" "$current_os" >>"$rc_fish"
    ((has_zsh)) && collect_shell_config "$config_dir" "$mod" "zsh" "$current_os" >>"$rc_zsh"

    # Source accumulated bash config so later modules see prior exports
    if [[ -s "$rc_bash" ]]; then
      . "$rc_bash"
    fi
  done

  # Generate rc files for shells that have content
  if [[ -s "$rc_bash" ]]; then
    generate_rc "bash" <"$rc_bash"
    infect_rc "bash"
  fi
  if [[ -s "$rc_fish" ]]; then
    generate_rc "fish" <"$rc_fish"
    infect_rc "fish"
  fi
  if [[ -s "$rc_zsh" ]]; then
    generate_rc "zsh" <"$rc_zsh"
    infect_rc "zsh"
  fi

  # Remember config path for next time
  mkdir -p "$NOMAD_STATE_DIR/state"
  printf '%s\n' "$(cd "$config_dir" && pwd)" >"$NOMAD_STATE_DIR/state/config-path"

  log "Shell config applied. To pick up changes: exec bash  (or restart your shell)"

  # Install remaining packages from flat package list (safe to ctrl-c)
  if ((skip_packages)); then
    log "Skipping package install (--no-packages)"
  else
    log "Installing packages..."
    install_all_packages "$config_dir"
  fi

  log "Done!"
}

cmd_profile() {
  error "profile is not yet implemented"
}

cmd_enable() {
  error "enable is not yet implemented"
}

cmd_disable() {
  error "disable is not yet implemented"
}

cmd_list() {
  error "list is not yet implemented"
}

cmd_doctor() {
  error "doctor is not yet implemented"
}

# --- Help & Version -----------------------------------------------------------

usage() {
  cat <<'USAGE'
nomad — portable shell environment manager

Usage: nomad <command> [args]

Commands:
  init [path]          Scaffold a new config directory (default: current dir)
  apply [path] [-P]    Apply config: resolve deps, install packages, link files
                         -P, --no-packages  Skip bulk package install
  profile <name>       Set this machine's profile
  enable <module>      Enable a module on this machine
  disable <module>     Disable a module on this machine
  list                 List all modules and their status
  doctor               Validate config and check for issues
  help                 Show this help
  version              Show version

USAGE
}

version() {
  echo "nomad $NOMAD_VERSION"
}

# --- Main ---------------------------------------------------------------------

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    init) cmd_init "$@" ;;
    apply) cmd_apply "$@" ;;
    profile) cmd_profile "$@" ;;
    enable) cmd_enable "$@" ;;
    disable) cmd_disable "$@" ;;
    list) cmd_list "$@" ;;
    doctor) cmd_doctor "$@" ;;
    version | --version | -v) version ;;
    help | --help | -h | "") usage ;;
    *) error "Unknown command: $cmd" ;;
  esac
}

# Only run main if not being sourced (enables bats testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

# --- Thank You Call Again -----------------------------------------------------
