# Fish completions for chr - Chromium development helper

complete -c chr -f

function __chr_no_subcommand
    not __fish_seen_subcommand_from bootstrap env config build run help
end

# Produce "alias\tdescription" lines for chr config completions
function __chr_config_aliases
    chr config -l -v 2>/dev/null | while read -l line
        set -l m (string match -r '(\S+)\s{2,}(.+)' -- $line)
        test (count $m) -ge 3; and printf '%s\t%s\n' $m[2] (string trim $m[3])
    end
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

# --- chr config ---
complete -c chr -n '__fish_seen_subcommand_from config' -s l -l list-aliases -d 'List available build aliases'
complete -c chr -n '__fish_seen_subcommand_from config' -s v -l verbose      -d 'Show builder group/name with -l'
complete -c chr -n '__fish_seen_subcommand_from config' -s n -l dry-run      -d 'Print commands without executing'
complete -c chr -n '__fish_seen_subcommand_from config' -s o -l outdir    -r -d 'Override output directory'
complete -c chr -n '__fish_seen_subcommand_from config'      -l extra-args -r -d 'Extra gn args to append'
complete -c chr -n '__fish_seen_subcommand_from config' -a '(__chr_config_aliases)'
