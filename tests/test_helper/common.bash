# Common test helper for nomad bats tests

# Source the nomad script to get all functions
NOMAD_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
source "$NOMAD_ROOT/nomad"

# Create a fresh temp directory for each test
setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_CONFIG="$TEST_DIR/config"
  NOMAD_STATE_DIR="$TEST_DIR/state"
  mkdir -p "$TEST_CONFIG/modules"
  mkdir -p "$TEST_CONFIG/profiles"
}

# Clean up after each test
teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: create a module directory with optional deps file content
create_module() {
  local name="$1"
  local deps_content="${2:-}"
  mkdir -p "$TEST_CONFIG/modules/$name"
  if [[ -n "$deps_content" ]]; then
    printf '%s\n' "$deps_content" >"$TEST_CONFIG/modules/$name/deps"
  fi
}

# Helper: load module deps and run toposort
run_toposort() {
  local config_dir="$1"
  shift
  load_module_deps "$config_dir" "$@"
  toposort
}
