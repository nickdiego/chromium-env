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

chr_ccache_setup() {
    if [ -z $variant ]; then
        echo "!! Error: Cannot setup ccache with no \$variant set!" >&2
        echo "!! Run chr_config ??" >&2
        return 1
    fi

    export CCACHE_DIR="${chromiumdir}/ccache/${variant}"
    export CCACHE_CPP2=yes
    export CCACHE_SLOPPINESS=time_macros
    export CCACHE_DEPEND=true
    export CCACHE_CONFIG_FILE="${CCACHE_DIR}/ccache.conf"
    test -d $CCACHE_DIR || mkdir -p $CCACHE_DIR
    test -f $CCACHE_CONFIG_FILE || touch $CCACHE_CONFIG_FILE
    grep -qw max_size $CCACHE_CONFIG_FILE || \
        echo "max_size = ${CHR_CCACHE_SIZE:-50G}" >> $CCACHE_CONFIG_FILE
}

_config_opts=( --variant=ozone --variant=x11 --variant=cros --variant=custom
               --release --no-jumbo --no-ccache --no-system-gbm --check)
chr_setconfig() {
    local release=1 jumbo=1 system_gbm=1 use_ccache=1

    # output
    variant='ozone'
    gn_args=( 'enable_nacl=false' )
    extra_gn_args=( )

    while (( $# )); do
        case $1 in
            --variant=*)
                variant=${1##--variant=}
                ;;
            --release)
                release=1
                ;;
            --no-jumbo)
                jumbo=0
                ;;
            --no-ccache)
                use_ccache=0
                ;;
            --no-system-gbm)
                system_gbm=0
                ;;
            --*)
                extra_gn_args+=( "$1" )
                ;;
        esac
        shift
    done

    case "$variant" in
        ozone)
            gn_args+=('ozone_auto_platforms=false' 'use_ozone=true' 'use_xkbcommon=true'
                      'ozone_platform_wayland=true' 'ozone_platform_x11=true')
            (( system_gbm )) &&
                gn_args+=( 'use_system_minigbm=true' 'use_system_libdrm=true')
            ;;
        cros)
            gn_args+=('target_os="chromeos"' 'use_xkbcommon=true')
            ;;
    esac

    for arg in "${extra_gn_args}"; do
        if [[ ! "$arg" =~ --args=.+ ]]; then
            gn_args+=("$arg")
            continue
        fi
        local args_val=$(eval "echo ${arg##--args=}")
        gn_args+=($args_val)
    done

    (( jumbo )) && gn_args+=( 'use_jumbo_build=true' )
    (( use_ccache )) && gn_args+=( 'cc_wrapper="ccache"' )
    (( CHR_USE_ICECC )) && gn_args+=( 'linux_use_bundled_binutils=false' 'use_debug_fission=false' )

    if (( release )); then
        builddir_base='out/release'
        gn_args+=( 'is_debug=false' 'blink_symbol_level=0' )
        gn_args+=( 'symbol_level=1' 'dcheck_always_on=true' ) # make it more debuggable even for release builds
    else
        builddir_base='out/debug'
        gn_args+=( 'is_debug=true' 'symbol_level=1' )
    fi

    # FIXME: Mainly when using icecc, for some reason, we get
    # some compiling warnings, so we disable warning-as-error for now
    gn_args+=( 'treat_warnings_as_errors=false' )

    builddir="${builddir_base}/${variant}"

    # Keep this at the end of this function
    chr_icecc_setup >/dev/null
    chr_ccache_setup >/dev/null
}

chr_config() {
    chr_setconfig $@
    local cmd="gn gen \"$builddir\" --args='${gn_args[*]}'"
    echo "Running cmd: $cmd"
    ( cd "$srcdir" && eval "$cmd" )
}

chr_build() {
    local artifact="${@:-chrome}"
    local wrapper='time'
    local cmd="$wrapper ninja -C $builddir $artifact"
    ccache --zero-stats
    echo "Running cmd: $cmd"
    ( cd "$srcdir" && eval "$cmd" )

}

chr_run() {
    local user_dir
    local wayland_ws=wayland
    local clear=${clear:-1}
    local ozone_plat_default=wayland
    local extra_args=$*
    local opts=( --enable-logging=stderr )

    case "$variant" in
        ozone)
            opts+=('--no-sandbox')
            if [[ ! "$extra_args" =~ --ozone-platform=.+ ]]; then
                echo "Using default ozone platform '$ozone_plat_default'"
                extra_args+="--ozone-platform=${ozone_plat_default}"
            fi
            # If running wayland compositor in an i3 session, move to the
            # $wayland_ws workspace
            [[ "$extra_args" =~ --ozone-platform=wayland ]] && \
                _has 'i3-msg' && i3-msg workspace $wayland_ws

            ;;
        cros)
            user_dir='/tmp/chr_cros'
            ;;
    esac
    user_dir=${user_dir:-/tmp/chr_tmp}
    opts+=("--user-data-dir=${user_dir}")

    if (( clear )) && [ -n "$user_dir" ]; then
        echo "Cleaning ${user_dir}"
        test -d "$user_dir" && rm -rf "$user_dir"
    fi

    local cmd="${builddir}/chrome ${opts[*]} $extra_args"
    echo "Running cmd: $cmd"
    ( cd "$srcdir" && eval "$cmd" )
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
            eval "$ICECC_CREATEENV --clang ${LLVM_BIN_DIR}/clang"
            mv -f *.tar.gz $icecc_bundle_path
            # Make sure we have a large enough space for ccache
            ccache -M $CCACHE_SIZE
        ) &>$logfile
    fi

    # Export config vars
    export ICECC_CLANG_REMOTE_CPP=1
    export ICECC_VERSION=$icecc_bundle_path
    export CCACHE_PREFIX='icecc'
    export PATH="${ICECC_INSTALL_DIR}/bin:$PATH"
    echo 'Done.'
}

date_offset() {
    date -d "$(date +%m/%d/%Y) -$*" +%m/%d/%y
}

_list_patches_opts=( --merged --week --month --year --markdown
                     --begin= --end= --user= --verbose )
chr_list_patches() {
    local script=my_activity.py
    local email=$(git config user.email)
    local opts=('--quiet' '--changes')
    local errors=$(mktemp /tmp/chr_XXXX.log)
    local verbose=${V:-0}
    local status_filter
    local time_filter # Default is "last_week"

    if ! type "$script" &>/dev/null; then
        echo "$script not found in system \$PATH." >&2
        return 1
    fi
    while (( $# )); do
        case $1 in
            -u | --user) shift && email=$1;;
            -v | --verbose) verbose=1;;
            --merged) status_filter='--merged-only';;
            --week) time_filter='--last_week';;
            --year) time_filter='--this_year';;
            --month) time_filter="--begin=$(date +%m/01/%y)";;
            [0-9]*d) time_filter="--begin=$(date_offset ${1:0:-1} day)";;
            [0-9]*w) time_filter="--begin=$(date_offset ${1:0:-1} week)";;
            [0-9]*m) time_filter="--begin=$(date_offset ${1:0:-1} month)";;
            [0-9]*y) time_filter="--begin=$(date_offset ${1:0:-1} year)";;
            --*) opts+=("$1");;
        esac
        shift
    done
    opts+=("-u $email" "$status_filter" "$time_filter" "${opts[@]}")

    # Build fetch command
    local cmd="$script ${opts[@]} 2> $errors"
    (( verbose )) && echo "cmd: '$cmd'" >&2

    # Fetch and process changes from crrev server
    local patches=$(eval "$cmd" | tail -n +3)

    # format and present output
    local total=$(wc -l <<< $patches)
    echo -e "Patches:\n"
    echo "$patches" | cat -
    echo -e "\nTotal: $total"
}

# bash/zsh completion
if _has complete; then
    complete -W "${_config_opts[*]}" chr_setconfig
    complete -W "${_config_opts[*]}" chr_config
    complete -W "${_list_patches_opts[*]}" chr_list_patches
elif _has compctl; then
    compctl -k "(${_config_opts[*]})" chr_setconfig
    compctl -k "(${_config_opts[*]})" chr_config
    compctl -k "(${_list_patches_opts[*]})" chr_list_patches
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

LLVM_BIN_DIR="${srcdir}/third_party/llvm-build/Release+Asserts/bin"
export PATH="$LLVM_BIN_DIR:$PATH"

# Basic icecc setup (the remaining is done in `chr_icecc_setup` function)
ICECC_DATA_DIR="${chromiumdir}/icecc"
ICECC_INSTALL_DIR=${ICECC_INSTALL_DIR:-/usr/lib/icecream}
ICECC_CREATEENV=${ICECC_CREATEENV:-$ICECC_INSTALL_DIR/bin/icecc-create-env}
ICECC_CCWRAPPER=${ICECC_CCWRAPPER:-$ICECC_INSTALL_DIR/libexec/icecc/compilerwrapper}

# Default config params
CHR_CONFIG_TARGET="${CHR_CONFIG_TARGET:---ozone}"
CHR_CONFIG_ARGS="${CHR_CONFIG_ARGS:---release}"

chr_setconfig $CHR_CONFIG_TARGET $CHR_CONFIG_ARGS

