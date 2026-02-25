#!/usr/bin/env bash
set -euo pipefail

# --- Constants ---------------------------------------------------------------

NOMAD_VERSION="0.1.0"
NOMAD_STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nomad"

# --- Utility Functions -------------------------------------------------------

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

# --- OS Detection ------------------------------------------------------------

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

# --- Module Discovery --------------------------------------------------------

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

# --- Deps File Parsing -------------------------------------------------------

parse_deps() {
  local deps_file="$1"

  if [[ ! -f "$deps_file" ]]; then
    return 0
  fi

  local after="" pkg="" cmd="" os=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim_comment "$line")"
    line="$(trim "$line")"

    [[ -z "$line" ]] && continue

    case "$line" in
      after:*) after="$(trim "${line#after:}")" ;;
      pkg:*) pkg="$(trim "${line#pkg:}")" ;;
      cmd:*) cmd="$(trim "${line#cmd:}")" ;;
      os:*) os="$(trim "${line#os:}")" ;;
      *)
        warn "Unknown directive in $deps_file: $line"
        ;;
    esac
  done <"$deps_file"

  # Output as KEY=VALUE text protocol. Bash 3.2 (macOS default) lacks
  # associative arrays and namerefs, so we use simple text that gets
  # parsed with IFS='=' read.
  if [[ -n "$after" ]]; then echo "AFTER=$after"; fi
  if [[ -n "$pkg" ]]; then echo "PKG=$pkg"; fi
  if [[ -n "$cmd" ]]; then echo "CMD=$cmd"; fi
  if [[ -n "$os" ]]; then echo "OS=$os"; fi
}

# Parse all module deps files once and populate global parallel arrays.
# After calling this, the following arrays are set (indexed same as _modules):
#   _modules[i] = module name
#   _mod_after[i] = "after:" value (space-separated module names)
#   _mod_pkg[i]   = "pkg:" value (space-separated package names)
#   _mod_cmd[i]   = "cmd:" value
#   _mod_os[i]    = "os:" value
# Each deps file is read exactly once. Later phases (toposort, OS filtering,
# package collection) all consume these arrays instead of re-reading files.
load_module_deps() {
  local config_dir="$1"
  shift
  # Remaining args are module names

  _modules=("$@")
  _mod_after=()
  _mod_pkg=()
  _mod_cmd=()
  _mod_os=()

  local mod
  for mod in "$@"; do
    local deps_file="$config_dir/modules/$mod/deps"
    local after="" pkg="" cmd="" os=""

    if [[ -f "$deps_file" ]]; then
      local parsed
      parsed="$(parse_deps "$deps_file")"
      local k v
      while IFS='=' read -r k v; do
        case "$k" in
          AFTER) after="$v" ;;
          PKG) pkg="$v" ;;
          CMD) cmd="$v" ;;
          OS) os="$v" ;;
        esac
      done <<<"$parsed"
    fi

    _mod_after+=("$after")
    _mod_pkg+=("$pkg")
    _mod_cmd+=("$cmd")
    _mod_os+=("$os")
  done
}

# --- Topological Sort --------------------------------------------------------

# Lookup index of a module name in the modules array.
# Returns the index via stdout, or returns 1 if not found.
index_of() {
  local needle="$1"
  shift
  local i=0
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      echo "$i"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

# Topological sort using Kahn's algorithm (BFS-based).
#
# Reads from the global arrays populated by load_module_deps:
#   _modules[]    - module names
#   _mod_after[]  - each module's "after:" dependencies
#
# Outputs module names in dependency order. Modules with no ordering
# constraint between them are sorted alphabetically for determinism.
#
# Detects cycles: if not all modules can be placed, reports which are stuck.
# Unknown dependencies (e.g. "after: homebrew" when homebrew isn't in the
# module list) are warned about and skipped - this keeps configs portable
# across machines where some modules may not exist.
#
# Uses parallel indexed arrays instead of associative arrays for bash 3.2
# compatibility (macOS default). index_of does linear lookups, which
# is fine for the expected scale (<50 modules).
toposort() {
  local count=${#_modules[@]}

  if ((count == 0)); then
    return 0
  fi

  # Build parallel arrays for the graph:
  #   indegree[i] = number of unresolved dependencies for _modules[i]
  #   edges[i]    = space-separated names of modules that depend on _modules[i]
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
        if dep_idx="$(index_of "$dep" "${_modules[@]}")"; then
          # Add this module as a successor of dep
          edges[$dep_idx]="${edges[$dep_idx]:+${edges[$dep_idx]} }${_modules[$i]}"
          # This module has one more incoming edge
          indegree[$i]=$((${indegree[$i]} + 1))
        else
          warn "Module '${_modules[$i]}' depends on unknown module '$dep' (skipping dependency)"
        fi
      done
    fi
  done

  # Seed the queue with modules that have no dependencies (indegree 0).
  # Sort alphabetically so the output is deterministic.
  local -a queue=()
  for ((i = 0; i < count; i++)); do
    if ((${indegree[$i]} == 0)); then
      queue+=("${_modules[$i]}")
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
    cur_idx="$(index_of "$current" "${_modules[@]}")"

    # For each module that depends on current, decrement its in-degree
    local -a newly_free=()
    if [[ -n "${edges[$cur_idx]}" ]]; then
      for successor in ${edges[$cur_idx]}; do
        local succ_idx
        succ_idx="$(index_of "$successor" "${_modules[@]}")"
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
        warn "  ${_modules[$i]} (blocked)"
      fi
    done
    return 1
  fi

  printf '%s\n' "${result[@]}"
}

# --- Init Command ------------------------------------------------------------

cmd_init() {
  local target="${1:-.}"

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
# PATH setup - add your custom paths here
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

# --- Stub Commands -----------------------------------------------------------

cmd_apply() {
  error "apply is not yet implemented"
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

# --- Help & Version ----------------------------------------------------------

usage() {
  cat <<'USAGE'
nomad - portable shell environment manager

Usage: nomad <command> [args]

Commands:
  init [path]          Scaffold a new config directory (default: current dir)
  apply [path]         Apply config: resolve deps, install packages, link files
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

# --- Main Dispatch -----------------------------------------------------------

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
