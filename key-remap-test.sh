#!/bin/env bash

#keycode=52 # 'z' keycode in qwerty
#char='z' # original character

keycode=65 # 'space' keycode in qwerty
char='space' # original character

keysym='Shift_L'

unused=103

echo "Remapping keys code=${keycode}/char='${char}' => ${keysym}" >&2
xmodmap -e "keycode ${unused}=${char}"
xmodmap -e "keycode ${keycode}=${keysym}"

echo 'Running xcape (Ctrl+C to stop it)..' >&2
xcape -d -e "#${keycode}=${char}"

echo 'Cleaning up key remaps..' >&2
xmodmap -e "keycode ${unused}="
xmodmap -e "keycode ${keycode}=${char}"

echo "Done." >&2
