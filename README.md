# PadForge

![PadForge](media/logo.png)

**The controller addon for WoW Forever.** Free your face buttons, radial wheels that work in combat, one-press quest items, popups you can answer, and profiles you can share with a single string. One download. Never breaks the native gamepad UI.

PadForge doesn't replace Blizzard's Gamepad UI. It fixes what players asked for on the forums, and stays out of the way of everything else.

---

## What it fixes

| You said | PadForge |
|---|---|
| "Let us rebind A / B / X / Y!" | **Free any face button.** Put a spell on it always, or **Smart**: yours only while an enemy is targeted (or in combat), the game's own Jump / Interact / Cancel the rest of the time. Switches in combat. LT / RT + that button still run your crossbar. |
| "Freeing A means losing Jump" | **Move the game's own actions.** Jump, Interact, Auto Run... onto a paddle or a stick click. |
| "Not enough buttons" | **Paddles, L3, R3 and Share**, each with 4 actions: plain, LT, RT, LT+RT. |
| "Invites don't take focus, I died to one" | **Popup answers.** A = yes, B = no for invites, resurrects, release spirit, summons, ready checks, loot confirmations, duels. A short wait stops accidental answers. |
| "Can't use quest items with the controller" | **Quest item button.** One press always uses the right quest item: the newest one, quest starters first. With an icon so you know which. |
| "No radial menu for my stuff" | **Wheels that work in combat.** Items (quest items + consumables), raid markers, chat phrases, group targeting, mounts, or your own. Point and press A, or hold, aim and release. |
| "Healing with D-pad on raid frames is slow" | **Group targeting.** One button steps through the group, skipping the dead. The Group wheel shows everyone's health and marks the lowest. |
| "I don't know where to start" | **Quick setup.** A starting layout for your class, using only the spells you already know. It grows as you learn more. |
| "My dungeon setup isn't my questing setup" | **Profile per place.** Dungeon, raid and PvP profiles switch by themselves. |
| "The swing timer circle can't be turned off" | **Hide elements.** Hide the swing / shot timer, the Issue Reporter, or anything you pick on screen. |
| "The movement sliders don't do what they say" | **Movement & camera.** The real gamepad settings, set directly, saved in your profile. |
| "Other addons broke on update / lost my settings" | **Versioned settings** that are upgraded, never wiped. Snapshots before anything destructive. |

## Profiles you can share

- Profiles shared by all your characters; pick one per character, and per spec.
- **Export** a whole profile or just parts (buttons, wheels, popups...) as a string. Paste it on Discord, Wago or a forum.
- **Import** shows you what's inside before anything changes and always makes a new profile. A string can never run code.
- **Snapshots**: a copy is kept before every delete, reset and import.

## Built not to break

- Never changes the game's own frames: hiding is done with an animation of ours. Never calls the gamepad window manager, never hooks it.
- Your bindings step aside while a game window (bags, map, character) holds the pad, and come back when it lets go.
- Everything that must wait for combat to end waits, and then happens. No "Action blocked" popups.
- Each module is isolated: if one fails, the others keep working.
- Works side by side with other addons. If ConsolePort, Improved Forever: Wheel or Easy Controller is loaded, the overlapping PadForge module turns itself off and tells you once.

## Getting started

1. Install, log in, type **/pf**.
2. **Buttons**: pick a face button, choose *Smart*, pick a spell. Move Jump (or whatever it had) to a paddle if you want.
3. **Wheels**: press **R3** for Items, **LT + R3** for markers, **RT + R3** for chat, **LT + RT + R3** for group targeting.
4. **Popups**: on by default. A answers yes, B no.

### Wheel controls

- **Press** the wheel button, **point** with the right stick, press **A**.
- Or **hold** the wheel button, aim, **release** it.
- D-pad steps through slots, **A** uses, **B** closes. The left stick still walks.

### The PadForge window

D-pad to move and change, **A** select, **Y** clear, **X** the row's extra action, **LB / RB** pages, **B** back. The mouse works too.

## Commands

| | |
|---|---|
| `/pf` | open PadForge |
| `/pf profile <name>` | switch profile |
| `/pf questitem` | list quest items (`skip`, `reset`) |
| `/pf pick` | pick an element on screen to hide |
| `/pf center` | list elements in the middle of the screen |
| `/pf hide <name>` | hide / show a named element |

## Supported controllers

Every controller WoW Forever supports (XInput). Glyphs follow the pad in hand (Xbox, PlayStation, Switch) or the style you choose. Paddles on Elite, DualSense Edge and Steam Deck.

## Reporting a bug

Say your PadForge version (top of the /pf window), your controller, and what you did just before the problem.

## Credits

The safe ways to work with Forever's gamepad UI (focus reading, crossbar slots, secure wheels, fading frames) were learned from **Improved Forever** by markgravity and **Easy Controller - Forever** by moust4ki, both MIT. Button glyph atlas lists from Improved Forever. Thank you. See LICENSE-ThirdParty.md.

MIT licensed. Free, always.

## Development

The addon is the repository's root. `luajit tests/run.lua` runs the test suite against a mock WoW client (no game needed).

Releases: push a tag (`git tag v1.0.1 && git push --tags`). GitHub Actions runs the tests, packages the addon and uploads it to CurseForge and Wago when the `CF_API_KEY` / `WAGO_API_TOKEN` secrets are set.
