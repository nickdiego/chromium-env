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

CHR_USE_ICECC=${CHR_USE_ICECC:-1}

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

_config_opts=( --wayland --x11 --release --no-jumbo --no-system-gbm upstream downstream )
chr_setconfig() {
    local release=1 jumbo=1 system_gbm=1
    local graphics='wayland'
    # TODO: automatically find out this
    local branch='downstream'

    # output
    gn_args=( 'enable_nacl=false' )

    while (( $# )); do
        case $1 in
            --wayland)
                graphics="ozone"
                ;;
            --x11)
                graphics="x11"
                ;;
            --release)
                release=1
                ;;
            --no-jumbo)
                jumbo=0
                ;;
            --no-system-gbm)
                system_gbm=0
                ;;
            *)
                branch=$1
                ;;
        esac
        shift
    done

    if [[ "$graphics" == 'ozone' ]]; then
        gn_args+=( 'use_ozone=true' 'use_xkbcommon=true' )
    fi

    if (( jumbo )); then
        gn_args+=( 'use_jumbo_build=true' )
    fi

    if (( release )); then
        builddir_base='out/release'
        gn_args+=( 'is_debug=false' 'remove_webcore_debug_symbols=true' )
        gn_args+=( 'symbol_level=1' 'dcheck_always_on=true' ) # make it more debuggable even for release builds
    else
        builddir_base='out/debug'
        gn_args+=( 'is_debug=true' 'symbol_level=1' )
    fi

    # TODO: Disable for upstream/master as it's not supported yet
    (( system_gbm )) && gn_args+=( 'use_system_minigbm=true' )

    if true; then  # TODO cmdline option?
        gn_args+=( 'cc_wrapper="ccache"' )
    fi

    if (( CHR_USE_ICECC )); then
        gn_args+=( 'linux_use_bundled_binutils=false' 'use_debug_fission=false' )
    fi

    builddir="${builddir_base}/${branch}/${graphics}"

    # Keep this at the end of this function
    chr_icecc_setup >/dev/null
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
    (cd "$srcdir" && eval "$cmd" )
}

chr_icecc_setup() {
    # 2. Update icecc bundle
    (( CHR_USE_ICECC )) || return 0
    test -d $ICECC_INSTALL_DIR || { echo "icecc install dir not found"; return 1; }
    test -x $ICECC_CREATEENV || { echo "icecc-create-env not found"; return 1; }
    test -x $ICECC_CCWRAPPER || { echo "icecc compilerwrapper not found"; return 1; }

    local icecc_bundle_path="${ICECC_DATA_DIR}/icecc_clang.tgz"

    if [[ "$1x" == "-ux" ]]; then
        echo "Updating icecc bundle: ${icecc_bundle_path}"
        local logfile="/tmp/chr_sync.log"
        # Update icecc bundle accoring to current config
        mkdir -pv $ICECC_DATA_DIR
        (
            set -e
            cd $(mktemp -d)
            eval "$ICECC_CREATEENV --clang ${LLVM_BIN_DIR}/clang &>$logfile"
            mv -f *.tar.gz $icecc_bundle_path
        )
    fi

    # Export config vars
    export ICECC_CLANG_REMOTE_CPP=1
    export ICECC_VERSION=$icecc_bundle_path
    export CCACHE_PREFIX='icecc'
    export PATH="${ICECC_INSTALL_DIR}/bin:$PATH"
    echo 'Done.'
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

CHR_CONFIG_TARGET="${CHR_CONFIG_TARGET:---wayland}"
CHR_CONFIG_ARGS="${CHR_CONFIG_ARGS:---release}"

ICECC_DATA_DIR="${chromiumdir}/icecc"
ICECC_INSTALL_DIR=${ICECC_INSTALL_DIR:-/usr/lib/icecream}
ICECC_CREATEENV=${ICECC_CREATEENV:-$ICECC_INSTALL_DIR/bin/icecc-create-env}
ICECC_CCWRAPPER=${ICECC_CCWRAPPER:-$ICECC_INSTALL_DIR/libexec/icecc/compilerwrapper}

chr_setconfig $CHR_CONFIG_TARGET $CHR_CONFIG_ARGS

