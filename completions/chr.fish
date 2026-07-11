# Copyright 2026 Igalia S.L.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
# Fish completions for chr - Chromium development helper

complete -c chr -f

function __chr_no_subcommand
    not __fish_seen_subcommand_from bootstrap env config build run help
end

# Produce "alias\tdescription" lines for chr config alias completions
function __chr_config_aliases
    chr config -l -v 2>/dev/null | while read -l line
        set -l m (string match -r '(\S+)\s{2,}(.+)' -- $line)
        test (count $m) -ge 3; and printf '%s\t%s\n' $m[2] (string trim $m[3])
    end
end

# True when -- has been seen in the current chr config invocation
function __chr_config_after_dashdash
    contains -- -- (commandline -opc)
end

# gn gen flags: hardcoded common ones with descriptions + dynamic rest from 'gn help gen'
function __chr_gn_gen_flags
    # --check only appears in prose in 'gn help gen', so add manually
    printf '%s\t%s\n' \
        '--check'        'Check header dependency correctness' \
        '--check=system' 'Also check system headers'
    # --ide= values
    printf '%s\t%s\n' \
        '--ide=json'      'JSON compile commands (for IDEs)' \
        '--ide=eclipse'   'Eclipse CDT settings file' \
        '--ide=qtcreator' 'QtCreator project files' \
        '--ide=xcode'     'Xcode workspace/solution' \
        '--ide=vs'        'Visual Studio project/solution'
    # Remaining flags parsed from gn help gen (no per-flag descriptions)
    set -l gn ~/projects/chromium/src/buildtools/linux64/gn
    test -x $gn; or return
    $gn help gen 2>/dev/null \
        | string match -r '^ {2}(--[a-zA-Z][a-zA-Z0-9-]*=?)' \
        | string match -r '^--.*' \
        | grep -v '^--ide=' \
        | grep -v '^--check' \
        | sort -u
end

# --- Subcommands ---
complete -c chr -n __chr_no_subcommand -a bootstrap -d 'Initialize submodules'
complete -c chr -n __chr_no_subcommand -a env       -d 'Print environment setup commands'
complete -c chr -n __chr_no_subcommand -a config    -d 'Configure and generate build files'
complete -c chr -n __chr_no_subcommand -a build     -d 'Build targets'
complete -c chr -n __chr_no_subcommand -a run       -d 'Run a built binary'
complete -c chr -n __chr_no_subcommand -a help      -d 'Show help'

# --- chr env ---
complete -c chr -n '__fish_seen_subcommand_from env' -l bash  -d 'Print bash-compatible exports'
complete -c chr -n '__fish_seen_subcommand_from env' -l sh    -d 'Print POSIX sh exports'
complete -c chr -n '__fish_seen_subcommand_from env' -l icecc -d 'Include icecc variables'

# --- chr config (before --) ---
complete -c chr -n '__fish_seen_subcommand_from config; and not __chr_config_after_dashdash' \
    -s l -l list-aliases -d 'List available build aliases'
complete -c chr -n '__fish_seen_subcommand_from config; and not __chr_config_after_dashdash' \
    -s v -l verbose -d 'Show builder group/name with -l'
complete -c chr -n '__fish_seen_subcommand_from config; and not __chr_config_after_dashdash' \
    -s n -l dry-run -d 'Print commands without executing'
complete -c chr -n '__fish_seen_subcommand_from config; and not __chr_config_after_dashdash' \
    -s u -l update-compdb -d 'Regenerate compile_commands.json and update symlink'
complete -c chr -n '__fish_seen_subcommand_from config; and not __chr_config_after_dashdash' \
    -s o -l outdir -r -d 'Override output directory'
complete -c chr -n '__fish_seen_subcommand_from config; and not __chr_config_after_dashdash' \
    -a '(__chr_config_aliases)'
complete -c chr -n '__fish_seen_subcommand_from config; and not __chr_config_after_dashdash' \
    -f -a '(__chr_mb_group_completions)'
complete -c chr -n '__fish_seen_subcommand_from config; and not __chr_config_after_dashdash' \
    -f -a '(__chr_mb_builder_completions)'

# Extract the current --group= value from the command line tokens
function __chr_config_group_value
    set -l tokens (commandline -opc)
    set -l n (count $tokens)
    for i in (seq 1 $n)
        set -l t $tokens[$i]
        if test $t = '--group'
            set -l j (math $i + 1)
            test $j -le $n; and echo $tokens[$j]
            return
        end
        set -l m (string match -r '^--group=(.+)' -- $t)
        test (count $m) -ge 2; and echo $m[2]; and return
    end
end

# --group=VALUE completions: all groups from gn_args_locations.json
function __chr_mb_group_completions
    set -l f ~/projects/chromium/src/infra/config/generated/builders/gn_args_locations.json
    test -f $f; or return
    python3 -c "
import json, sys
for g in sorted(json.load(open(sys.argv[1]))):
    print('--group=' + g)
" $f 2>/dev/null
end

# --builder=VALUE completions: builders for the current --group, only if the group is valid
function __chr_mb_builder_completions
    set -l group (__chr_config_group_value)
    test -n "$group"; or return
    set -l f ~/projects/chromium/src/infra/config/generated/builders/gn_args_locations.json
    test -f $f; or return
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
g = sys.argv[2]
if g in d:
    for b in sorted(d[g]):
        print('--builder=' + b)
" $f $group 2>/dev/null
end

# gn build args (key=\tdefault) from chr config --list-gn-args (blocklist applied there)
function __chr_gn_build_args
    chr config --list-gn-args 2>/dev/null
end

# --- chr config (after --): gn gen flags and gn build args ---
complete -c chr -n '__fish_seen_subcommand_from config; and __chr_config_after_dashdash' \
    -a '(__chr_gn_gen_flags)'
complete -c chr -n '__fish_seen_subcommand_from config; and __chr_config_after_dashdash' \
    -a '(__chr_gn_build_args)'
