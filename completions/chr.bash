#!/usr/bin/env bash
# Bash completions for chr — chromium development helper
#
# Requires: bash-completion package (provides _init_completion)
# Activate: add to ~/.bashrc —
#   source ~/projects/chromium/completions/chr.bash

# ---- helpers ----------------------------------------------------------------

_chr_mb_groups() {
    local f=~/projects/chromium/src/infra/config/generated/builders/gn_args_locations.json
    [[ -f "$f" ]] || return
    python3 -c "
import json, sys
for g in sorted(json.load(open(sys.argv[1]))):
    print(g)
" "$f" 2>/dev/null
}

_chr_mb_builders() {
    local group="$1"
    [[ -z "$group" ]] && return
    local f=~/projects/chromium/src/infra/config/generated/builders/gn_args_locations.json
    [[ -f "$f" ]] || return
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
g = sys.argv[2]
if g in d:
    for b in sorted(d[g]):
        print(b)
" "$f" "$group" 2>/dev/null
}

_chr_gn_flags() {
    # --check only appears in prose in 'gn help gen', add manually
    printf '%s\n' --check --check=system \
        --ide=json --ide=eclipse --ide=qtcreator --ide=xcode --ide=vs
    local gn=~/projects/chromium/src/buildtools/linux64/gn
    [[ -x "$gn" ]] || return
    "$gn" help gen 2>/dev/null \
        | grep -oP '^ {2}\K--[a-zA-Z][a-zA-Z0-9-]*=?' \
        | grep -v '^--ide=' | grep -v '^--check' \
        | sort -u
}

_chr_gn_build_args() {
    local chr=~/projects/chromium
    local gn="$chr/src/buildtools/linux64/gn"
    local state="$chr/.chr_state"
    [[ -x "$gn" && -f "$state" ]] || return
    local outdir
    outdir=$(grep -m1 '^CHR_CONFIG_OUTDIR=' "$state" | cut -d= -f2-)
    [[ -n "$outdir" && -d "$chr/src/$outdir" ]] || return
    local -a _blocklist=(
        coverage_instrumentation_input_file
    )
    local _block_pat; _block_pat="^($(IFS='|'; echo "${_blocklist[*]}"))="

    (cd "$chr/src" && "$gn" args "$outdir" --list --short 2>/dev/null) \
        | awk -F' = ' '/^[a-zA-Z_]/ && NF>=2 {print $1 "="}' \
        | grep -vE "$_block_pat"
}

# ---- main completion --------------------------------------------------------

_chr() {
    local cur prev words cword
    _init_completion || return

    local subcommand='' after_dashdash=0 group_value=''
    local i
    for ((i = 1; i < cword; i++)); do
        case "${words[i]}" in
            --) after_dashdash=1; break ;;
            bootstrap|env|config|build|run|help) subcommand="${words[i]}" ;;
            --group=*) group_value="${words[i]#--group=}" ;;
            --group)   (( i + 1 < cword )) && group_value="${words[i+1]}" ;;
        esac
    done

    # --- after --: gn gen flags (--*) and gn build args (name=) --------------
    if (( after_dashdash )); then
        if [[ "$cur" == --* ]]; then
            mapfile -t COMPREPLY < <(compgen -W "$(_chr_gn_flags)" -- "$cur")
        elif [[ -n "$cur" ]]; then
            mapfile -t COMPREPLY < <(compgen -W "$(_chr_gn_build_args)" -- "$cur")
            compopt -o nospace
        fi
        return
    fi

    # --- handle prev-word options that take a value --------------------------
    case "$prev" in
        -o|--outdir) _filedir -d; return ;;
        --group)
            mapfile -t COMPREPLY < <(compgen -W "$(_chr_mb_groups)" -- "$cur")
            return ;;
        --builder)
            local b; b=$(_chr_mb_builders "$group_value")
            [[ -n "$b" ]] && mapfile -t COMPREPLY < <(compgen -W "$b" -- "$cur")
            return ;;
    esac

    # --- handle --opt=<value> style (current word contains =) ----------------
    case "$cur" in
        --group=*)
            local pfx="${cur#--group=}"
            mapfile -t COMPREPLY < <(compgen -P "--group=" -W "$(_chr_mb_groups)" -- "$pfx")
            compopt -o nospace
            return ;;
        --builder=*)
            local pfx="${cur#--builder=}"
            local b; b=$(_chr_mb_builders "$group_value")
            if [[ -n "$b" ]]; then
                mapfile -t COMPREPLY < <(compgen -P "--builder=" -W "$b" -- "$pfx")
            fi
            compopt -o nospace
            return ;;
        --outdir=*)
            local pfx="${cur#--outdir=}"
            mapfile -t COMPREPLY < <(compgen -d -- "$pfx" | sed 's|^|--outdir=|')
            compopt -o nospace
            return ;;
    esac

    # --- subcommand dispatch -------------------------------------------------
    case "$subcommand" in
        '')
            COMPREPLY=($(compgen -W "bootstrap env config build run help" -- "$cur"))
            ;;
        env)
            COMPREPLY=($(compgen -W "--bash --sh --icecc" -- "$cur"))
            ;;
        config)
            case "$cur" in
                --*)
                    COMPREPLY=($(compgen -W "
                        --list-aliases --verbose --dry-run --update-compdb
                        --outdir= --group= --builder=
                    " -- "$cur"))
                    # Suppress trailing space for options that expect a value via =
                    local c; for c in "${COMPREPLY[@]}"; do
                        [[ "$c" == *= ]] && compopt -o nospace && break
                    done
                    ;;
                -*)
                    COMPREPLY=($(compgen -W "-l -v -n -u -o" -- "$cur"))
                    ;;
                *)
                    mapfile -t COMPREPLY < <(compgen -W "$(chr config -l 2>/dev/null)" -- "$cur")
                    ;;
            esac
            ;;
    esac
}

complete -F _chr chr
