# ex: ts=2 sw=4 et filetype=sh

is_bash() { test -n "$BASH_VERSION"; }
is_zsh() { test -n "$ZSH_VERSION"; }

if is_bash; then
    thisscript="${BASH_SOURCE[0]}"
elif is_zsh; then
    thisscript="${(%):-%N}"
else
    echo "Unsupported shell!"
    exit 1
fi

chromiumdir="$(cd $(dirname $thisscript); pwd)"
srcdir="${chromiumdir}/src"
gn_args=()

use_icecc=${CHR_USE_ICECC:-1}

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

ccache_ensure_config() {
    local config_file=$1 key=$2 value=$3
    local config_file_dir=$(dirname $config_file)
    test -d $config_file_dir || mkdir -p $config_file_dir
    test -f $config_file || touch $config_file
    grep -qw $key $config_file || echo "$key = $value" >> $config_file
}

chr_ccache_setup() {
    if [ -z $variant ]; then
        echo "!! Error: Cannot setup ccache with no \$variant set!" >&2
        echo "!! Run chr_config ??" >&2
        return 1
    fi

    export CCACHE_BASEDIR=$chromiumdir
    export CCACHE_DIR="${chromiumdir}/cache/ccache/${variant}"
    export CCACHE_CPP2=yes
    export CCACHE_SLOPPINESS='include_file_mtime,time_macros'
    export CCACHE_DEPEND=true
    ccache_ensure_config "${CCACHE_DIR}/ccache.conf" \
        max_size ${CHR_CCACHE_SIZE:-50G}
}

chr_dump_config() {
    echo "### srcdir: $srcdir"
    echo "### outdir: $srcdir/$builddir"
    echo "### variant: $variant"
    echo "### type: $build_type"
    echo "### python: $(which python)"
    # Verbose?
    [ "$1" != '-v' ] && return
    echo "### python ver: $(python --version 2>&1)"
    echo "### gn args:"
    for arg in "${gn_args[@]}"; do
        echo "    $arg"
    done
    if [ "${#extra_gn_args[@]}" -gt 0 ]; then
        echo "### extra gn args:"
        for arg in "${extra_gn_args[@]}"; do
            echo "    $arg"
        done
    fi
}

_config_opts=( --variant=linux --variant=cros --variant=lacros --variant=custom
                --type=release --type=debug --no-glib --ccache --component
                --check --no-goma --update-compdb --enable-lacros-support
                --quiet)
chr_setconfig() {
    local quiet=0
    local use_component=0
    local use_glib=1

    # output
    variant='linux'
    build_type='release'
    gn_args=( 'enable_nacl=false' 'proprietary_codecs=true' 'ffmpeg_branding="Chrome"')
    extra_gn_args=()

    use_goma=1
    use_ccache=0
    use_icecc=0
    update_compdb=0
    cros_with_lacros_support=0

    # Tmp for debugging. TODO: Add cmd line option?
    cros_camera=${cros_camera:-0}
    enable_vaapi=${enable_vaapi:-0}

    while (( $# )); do
        case $1 in
            --variant=*)
                variant=${1##--variant=}
                ;;
            --type=*)
                build_type=${1##--type=}
                ;;
            --ccache)
                use_ccache=1
                ;;
            --no-glib)
                use_glib=0
                ;;
            --component)
                use_component=1
                ;;
            --no-goma)
                use_goma=0
                ;;
            --update-compdb)
                update_compdb=1
                ;;
            --enable-lacros-support)
                cros_with_lacros_support=1
                ;;
            --quiet|-q)
                quiet=1
                ;;
            --*)
                extra_gn_args+=("$1")
                ;;
        esac
        shift
    done

    case "$variant" in
        linux)
            gn_args+=('ozone_auto_platforms=false' 'use_ozone=true'
                      'use_xkbcommon=true' 'ozone_platform_wayland=true'
                      'ozone_platform_x11=true')

            (( enable_vaapi )) && gn_args+=('use_vaapi=true')
            (( cros_camera )) && gn_args+=('enable_chromeos_camera_capture=true')
            ;;
        cros)
            use_glib=0
            gn_args+=('target_os="chromeos"' 'use_xkbcommon=true'
                      'use_system_minigbm=false' 'use_intel_minigbm=true')
            ;;
        lacros)
            use_glib=0
            gn_args+=('target_os="chromeos"' 'use_ozone=true'
                      'use_xkbcommon=true' 'ozone_auto_platforms=false'
                      'ozone_platform_wayland=true' 'ozone_platform="wayland"'
                      'ozone_platform_x11=false' 'use_system_minigbm=true'
                      'use_system_libdrm=true' 'use_wayland_gbm=false'
                      'use_glib=false' 'use_gtk=false'
                      'chromeos_is_browser_only=true'
                      'also_build_ash_chrome=false')
            ;;
    esac

    if (( use_goma )); then
        use_component=1
        use_ccache=0
        use_icecc=0
    elif (( use_component )); then
        use_icecc=1
        use_ccache=1
    fi

    gn_opts=()
    for arg in "${extra_gn_args}"; do
        if [[ ! "$arg" =~ --args=.+ ]]; then
            gn_opts+=("$arg")
            continue
        fi
        local args_val=$(eval "echo ${arg##--args=}")
        gn_args+=($args_val)
    done

    # goma build
    if (( use_goma )); then
        gn_args+=( 'use_goma=true' )
    else
        # FIXME: Work around ENOENT errors for polymer.m.js
        gn_args+=( 'optimize_webui=false' )
    fi

    # icecc
    if (( use_icecc )); then
        gn_args+=( 'linux_use_bundled_binutils=false' 'use_debug_fission=false' )
        # FIXME: Mainly when using icecc, for some reason, we get
        # some compiling warnings, so we disable warning-as-error for now
        gn_args+=( 'treat_warnings_as_errors=false' )
    fi

    # component build
    if (( use_component )); then
        gn_args+=( 'is_component_build=true' )
        (( use_goma )) || variant+='-component'
    fi

    (( use_ccache )) && gn_args+=( 'cc_wrapper="ccache"' )

    (( use_glib )) && gn_args+=( 'use_glib=true' )

    if [ "$build_type" = 'release' ]; then
        builddir_base='out'
        gn_args+=( 'is_debug=false' 'blink_symbol_level=0' )
        # Make it more debuggable even for release builds
        gn_args+=( 'symbol_level=1' 'dcheck_always_on=true' 'dcheck_is_configurable=false' )
    else
        builddir_base='out/debug'
        gn_args+=( 'is_debug=true' 'symbol_level=1' )
    fi

    # Handle Google Keys (getting them from env vars).
    test -n "$GOOGLE_API_KEY" &&
        gn_args+=( "google_api_key=\"$GOOGLE_API_KEY\"" )
    test -n "$GOOGLE_DEFAULT_CLIENT_SECRET" &&
        gn_args+=( "google_default_client_secret=\"$GOOGLE_DEFAULT_CLIENT_SECRET\"" )
    test -n "$GOOGLE_DEFAULT_CLIENT_ID" &&
        gn_args+=( "google_default_client_id=\"$GOOGLE_DEFAULT_CLIENT_ID\"" )

    if (( update_compdb )); then
        local compdb_targets=${CHR_COMPDB_TARGETS:-chrome}
        gn_opts+=(--export-compile-commands="$compdb_targets")
    fi

    builddir="${builddir_base}/${variant}"
    lacros_sock='/tmp/lacros.sock'

    # Keep this at the end of this function
    chr_icecc_setup >/dev/null
    chr_ccache_setup >/dev/null

    (( quiet )) || chr_dump_config
}

chr_config() {
    chr_setconfig $@
    local cmd="gn gen \"$builddir\" ${gn_opts[@]} --args='${gn_args[*]}'"
    local compdb="${srcdir}/compile_commands.json"
    echo "Running cmd: $cmd"
    ( cd "$srcdir" && eval "$cmd" )
    if (( update_compdb )) && [ ! -e $compdb ]; then
        ln -sf "${builddir}/compile_commands.json" "$compdb" && \
            echo "Updated $compdb" >&2
    fi
}

on_build_starting() {
    build_log_file=$(mktemp /tmp/chr_build_XXXXXX.log)
    echo "Logging build details to ${build_log_file}." >&2

    (( use_ccache )) && ccache --zero-stats

    (( use_goma && !GOMA_DISABLED )) || return
    echo "Ensuring Goma client is running.." >&2
    {
        # Ensure compiler_proxy daemon is started
        echo "Starting goma client..."
        goma_ctl ensure_start
    } &> $build_log_file
}

on_build_finished() {
    (( chr_build_running )) || return

    local stop_goma=${stop_goma:-1}
    (( use_goma && !GOMA_DISABLED && stop_goma )) || return
    echo "Stopping Goma..." >&2
    trap "" SIGINT
    {
        echo "Stopping goma client...but before, some stats:"
        echo "========================= GOMA STATS BEGIN"
        goma_ctl stat
        echo "=========================== GOMA STATS END"
        goma_ctl ensure_stop
    } &> $build_log_file

    chr_build_running=0
}

chr_build() {
    local artifact="${@:-chrome}"
    local wrapper='time'
    local cmd="$wrapper ninja -C $builddir $artifact"
    local result=0

    on_build_starting
    trap on_build_finished SIGINT
    chr_build_running=1

    echo "Running cmd: $cmd"
    ( cd "$srcdir" && eval "$cmd" )
    result=$?

    on_build_finished
    trap - SIGINT

    return $result
}

chr_get_user_data_dir() {
  local dir="${user_dir:-${chromiumdir}/tmp/chr_tmp}_${variant}"
  echo $dir
}

chr_run() {
    local user_dir
    local wayland_ws=wayland
    local clear=${clear:-0}
    local ozone_plat_default=wayland
    local extra_args=("$@")
    local opts=( --enable-logging=stderr --no-sandbox )
    local is_wayland=0
    local is_lacros=0

    case "$variant" in
        linux)
            if [[ "${extra_args[*]}" =~ --ozone-platform=wayland ]]; then
                is_wayland=1
            elif [[ ! "${extra_args[*]}" =~ --ozone-platform=.+ ]]; then
                echo "Using default ozone platform '$ozone_plat_default'"
                extra_args+=( "--ozone-platform=${ozone_plat_default}" )
            fi
            ;;
        cros)
            extra_args+=('--enable-wayland-server'
                         '--wayland-server-socket=wayland-exo'
                         '--no-startup-window --ash-dev-shortcuts')
            if (( cros_with_lacros_support )); then
                extra_args+=('--enable-features=LacrosSupport'
                             "--lacros-mojo-socket-for-testing=${lacros_sock}")
            fi
            ;;
        lacros)
            is_lacros=1
            ;;
    esac
    user_dir="$(chr_get_user_data_dir)"
    opts+=("--user-data-dir=${user_dir}")

    if (( clear )) && [ -n "$user_dir" ]; then
        echo "Cleaning ${user_dir}"
        test -d "$user_dir" && rm -rf "$user_dir"
    fi

    local cmd="${builddir}/chrome ${opts[*]} ${extra_args[*]}"
    local -a env prefix_cmd

    if (( is_wayland )); then
        cmd="env GDK_BACKEND=wayland $cmd"
        # If running wayland compositor in an i3 session, move to the
        # $wayland_ws workspace
        _has 'i3-msg' && i3-msg workspace $wayland_ws
    elif (( is_lacros )); then
        env=('EGL_PLATFORM=surfaceless' 'WAYLAND_DISPLAY=wayland-exo')
        prefix_cmd=('build/lacros/mojo_connection_lacros_launcher.py'
                    '-s' "$lacros_sock")
        cmd="env ${env[*]} ${prefix_cmd[*]} $cmd"
    fi

    echo "Running cmd: $cmd"
    ( cd "$srcdir" && eval "$cmd" )
}

chr_icecc_setup() {
    # 2. Update icecc bundle
    (( use_icecc )) || return 0
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
        ) &>$logfile
    fi

    # Export config vars
    export ICECC_CLANG_REMOTE_CPP=1
    export ICECC_VERSION=$icecc_bundle_path
    export CCACHE_PREFIX='icecc'
    export PATH="${ICECC_INSTALL_DIR}/bin:$PATH"
    echo 'Done.'
}

_goma_setup_opts=( -u --update -l --login )
chr_goma_setup() {
    local update=0 login=0

    # 2. Update goma client
    test -n "$GOMA_INSTALL_DIR" || { echo "goma install dir not found"; return 1; }

    while (( $# )); do
        case $1 in
            -u | --update) update=1;;
            -l | --login) login=1;;
        esac
        shift
    done

    if (( update )); then
        echo "Updating goma client: ${GOMA_INSTALL_DIR}"
        cipd install infra/goma/client/linux-amd64 -root $GOMA_INSTALL_DIR
    fi

    if (( login )); then
        # Ensure is authorized
        goma_auth login
    fi
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
if is_bash; then
    complete -W "${_config_opts[*]}" chr_setconfig
    complete -W "${_config_opts[*]}" chr_config
    complete -W "${_list_patches_opts[*]}" chr_list_patches
    complete -W "${_goma_setup_opts[*]}" chr_goma_setup
elif is_zsh; then
    compctl -k "(${_config_opts[*]})" chr_setconfig
    compctl -k "(${_config_opts[*]})" chr_config
    compctl -k "(${_list_patches_opts[*]})" chr_list_patches
    compctl -k "(${_goma_setup_opts[*]})" chr_goma_setup
fi

# Setup depot_tools
depot="${chromiumdir}/tools/depot_tools"
if [ -r "$depot" ]; then
    export PATH="${depot}:$PATH"

    if [ -n "$BASH_VERSION" ]; then
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

# Chrome env vars
# Needed for tests (browser tests?) when build dir is more than 1 level deeper
# (e.g: out/Default). If this is not set, embedded web test server fail to
# start cause it cannot find cert files.
export CR_SOURCE_ROOT=$srcdir

# Goma related vars
# FIXME: Could not use ${chromiumdir}/tools/goma cause cipd does not allow
# nested root dirs (cipd help init).
export GOMA_LOCAL_OUTPUT_CACHE_DIR="${chromiumdir}/cache/goma"
export GOMA_LOCAL_OUTPUT_CACHE_MAX_CACHE_AMOUNT_IN_MB=$((50*1024)) #50GB
# Required for lacros device builds.
export GOMA_ARBITRARY_TOOLCHAIN_SUPPORT=1


# Default config params
CHR_CONFIG_TARGET="${CHR_CONFIG_TARGET:---variant=linux}"
CHR_CONFIG_ARGS="${CHR_CONFIG_ARGS:---type=release}"
CHR_COMPDB_TARGETS="${CHR_COMPDB_TARGETS:-chrome,views_unittests,interactive_ui_tests,ozone_unittests}"

chr_setconfig -q $CHR_CONFIG_TARGET $CHR_CONFIG_ARGS

# Set a sufficiently large limit for file descriptors (Goma builds with
# -j2000 would complain if this is not set).
ulimit -n 4096

