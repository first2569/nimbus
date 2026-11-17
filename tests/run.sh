#!/bin/sh
# Runs every test suite. Needs lune on PATH and CraftOS-PC unpacked in .tools/craftos-pc.
cd "$(dirname "$0")/.." || exit 1
R="$(cygpath -w "$PWD")"

lune run tests/kernel.luau && lune run tests/sha256.luau || exit 1
lune run tests/recovery_smoke.luau nimbus/recovery.lua || exit 1
lune run build/manifest.luau || exit 1 # the updater test needs a manifest that matches the files
lune run build/bundle.luau || exit 1

emu() { # emu <script> [args]: runs a test script in the headless emulator with the repo at /proj
  script="$1"; shift
  timeout 240 .tools/craftos-pc/CraftOS-PC_console.exe --headless --directory "$R\.tools\data" \
    --mount-ro "/proj=$R" --script "$R\tests\\$script" "$@" 2>&1 | tr -d '\r'
}

# Both installers, on an empty computer.
rm -rf .tools/data/computer/0 .tools/data/computer/1
emu install.lua >.tools/install.raw
grep -aE '^(ok   |FAIL|INSTALL)' .tools/install.raw | grep -av ' ok  ' | sed 's/ *$//' | awk '!seen[$0]++'
grep -aq '^INSTALL PASSED' .tools/install.raw || { tail -n 25 .tools/install.raw; exit 1; }

# The emulated computer lives in .tools/data and gets its own copy of nimbus, like a real install;
# the repo itself is only mounted read-only at /proj.
rm -rf .tools/data/computer/0 .tools/data/computer/1
mkdir -p .tools/data/computer/0 .tools/data/computer/1
cp -r nimbus startup.lua .tools/data/computer/0/
cp -r nimbus .tools/data/computer/1/ # the second computer for the network tests
emu acceptance.lua --args "--shutdown" >.tools/acceptance.raw
# headless mode echoes every partial write, so keep only the finished result lines
grep -aE '^(ok   |FAIL|ACCEPTANCE)' .tools/acceptance.raw | grep -av ' ok  ' | sed 's/ *$//' | awk '!seen[$0]++'
grep -aq '^ACCEPTANCE PASSED' .tools/acceptance.raw || { tail -n 25 .tools/acceptance.raw; exit 1; }
