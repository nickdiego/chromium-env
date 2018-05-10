# ex: ts=2 sw=4 et filetype=sh

if [ -n "$BASH_VERSION" ]; then
    thisscript="${BASH_SOURCE[0]}"
elif [ -n "$ZSH_VERSION" ]; then
    thisscript="${(%):-%N}"
else
    echo "Unsupported shell!"
    exit 1
fi

chromiumdir=$(cd `dirname $thisscript`; pwd)
srcdir="${chromiumdir}/src"
builddir="out/Ozone"

# Setup depot_tools
depot="${chromiumdir}/tools/depot_tools"
if [ -r "$depot" ]; then
    export PATH="${depot}:$PATH"

    if [ -n "$BASH_VERSION" ]; then
        echo "Laoading bash completion to 'gclient' command"
        source "${depot}/gclient_completion.sh"
    fi

    chromiun_venv=${CHROMIUM_VENV:-~/venvs/chromium}
    if [ -d ${chromium_venv} ]; then
        source ${chromiun_venv}/bin/activate
    else
        echo "WARNING: chromium python virtualenv not found [${chromiun_venv}]!"
    fi
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
