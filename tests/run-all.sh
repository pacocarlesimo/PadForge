#!/bin/sh
# Every check, from the repo root: sh tests/run-all.sh
set -e
echo "== lint"
luacheck . --quiet
echo "== unit tests (small mock client)"
luajit tests/run.lua
echo "== API check (against the client's documentation)"
luajit tests/apicheck.lua
echo "== simulator (the game's own secure code, bindings, focus, popups)"
luajit tests/sim/run.lua
