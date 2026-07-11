### chromium-env

Container directory for Chromium development work: source tree, build configuration,
tools, logs. This is my daily driver for chromium devel, it contains shell helpers to
speed up the workflow (bootstrapping, env setup, build configuration, syncing/rebasing
branch stacks).

#### `scripts/chr` — where things are headed

The active development is on `scripts/chr`, a standalone script meant to replace the
old `env.sh` shell functions. The motivation is mostly ergonomics: a proper subcommand
interface, consistent flag style, strong tab completion across bash/fish/zsh, and
behavior that's easy to audit and extend without sourcing a pile of functions into your
shell.

`env.sh` still works but is legacy at this point. New features go into `chr`.

*Tested on Arch Linux with bash 5+, zsh and fish 4.8.*

---

#### Getting started

Clone into `$HOME` (or wherever makes sense), install the
[system dependencies](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/docs/linux/build_instructions.md#Install-additional-build-dependencies),
then run:

```sh
chr bootstrap
```

This initializes submodules and gets the environment ready for first use.

#### Environment setup

`chr env` prints shell-native export commands for `PATH`, `CHROMIUM_OUTPUT_DIR`, and
a few other variables the tooling expects. Source it on shell startup:

```sh
# fish
chr env | source

# bash/zsh
eval "$(chr env --bash)"
```

Append to your shell's rc file so it runs automatically. Pass `--icecc` if you use
[icecream](https://github.com/icecc/icecream) for distributed builds. Note: icecc
support is currently incomplete, only env variables are set for now.

#### Build configuration

`chr config` configures a build using Chromium's `mb` infrastructure. You give it a
short alias and it figures out the builder group, GN args, and output directory:

```sh
chr config linux-wayland         # linux/ozone/wayland release build
chr config linux-dbg             # debug build
chr config linux-wayland -u      # reconfigure + regenerate compile_commands.json
```

List what's available:

```sh
chr config -l          # aliases only
chr config -l -v       # show builder group and name too
```

You can also override individual GN args after `--`:

```sh
chr config linux-wayland -- is_debug=true symbol_level=1
```

#### Syncing and rebasing

`chr sync` is the main daily-driver command. It fetches latest `main`, runs
`gclient sync`, rebases your branch stack, and triggers a build. The stack is
auto-detected — just name the top branch (or nothing, to use the current one):

```sh
chr sync                                   # current branch is the top of the stack
chr sync chromod/my-branch-3               # explicit top
chr sync chromod/my-branch-3 --no-build    # skip build step
```

The full stack (all local branches between `origin/main` and the named tip) is walked
automatically, so you don't have to list every layer.

If you're on `main` or in detached HEAD state and don't specify a branch, it just
does the fetch + `gclient sync` + build without touching any branch stack.

On conflict, resolve it manually (`git add` + `git rebase --continue`) then re-run
`chr sync` with the same arguments — it will pick up where it left off.

#### Shell completion

Completions for bash, fish, and zsh live in `completions/`. They're dynamic: aliases,
GN args, branch names, and flags are all pulled from live data at completion time.

```sh
# fish — add to ~/.config/fish/config.fish
source ~/projects/chromium/completions/chr.fish

# bash — add to ~/.bashrc
source ~/projects/chromium/completions/chr.bash

# zsh — add to ~/.zshrc (before compinit)
fpath=(~/projects/chromium/completions $fpath)
```

#### Work in progress

`chr build` and `chr run` are stubbed out but not yet implemented — those will cover
building arbitrary targets and launching Chrome with the right environment variables,
replacing `chr_build`/`chr_run` from `env.sh`.

#### Contributing

Changes to `scripts/chr` and `completions/chr.bash` need to pass two checks:

- **[shellcheck](https://www.shellcheck.net/)** — static analysis, run as `shellcheck scripts/chr`
- **[shfmt](https://github.com/mvdan/sh)** — formatting, run as `shfmt --diff scripts/chr completions/chr.bash`
  (settings are picked up automatically from `.editorconfig`)

Both run in CI on every push and pull request. There's also a local pre-commit hook
in `.git/hooks/pre-commit` that runs shfmt on staged files — set it up once after
cloning and you'll catch formatting issues before they hit CI.
