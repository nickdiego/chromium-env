#!/bin/env bash

# Script useful for fetching and scheduling local chromium builds using
# cronjobs, for example. It assumes there is a chromium checkout at
# $CHROMIUM_SRC and it is capable to save/restore current branch changes using
# `git stash`. Sources are fetched from $REMOTE git remote and and build occur
# in $BUILD_BRANCH branch.
#
## Author: Nick Diego Yamane <nickdiego@igalia.com>

CHROMIUM_DIR="$HOME/projects/chromium"
CHROMIUM_ENV="${CHROMIUM_DIR}/env.sh"
CHROMIUM_SRC="${CHROMIUM_DIR}/src"
LOGS_DIR="${CHROMIUM_DIR}/logs"

if [ ! -r "$CHROMIUM_ENV" ]; then
  echo "env.sh file not found! $CHROMIUM_ENV" >&2
  exit 1
fi

BUILD_ID="build_$(date "+%m-%d-%Y_%H:%M:%S%Z")"
LOG="${LOGS_DIR}/${BUILD_ID}.log"

# Config/build vars
VARIANTS=(ozone cros)
CONFIGS=('--goma' '--release' '--update-compdb')
TARGETS=(chrome)
NUM_JOBS=400

FETCH=${FETCH:-1}

# Git-related vars / functions
get_branch_name() {
  local branch_name=$(git symbolic-ref -q HEAD)
  branch_name=${branch_name##refs/heads/}
  echo ${branch_name}
}

has_pending_changes() {
  git diff-index --quiet HEAD --
  echo $?
}

save_and_fetch_build_branch() {
  (( FETCH )) || return

  if [ -z "$ORIGINAL_BRANCH" ]; then
    echo "Error: No idea on how to save/restore dettached branch." >&2
    return 1
  fi

  if (( IS_DIRTY )); then
    echo "### Saving uncommitted changes (branch=${ORIGINAL_BRANCH})"
    git stash push -m "TMP: ${BUILD_ID} @ $ORIGINAL_HEAD"
  fi

  echo "### Fetching latest chromium changes..."
  git fetch $REMOTE $UPSTREAM_BRANCH

  echo "### Switching to build branch '$BUILD_BRANCH'"
  git checkout -q -B $BUILD_BRANCH ${REMOTE}/$UPSTREAM_BRANCH
  git reset --hard FETCH_HEAD
  gclient sync
}

restore_original_branch_state() {
  (( FETCH )) || return

  echo "### Switching back to branch '$ORIGINAL_BRANCH'"
  git checkout -q $ORIGINAL_BRANCH
  if (( IS_DIRTY )); then
    local ref=$(git stash list -n1 --format=%s | awk -F'@ ' '{print $NF}')
    if [ "x$ORIGINAL_HEAD" != "x$ref" ]; then
      echo "!!! Failed to recover previous branch state" >&2
    else
      echo "### Restoring previous branch state.."
      git stash pop
    fi
  fi
  gclient sync
}

source "$CHROMIUM_ENV"
cd "$CHROMIUM_SRC"
mkdir -p "$LOGS_DIR"

REMOTE='origin'
UPSTREAM_BRANCH='master'
BUILD_BRANCH='AUTO_BUILD'
ORIGINAL_BRANCH=$(get_branch_name)
ORIGINAL_HEAD=$(git rev-parse HEAD)

# Init checkout "dirty" state
IS_DIRTY=$(has_pending_changes)

(
  # Dump build info
  echo -e "## Starting chromium build"
  echo -e "======== build id: $BUILD_ID"
  echo -e "======== source dir: $CHROMIUM_SRC"
  echo -e "======== previous branch: $ORIGINAL_BRANCH"
  echo -e "======== prev head: $ORIGINAL_HEAD"
  echo -e "======== log file: $LOG"
  echo -e "======== variants: ${VARIANTS[@]}"
  echo -e "======== options: ${CONFIGS[@]}"
  echo -e "======== starting time: $(date)\n"

  cd ${CHROMIUM_SRC}
  save_and_fetch_build_branch

  CHR_COMPDB_TARGETS=$TARGETS

  for variant in "${VARIANTS[@]}"; do
    echo "### Build for variant '$variant' [BEGIN]"
    chr_config "${CONFIGS[@]}" --variant=$variant
    chr_build -j${NUM_JOBS} "${TARGETS[@]}"
    echo "### Build for variant '$variant' [END]"
  done

  restore_original_branch_state
  echo -e "\n## DONE"
  echo -e "#### End time: $(date)\n"

) 2>&1 | tee $LOG

