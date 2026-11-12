#!/bin/sh
# Fetches the WoW Forever UI source the simulator tests run on: the game's
# own Lua, as mirrored at github.com/Gethe/wow-ui-source (branch "forever").
# It isn't kept in this repository. Run from the repo root.
set -e
DEST="${WOW_UI_SOURCE:-tests/.wow-ui-source}"
if [ -d "$DEST/.git" ]; then
    git -C "$DEST" fetch --depth 1 origin forever && git -C "$DEST" reset --hard FETCH_HEAD
else
    git clone --depth 1 --branch forever https://github.com/Gethe/wow-ui-source "$DEST"
fi
echo "UI source: $(cat "$DEST/version.txt" 2>/dev/null || git -C "$DEST" log -1 --format=%s)"
