# nomadic

Portable shell environment manager. One bash script, no dependencies.

nomadic separates the **engine** (this script) from the **config** (your personal repo of dotfiles, shell config, scripts, and packages). Clone your config on any machine, run `nomadic apply`, and your environment is ready.

## Quick start

```bash
# Scaffold a new config directory
nomadic init ~/my-config

# Apply it
nomadic apply ~/my-config

# Next time, just:
nomadic apply
```

## How it works

1. Discovers modules in your config's `modules/` directory
2. Parses dependency ordering (`after:`) and topologically sorts them
3. Filters by OS and checks command requirements
4. For each module in order: runs setup scripts, creates symlinks, collects shell config
5. Writes a generated rc file and adds a source line to your shell rc

## Config directory structure

```
my-config/
  profiles/
    default             # list of module names

  modules/
    path/
      bash              # shell config (static text, appended to rc)
    homebrew/
      setup             # one-time install script (sourced)
      bash              # shell config
      deps              # os: macos
    neovim/
      links             # symlink mappings
      deps              # pkg: nvim
      config/
        nvim/
          init.lua
    git/
      links             # gitconfig -> ~/.gitconfig
      gitconfig
      deps              # pkg: git
```

## Module files

| File | Purpose |
|------|---------|
| `deps` | Dependency declarations (see below) |
| `bash` / `fish` / `zsh` | Shell config. Static files are concatenated; executable files are run and stdout is captured. OS-specific variants (e.g., `bash.macos`, `zsh.ubuntu`) are used when present, falling back to the base file |
| `setup` | One-time setup script, sourced in the current shell |
| `links` | Symlink mappings: `<source> <target>` per line, source relative to module dir, `~` expanded in target. Existing targets are skipped unless `--force` is used, which backs up the original to `~/.nomadic/backups/` |

## Deps file format

```
after: homebrew packages      # run after these modules
pkg: gnu-sed neovim           # abstract package names
cmd: gsed                     # required command (skip module if missing)
os: macos                     # only on these OSes (macos, ubuntu, arch, linux)
```

All directives are optional. No `deps` file = no constraints.

## Commands

```
nomadic init [path]         Scaffold a new config directory
nomadic apply [path] [-P] [-f]  Apply config (remembers path for next time)
  -P, --no-packages       Skip bulk package install
  -f, --force             Overwrite existing files when linking (backs up originals)
nomadic help                Show help
nomadic version             Show version
```

## Requirements

Bash 3.2+ (ships with macOS). No other dependencies.

## Testing

```bash
bats tests/
```

To test `nomadic apply` without touching your real shell config, run inside a temporary HOME:

```bash
tmp=$(mktemp -d)
cp -r ~/.nomadic "$tmp/.nomadic"
env HOME="$tmp" bash --norc --noprofile
# inside the clean shell:
./nomadic apply
source ~/.nomadic/config.bash
# exit when done — everything is throwaway
```
