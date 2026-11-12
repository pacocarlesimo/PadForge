# Testing PadForge

    sh tests/fetch-ui-source.sh    # once, and after a game patch
    sh tests/run-all.sh

| Check | What it proves | Needs the UI source |
|---|---|---|
| `luacheck .` | no unused or never-set variables, no typos in locals | no |
| `tests/run.lua` | logic: profiles, import / export, migrations, claims, the ground rules (static) | no |
| `tests/apicheck.lua` | every `C_Xxx.Yyy` PadForge uses exists on WoW Forever, or is used behind a test; no dead events | yes |
| `tests/sim/run.lua` | PadForge on a simulated client, driven with a simulated pad | yes |
| `/pf selftest` (in the game) | what only the real client knows | - |

## The simulator (tests/sim)

`tests/.wow-ui-source` (or `$WOW_UI_SOURCE`) is a checkout of the game's UI
source for WoW Forever. The simulator loads the game's own files from it:

- `Blizzard_RestrictedAddOnEnvironment` and `SecureTemplates.lua`: secure
  snippets run in the real restricted environment, clicks go through the
  real `SecureActionButton_OnClick`, state drivers through the real manager;
- `Blizzard_GamepadSharedUtility`: the real binding stack and the real
  `FrameControlsManager`, so "does a game window have the pad" is the
  game's answer, not ours;
- `StaticPopupGamepad.lua`: the real popup focus handling;
- `Blizzard_APIDocumentationGenerated`: widgets only have the methods the
  client documents for their type, namespaces only their documented functions.

Around that, `sim/wow.lua` models the C side: frames, override bindings
(priority, the triggers as SHIFT / CTRL), macro conditions, combat
lockdown, secret values, and who is running (the game or the addon).
It records what the client would block, and any break of the ground rules
(addon code changing a game frame, calling the game's gamepad code, or
closing a game window).

What it can't know, and `/pf selftest` plus a play session must confirm:

- how the C side orders two priority override bindings on one key from two
  owners (the simulator says the latest wins);
- taint carried by values rather than by calls;
- atlas names, and anything else that isn't in the UI source.
