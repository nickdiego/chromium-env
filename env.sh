# ex: ts=2 sw=4 et filetype=sh

case "$SHELL" in
    */zsh)
        thisscript="${(%):-%N}"
        ;;
    */bash)
        thisscript="${BASH_SOURCE[0]}"
        ;;
    *)
        echo "Unsupported shell!"
        exit 1
        ;;
    esac


chromiumdir=$(cd `dirname $thisscript`; pwd)
srcdir="${chromiumdir}/src"
builddir="out/Ozone"

# Setup depot_tools
depot="${chromiumdir}/tools/depot_tools"
if [ -r "$depot" ]; then
    export PATH="${depot}:$PATH"
else
    echo "WARNING: depot_tools dir does not exists [$depot]"
fi

# Setup ccache
LLVM_BIN_DIR="${srcdir}/third_party/llvm-build/Release+Asserts/bin"
export CCACHE_CPP2=yes
export CCACHE_SLOPPINESS=time_macros
export PATH="$LLVM_BIN_DIR:$PATH"

chr_config() {
    opts=(
        'use_ozone=true'
        'enable_mus=true'
        'use_xkbcommon=true'
        'enable_nacl=false'
        'symbol_level=1'
    )
    if true; then  # TODO cmdline option?
        opts+=( 'cc_wrapper="ccache"' )
    fi

    cmd="gn gen \"$builddir\" --args='${opts[*]}'"
    echo "Running cmd: $cmd"
    ( cd "$srcdir" && eval "$cmd" )
}

chr_build() {
    target="${1:-chrome}"
    ninja -C "$builddir" "$target"
}

chr_run() {
    opts=(
        '--mus'
        '--no-sandbox'
    )
    cmd="${builddir}/chrome ${opts[*]}"
    echo "Running cmd: $cmd"
    eval "$cmd"
}
