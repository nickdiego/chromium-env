# ex: ts=2 sw=4 et filetype=sh

if [ -n "$BASH_VERSION" ]; then
    thisscript="${BASH_SOURCE[0]}"
elif [ -n "$ZSH_VERSION" ]; then
    thisscript="${(%):-%N}"
else
    echo "Unsupported shell!"
    exit 1
fi

chromiumdir="$(cd $(dirname $thisscript); pwd)"
srcdir="${chromiumdir}/src"
gn_args=()

_has() {
    type $1 >/dev/null 2>&1
}

chr_bootstrap() {
    echo "## Trying to bootstrap chromium env ${1:+(reason: $1)}" >&2

    _has git || { echo "!! Error: git not installed" >&2; return 1; }
    _has python2 || { echo "!! Error: python2 not installed" >&2; return 1; }

    GIT_DIR="${chromiumdir}/.git" git submodule update --init --recursive
    if [ ! -L "${chromiumdir}/tools/bin/python" ]; then
        mkdir -pv ${chromiumdir}/tools/bin
        ln -sv $(which python2) ${chromiumdir}/tools/bin/python
    fi

    if [ $? -ne 0 ]; then
        echo "WARN: Bootstrap failed!" >&2
        return 1
    else
        source $thisscript
        echo "Bootstrap done."
        return 0
    fi
}

_config_opts=( wayland x11 --release --no-jumbo)
chr_setconfig() {
    local config='wayland'
    local release=0 jumbo=1
    gn_args=( 'enable_nacl=false' )

    while (( $# )); do
        case $1 in
            wayland)
                buildvar="Ozone"
                gn_args+=( 'use_ozone=true' 'use_xkbcommon=true' )
                # TODO: Disable for upstream/master (?) as it's not supported yet
                gn_args+=( 'use_system_minigbm=true' )
                ;;
            x11)
                buildvar="Default"
                ;;
            --release)
                release=1
                ;;
            --no-jumbo)
                jumbo=0
                ;;
        esac
        shift
    done

    if (( jumbo )); then
        gn_args+=( 'use_jumbo_build=true' )
    fi

    if (( release )); then
        builddir_base='out/release'
        gn_args+=( 'is_debug=false' )
        gn_args+=( 'symbol_level=2' 'dcheck_always_on=true' ) # make it more debuggable even for release builds
    else
        builddir_base='out/debug'
        gn_args+=( 'is_debug=true' 'symbol_level=1' )
    fi

    if true; then  # TODO cmdline option?
        gn_args+=( 'cc_wrapper="ccache"' )
    fi

    builddir="${builddir_base}/${buildvar}"
}

chr_config() {
    chr_setconfig $@
    local cmd="gn gen \"$builddir\" --args='${gn_args[*]}'"
    echo "Running cmd: $cmd"
    ( cd "$srcdir" && eval "$cmd" )
}

chr_build() {
    local target="${1:-chrome}"
    local wrapper='time'
    local cmd="$wrapper ninja -C $builddir $target"
    echo "Running cmd: $cmd"
    ( cd "$srcdir" && eval "$cmd" )

}

chr_run() {
    local opts=(
        '--ozone-platform=wayland'
        '--no-sandbox'
    )
    local cmd="${builddir}/chrome ${opts[*]} $*"
    local weston_ws=2
    _has 'i3-msg' && i3-msg workspace $weston_ws
    echo "Running cmd: $cmd"
    eval "$cmd"
}

# bash/zsh completion
if _has complete; then
    complete -W "${_config_opts[*]}" chr_setconfig
    complete -W "${_config_opts[*]}" chr_config
elif _has compctl; then
    compctl -k "(${_config_opts[*]})" chr_setconfig
    compctl -k "(${_config_opts[*]})" chr_config
fi

# Setup depot_tools
depot="${chromiumdir}/tools/depot_tools"
if [ -r "$depot" ]; then
    export PATH="${depot}:$PATH"

    if [ -n "$BASH_VERSION" ]; then
        echo "Laoading bash completion to 'gclient' command"
        source "${depot}/gclient_completion.sh"
    fi

    py2path="${chromiumdir}/tools/bin"
    if [ -d "$py2path" ]; then
        export PATH="${py2path}:${PATH}"
    else
        chr_bootstrap "python2 wrapper not found"
    fi
else
    chr_bootstrap "depot_tools not found"
fi

if test -r ~/.boto; then
    export NO_AUTH_BOTO_CONFIG=~/.boto
fi

# Setup ccache
LLVM_BIN_DIR="${srcdir}/third_party/llvm-build/Release+Asserts/bin"
export CCACHE_DIR="${chromiumdir}/ccache"
export CCACHE_CPP2=yes
export CCACHE_SLOPPINESS=time_macros
export PATH="$LLVM_BIN_DIR:$PATH"


CHR_CONFIG_TARGET="${CHR_CONFIG_TARGET:-wayland}"
CHR_CONFIG_ARGS="${CHR_CONFIG_ARGS:-'--release'}"

chr_setconfig $CHR_CONFIG_TARGET $CHR_CONFIG_ARGS

