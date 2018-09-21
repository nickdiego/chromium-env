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
builddir="out/Ozone"
chromium_venv="${CHROMIUM_VIRTUALENV_PATH:-${chromiumdir}/venv}"

if test -r ~/.boto; then
    export NO_AUTH_BOTO_CONFIG=~/.boto
fi

_has() {
    type $1 >/dev/null 2>&1
}

chr_bootstrap() {
    echo "## Trying to bootstrap chromium env ${1:+(reason: $1)}" >&2

    _has git || { echo "!! Error: git not installed" >&2; return 1; }
    _has virtualenv || { echo "!! Error: virtualenv not installed" >&2; return 1; }

    GIT_DIR="${chromiumdir}/.git" git submodule update --init --recursive
    test -d "${chromiumdir}/venv" || virtualenv -p python2 "${chromiumdir}/venv"

    if [ $? -ne 0 ]; then
        echo "WARN: Bootstrap failed!" >&2
        return 1
    else
        source $thisscript
        echo "Bootstrap done."
        return 0
    fi
}

chr_config() {
    opts=(
        'use_ozone=true'
        'use_xkbcommon=true'
        'use_jumbo_build=true'
        'enable_nacl=false'
    )
    if true; then  # TODO cmdline option?
        opts+=( 'symbol_level=1' )
    fi

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
        '--ozone-platform=wayland'
        '--in-process-gpu'
        '--no-sandbox'
    )
    cmd="${builddir}/chrome ${opts[*]}"
    echo "Running cmd: $cmd"
    eval "$cmd"
}

# Setup depot_tools
depot="${chromiumdir}/tools/depot_tools"
if [ -r "$depot" ]; then
    export PATH="${depot}:$PATH"

    if [ -n "$BASH_VERSION" ]; then
        echo "Laoading bash completion to 'gclient' command"
        source "${depot}/gclient_completion.sh"
    fi

    if test -r ${chromium_venv}/bin/activate; then
        source ${chromium_venv}/bin/activate
    else
        chr_bootstrap "chromium virtualenv not found"
    fi
else
    chr_bootstrap "depot_tools not found"
fi

# Setup ccache
LLVM_BIN_DIR="${srcdir}/third_party/llvm-build/Release+Asserts/bin"
export CCACHE_DIR="${chromiumdir}/ccache"
export CCACHE_CPP2=yes
export CCACHE_SLOPPINESS=time_macros
export PATH="$LLVM_BIN_DIR:$PATH"

