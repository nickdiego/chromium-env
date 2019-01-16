### Chromium devel helper scripts

Intended to be used as root/container directory for chromium development files
(source files, tools, configuration and other kind of files involved).
So a common setup is to clone it in `$HOME`, for example and, after [having
installed the system dependencies](https://chromium.googlesource.com/chromium/src/+/master/docs/linux_build_instructions.md#Install-additional-build-dependencies),
run:

```sh
cd <path/to/this/repo> && source env.sh
chr_bootstrap
```

This will run some sanity checks, download `depot_tools`, configure right python
interpreter (if needed) and set some env variables, needed for the next steps.

*Tested only on Arch Linux for now*

#### Syncing the source files

Assuming you're in a shell with `env.sh` sourced, run:

```sh
gclient sync
```
Which will fetch chromium source code at `<path/to/this/repo>/src`.

#### Setting up ICECC

After [install and configure icecc in you host system](
https://github.com/icecc/icecream/blob/master/README.md#installation), export
the following variables (in your `bashrc`, for example):

*This step is necessary because `icecc` install dir, paths, etc differ in linux
distros. The default versions in `env.sh` are meant to work in Arch Linux (with
`icecream` AUR package installed).*

```sh
export ICECC_INSTALL_DIR=/usr/lib/icecc
export ICECC_CREATEENV="$ICECC_INSTALL_DIR/bin
```

Then generate the icecc bundle for current source repo:

```sh
chr_icecc_setup -u
```

This will output a `<path/to/this/repo>/icecc/icecc_clang.tgz` file, add `icecc`
bin paths to system `$PATH` var and export some necessary env variables, such as:

*`icecc` support was implemented based on previous work done by [Gyoyoung Kim's work](
https://github.com/Gyuyoung/ChromiumBuild) described [here](
https://blogs.igalia.com/gyuyoung/2018/01/11/share-my-experience-to-build-chromium-with-icecc/)*

```
ICECC_VERSION = /home/nick/projects/chromium/icecc/icecc_clang.tgz
CCACHE_PREFIX = icecc
```

#### Configuring (generating `build.ninja` file)_

As these scripts have been written with Igalia's Ozone/Wayland development
in mind, they assume you might need to maintain downstream and upstream builds
in separate locations, so that they can be maintained simultaneosly, saving some
time when switching over them.

So, supposing you're working on upstream features (eg: upstream/master) and wishes
to build `chrome` with Ozone/Wayland backend enabled, run:

```sh
chr_config --wayland --release upstream
```
This will generate build directory at `<path/to/this/repo>/src/out/release/upstream/ozone`.

#### Building

To build `chrome` target with no extra parameters, run:

```sh
chr_build
```
To build a different target or pass additional paramaters (e.g: number of jobs, etc), do:

```sh
chr_build -j200 chrome
```

#### Running `chrome`

Simple like that:

```sh
chr_run
```

Additional parameter are supported, for example:

```sh
chr_run --user-data-dir=/tmp/x --in-process-gpu
```

### Focus/Scope

Conceived and mainly intended to be used for Igalia's Ozone/Wayland development
workflow, Even though it should be useful for general chromium devel, some features
such as bash/zsh completion support only ozone/wayland/linux specific bits.

