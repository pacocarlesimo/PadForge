# Changelog

## 1.0.1

Checked against the game's own UI source for 1.60.1, and tested on a simulated client that runs the game's real secure code, binding stack, focus manager and popup handler.

- **Fix: popup answers never bound, and every PadForge button went dead while a popup was up.** An invite, resurrect, summon or duel popup that comes by itself doesn't take the controller, but the game still notes it as its "focused frame". PadForge read that as "a game window has the pad", so A / B never answered it, and Smart buttons, paddles and wheels were off until it closed. The same happened with a window left open after stepping back to the character. PadForge now reads only whether the game's UI is focused.
- **Fix: raid markers.** The Markers wheel ran a script, which the game refuses (with a warning popup) until the player has allowed scripts. It now uses the game's own /tm.
- **Fix: a second quick press of A could answer the next popup.** An answer now lets go of A / B at once.
- **Fix: Jump and Cancel lost for a whole fight** when a fight started with an answerable popup still up. Popup answers are never bound across a fight.
- Fix: "/pf center" and the list of elements in the middle of the screen failed with an error on the real client.
- Fix: an error drawing the Group wheel where the game keeps unit names secret.
- Fix: macros showed a question mark instead of their icon.
- The right stick is found by name the way this client does it (the function used before isn't on WoW Forever).
- **/pf selftest**: checks in the game what PadForge relies on (controller, crossbar buttons, popups, focus) and keeps the report in the saved settings.
- Tests: tests/sim runs PadForge on the game's own Lua; tests/apicheck.lua checks every game function used against the client's documentation.

## 1.0.0

First stable release.

- Vibration is taken out: WoW Forever doesn't pass it on to the controller reliably on every system.
- The troubleshooting tools are taken out (log file, diagnostics, /pf diag, /pf log, /pf safe). Old saves are cleaned up by themselves.
- Includes every fix of the betas: no "PadForge has been blocked" errors (no game setting changed by itself, no game code run under PadForge's name, nothing bound while a game window holds the pad, secret combat numbers never touched).

## 1.0.0-beta20

- The motor test (/pf vibe test, "Test each motor") now goes into the log too, with the game's answer for each motor.

## 1.0.0-beta19

- **Log file kept by itself at the end of every session** (logout or /reload), not only when the game blocks PadForge.
- **Vibration in the log**: whether the game offers vibration, the active controller and its name, the game's own vibration setting, the module and strength, and every vibration tried (event or test) with the game's answer for each motor. One log file tells why the pad stays still.

## 1.0.0-beta18

Found from a player's log file:

- **Fix: blocked "SetPreferredGamepadInteractTarget()" and "UseAction()".** WoW Forever makes many combat numbers secret (damage, health, cooldowns): the vibration's "big hit" check compared the damage taken, which is an error on every hit in combat; and PadForge handed each error to the game's error handler, running the game's code under PadForge's name. That spread to the gamepad window code and even the action buttons. PadForge now keeps its errors to itself (log file and /pf diag only), and checks every number the game can make secret before using it: damage, health, threat, cooldowns, item counts, chat lines. A secret value is simply skipped (no LOWEST mark is guessed on the Group wheel then).
- A test now fails if PadForge ever calls the game's error handler again, and the test client hands out secret values like the real one.

## 1.0.0-beta17

- **Log file**: diagnostics are kept in PadForge's saved variables, written to disk on /reload or logout (WTF/Account/<account>/SavedVariables/PadForge.lua). Kept by itself whenever the game blocks PadForge; /pf log (or Help > Save the log to a file) keeps one any time. The last 10.

## 1.0.0-beta16

A full audit against what an addon may and may not do with WoW Forever's gamepad UI. Everything that could taint the game's code is gone, and a test now fails if any of it comes back.

- **Fix: blocked "SetPreferredGamepadInteractTarget()" after a fight / looting.** The wheels changed a gamepad setting (stick directions as keys) at the start and end of every fight; that ran the game's gamepad code under PadForge's name, and the next window to close (the loot window) was blocked. PadForge no longer changes any game setting by itself.
- Wheels: point, then A (or hold the wheel button, aim, let it go). The "let the stick go" mode needed that setting and is gone.
- Movement & camera settings are written only when you change them, never at login, on a profile switch or entering a dungeon; the page says when a profile's values differ, with a button to apply them.
- No function or method of the game's Lua is called any more: popups, the glyph style and the controller's focus are only read.
- The minimap button is no longer a child of the minimap.
- Vibration page: says at once whether the game can vibrate your controller, and why not.

## 1.0.0-beta15

- Vibration: **/pf vibe test** (or the Test button on the Vibration page) drives each motor for a second, says which in chat, and reports why the pad may stay still: no controller active, the game's own vibration setting off (with a button to turn it on), the module off.

## 1.0.0-beta14

- **Fix: blocked "SetPreferredGamepadInteractTarget()".** That error comes when a game window that holds the controller closes after an addon bound or took the pad's buttons while it was open. PadForge no longer does, anywhere:
  - popup answers only while no game window (the popup itself included) has the controller: when it has it, the game's own A / B answer it;
  - at the start of a fight, a game window holding the controller keeps PadForge's buttons off for that fight;
  - the PadForge window, the element picker and moving the wheel don't open over a game window, and the PadForge window steps aside when one opens.

## 1.0.0-beta13

- **Fix: "PadForge has been blocked from an action only available to the Blizzard UI".** The PadForge window is no longer in the game's Escape list (UISpecialFrames): the game walks it as Escape or the pad's Menu opens its menu, which tainted the gamepad menu's code. The page in Options > AddOns is gone for the same reason (open PadForge from the minimap button, /pf or its key binding).
- When the game blocks PadForge, it now says which function at once in chat, and /pf diag shows it with the steps just before.

## 1.0.0-beta12

- **Vibration**: the pad rumbles on the moments you pick (low health keeps a heartbeat, big hits, aggro, interrupts, death, invites, ready checks, whispers, rare loot, level up, wheel use, finished casts). A pattern per event, overall strength, a test for each.
- **Group targeting**: "Next / Previous group member" on any button steps through you, your party or the raid, skipping the dead and the absent, in combat too. The Group wheel shows health under each member and marks the LOWEST.
- **Profile per place**: a profile of its own for dungeons, raids and battlegrounds / arenas, switched as you enter and leave.
- **Quick setup**: offered the first time PadForge opens. Built-in wheels, a Spells wheel and Smart X, made only from spells the character already knows; the Spells wheel grows as the suggested spells are learned.
- **Mounts wheel** built in (RB + R3): class mounts and travel forms you know, companions, the mount journal, mount items. A **Pets** wheel source too.

## 1.0.0-beta11

- The wheel now sits right of your character by default, and more see-through (45%). Profiles still on the old default place are moved; ones you placed yourself are left alone.

## 1.0.0-beta10

- Macros: PadForge binds the macros you make in the game (/macro); writing macros inside PadForge (beta9) is taken out. The Macros tab now comes right after Spells, sorted by name, and says how to make one when you have none.
- Profiles can't carry free macro text any more: an imported string can only name your own macros.

## 1.0.0-beta9

- **Write macros in PadForge** ("/cast !Stealth"...): a "Write a macro" tab in the action list and a Macros page to edit or remove them. Editing a macro updates every button and wheel slot that uses it. Saved in the profile, so exports carry them. Game macros (/macro) are in the "WoW macros" tab.

## 1.0.0-beta8

- **Minimap button**: click to open PadForge, right-click for profiles, drag it round the minimap to move it. Hide it on the Start page or with /pf minimap.

## 1.0.0-beta7

- **Wheels: Look & position.** Move the wheel by dragging it with the mouse or nudging it with the D-pad. Themes (Dark, Midnight, Frost, Fel, Blood, Arcane, Glass), background and highlight colours from a palette, opacity, overall size, ring radius, icon size, and whether the name, the slot label and the hints show. Changes preview live.

## 1.0.0-beta6

- Auto switch keyboard / pad taken out: WoW Forever doesn't change its layout reliably from an addon. Its settings are removed from saved profiles.
- Kept from beta4: PadForge never takes the keyboard anywhere.

## 1.0.0-beta5

- **Auto switch now changes the whole layout.** On WoW Forever the bars only change on an interface reload (as with the option in Options); when the game doesn't reload by itself, PadForge does.
- Since each switch is a short loading screen: 3 s of grace after every load, at least 5 s between switches (adjustable), and the mouse no longer counts by default.

## 1.0.0-beta4

- **Fix: the keyboard stopped working** with Auto switch on (its key watcher swallowed every key on some clients). PadForge now never takes the keyboard anywhere: keys are only read.
- The PadForge window and the element picker no longer take the keyboard either (pad and mouse drive them; Escape closes the window).

## 1.0.0-beta3

- **Auto switch** (new, opt-in): the game's interface switches to keyboard & mouse or the Gamepad UI by itself, after 2 s (adjustable) on the other device. Never in combat; typing in chat doesn't count. `/pf switch pad | keyboard` by hand.
- Wheels are no longer on R3 by default (R3 is the game's ping). Wheels page: "Put the 4 built-in wheels on R3" turns them on in one press.

## 1.0.0-beta2

- The quest item icon only shows once a button uses the quest item (no more "/pf to bind" on screen).
- Hide elements also finds the game's button legend (top left) by name; if it isn't found, hide it with /pf pick.

## 1.0.0-beta1

First public beta.

- **Buttons**: free A / B / X / Y (always, or Smart: only while an enemy is targeted / in combat). Trigger layers stay the crossbar's. Actions on paddles, L3, R3 and Share with 4 layers each. Move the game's own actions (Jump, Interact, Auto Run...) to another button.
- **Wheels**: up to 8 radial wheels, 12 slots each, working in combat. Sources: Items, Consumables, Quest items, Raid markers, Chat phrases, Group, Mounts, Custom. Flick to use, or hold-aim-release, or confirm with A. Opening with the stick already pushed never fires a slot.
- **Quest item**: one secure button always holding the best quest item, an on-screen icon, skip / reset.
- **Popup answers**: invites, resurrects, release spirit, summons, ready checks, loot confirmations, duels. The popup's own button is clicked, after a grace time. Left alone when a game window has the pad.
- **Hide elements**: by name (swing / shot timers, Issue Reporter), at the middle of the screen, or picked with the mouse. Faded, never changed.
- **Movement & camera**: the client's gamepad CVars, only those that exist, saved per profile, reset to the game's defaults.
- **Profiles**: per character and per spec, export (whole or by section) / import with a preview, snapshots, schema migrations.
- **Window**: fully driven by the pad, mouse and keyboard; closes for combat.
