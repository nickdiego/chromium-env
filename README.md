### My chromium development env

Intended to be used as root/container directory for chromium development files
(source files, tools, configuration and other kind of files involved), this repo
provides a set of shell helper functions/scripts to speedup bootstrap, setting up,
building and running chrome and other chromium artifacts/tools.

*Tested only on Arch Linux with recent versions of bash and zsh*

A common setup would be cloning it in `$HOME`, for example. After
[having installed the system dependencies](https://chromium.googlesource.com/chromium/src/+/master/docs/linux_build_instructions.md#Install-additional-build-dependencies), run the following to bootstrap the env:

```sh
source env.sh && chr_bootstrap
```
This will run some sanity checks, download `depot_tools`, configure right python
interpreter (if needed) and set some env variables, needed for the next steps.

*From now on, we assume you're in a shell with `env.sh` sourced.*

#### Syncing the source files

Fetching chromium sources at `<path/to/this/repo>/src`.

```sh
gclient sync
```
#### Distributed builds with Goma

Nowadays, [Goma](https://chromium.googlesource.com/infra/goma/client/)
is used for running distributed builds of Chromium. It relies on
Google's cloud-based build cluster infrastructure to provide a
distributed cache mechanism and massively parallelize the compilation
process, dramatically reducing build times (e.g: clean builds < 30min).

*Unfortunately, for now, it's not publicly available, rather is limited
to early access users :(*

By default, goma is enabled in Chromium builds configured using chr\_\*
helper scritps, which should work out-of-the-box. To disable it, pass in
`--no-goma` to `chr_set_config`/`chr_config`.

#### Distributed builds with Icecc

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

#### Configuring (generating `build.ninja` file)_

As these scripts have been written with Igalia's Ozone/Wayland development
in mind, they assume you might need to maintain downstream and upstream builds
in separate locations, so that they can be maintained simultaneosly, saving some
time when switching over them.

So, supposing you're working on upstream features (eg: upstream/master) and wants
to build `chrome` with Ozone backends enabled, run:

```sh
chr_config --variant=ozone --type=release
```
This will generate build directory at `<path/to/this/repo>/src/out/release/ozone`.

#### Building

To build chrome or pass additional paramaters (e.g: number of jobs, etc), run:

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

Conceived and mainly intended to be used for Igalia's Ozone/Wayland/X11 development
workflow. Even though it should be useful for general chromium devel, some features
such as bash/zsh completion support only ozone/wayland/linux specific bits.

