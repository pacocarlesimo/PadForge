-- PadForge on the simulated WoW Forever client: the game's own secure
-- code, binding stack, focus manager and popup handler run for real.
--   luajit tests/sim/run.lua        (from the repo root)
-- Needs a checkout of the game's UI source: see tests/README.md.
package.path = "tests/?.lua;" .. package.path
local say = print
local Docs = require("sim.docs")
local root, tried = Docs.Root()
if not root then
    say("SKIPPED: no WoW Forever UI source at " .. tostring(tried) .. " (run tests/fetch-ui-source.sh)")
    os.exit(os.getenv("PF_REQUIRE_SIM") and 1 or 0)
end
local S = require("sim.wow")
local G = require("sim.game")

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        say("FAIL: " .. name .. (detail ~= nil and ("  -- " .. tostring(detail)) or ""))
    end
end
local function section(name) if os.getenv("PF_VERBOSE") then say("== " .. name) end end

G.Boot(root)
local PF = G.LoadAddon(".", "PadForge")
S.Advance(0.5)
-- From here the test's own calls into PadForge run as addon code (as its
-- window or a slash command would); S.Press, S.Fire, S.Advance and the
-- G helpers run as the game.
S.taint = "PadForge"

-- Nothing the client would refuse, nothing against the ground rules, no
-- Lua error: checked after every scenario
local function clean(where)
    check(where .. ": no Lua errors", #S.errors == 0, S.errors[1])
    check(where .. ": no errors caught by PadForge", #PF.errors == 0, PF.errors[1])
    check(where .. ": nothing blocked by the client", #S.blocked == 0, S.blocked[1])
    check(where .. ": no game frame or function touched by addon code", #S.violations == 0, S.violations[1])
    S.errors, S.blocked, S.violations = {}, {}, {}
    for i = #PF.errors, 1, -1 do PF.errors[i] = nil end
end
local function did(field, value)
    for _, rec in ipairs(S.performed) do
        if rec[field] == value then return rec end
    end
end
local function reset() S.performed = {} end
local function target(unit)
    S.units.target = unit
    S.Fire("PLAYER_TARGET_CHANGED")
    S.Advance(0.3)
end
local function settle() S.Advance(0.5) end

---------------------------------------------------------------------------
section("login")
check("database ready", PF.db ~= nil and PF.P() ~= nil)
check("every module running", (function()
    for _, def in ipairs(PF.moduleOrder) do if not def.running ~= (def.defaultOff or false) then return false end end
    return true
end)())
check("only events this client has are registered", next(S.unknownEvents) == nil, next(S.unknownEvents))
check("the game has the pad at login", PF.Binds.InGame())
check("A is the game's jump", S.RouteOf("PAD1") == "command:GAMEPADACTIONBUTTON8", S.RouteOf("PAD1"))
clean("login")

---------------------------------------------------------------------------
section("smart face button")
local Buttons, B = PF.Buttons, PF.Binds
Buttons.SetAction("PAD3", "N", "spell:133")
settle()
check("picking an action makes X smart", Buttons.Entry("PAD3").mode == "smart")
check("X ready", Buttons.status.PAD3 == "ready", Buttons.status.PAD3)
target(nil)
reset()
S.Tap("PAD3")
check("no enemy: X is the game's interact", did("command", "INTERACT") ~= nil, S.RouteOf("PAD3"))
target({ harm = true, hp = 50, max = 100, name = "Wolf" })
reset()
S.Tap("PAD3")
check("enemy targeted: X casts Fireball", did("cast", "Fireball") ~= nil, S.RouteOf("PAD3"))
check("...and not the game's interact", did("command", "INTERACT") == nil)
reset()
S.Press("PADLTRIGGER")
S.Tap("PAD3")
S.Release("PADLTRIGGER")
check("LT + X still runs the crossbar's left bar", did("action", "leftBar:5") ~= nil, S.performed[1] and (S.performed[1].cast or S.performed[1].command))
check("...and doesn't cast", did("cast", "Fireball") == nil)
reset()
S.Press("PADRTRIGGER")
S.Tap("PAD3")
S.Release("PADRTRIGGER")
check("RT + X runs the right bar", did("action", "rightBar:5") ~= nil)
reset()
S.Press("PADLTRIGGER") S.Press("PADRTRIGGER")
S.Tap("PAD3")
S.Release("PADRTRIGGER") S.Release("PADLTRIGGER")
check("LT + RT + X runs the bottom bar", did("action", "bottomBar:5") ~= nil)
-- the switch happens in combat too
target(nil)
S.EnterCombat()
reset()
S.Tap("PAD3")
check("in combat without an enemy: interact", did("command", "INTERACT") ~= nil)
target({ harm = true, hp = 50, max = 100, name = "Wolf" })
reset()
S.Tap("PAD3")
check("in combat, enemy targeted: casts", did("cast", "Fireball") ~= nil)
target({ harm = true, dead = true, hp = 0, max = 100, name = "Wolf" })
reset()
S.Tap("PAD3")
check("in combat, dead enemy: interact (to loot)", did("command", "INTERACT") ~= nil)
S.LeaveCombat()
settle()
target(nil)
clean("smart face button")

---------------------------------------------------------------------------
section("always-on face button and relocation")
Buttons.SetAction("PAD1", "N", "macro:Pull")
Buttons.SetMode("PAD1", "action")
Buttons.SetRelocation("PAD1", "PADPADDLE1")
settle()
reset()
S.Tap("PAD1")
check("A runs the macro", did("macro", "Pull") ~= nil, S.RouteOf("PAD1"))
check("...and doesn't jump", did("command", "JUMP") == nil)
reset()
S.Tap("PADPADDLE1")
check("Jump moved to paddle 1", did("command", "JUMP") ~= nil, S.RouteOf("PADPADDLE1"))
reset()
S.Press("PADLTRIGGER")
S.Tap("PAD1")
S.Release("PADLTRIGGER")
check("LT + A still the crossbar", did("action", "leftBar:8") ~= nil)
Buttons.SetMode("PAD1", "game")
Buttons.SetRelocation("PAD1", nil)
settle()
reset()
S.Tap("PAD1")
check("A back to the game's jump", did("command", "JUMP") ~= nil, S.RouteOf("PAD1"))
clean("always-on face button")

---------------------------------------------------------------------------
section("paddle layers")
Buttons.SetAction("PADPADDLE2", "N", "spell:116")
Buttons.SetAction("PADPADDLE2", "LT", "item:858")
Buttons.SetAction("PADPADDLE2", "RT", "target:player")
Buttons.SetAction("PADPADDLE2", "LTRT", "emote:WAVE")
settle()
reset() S.Tap("PADPADDLE2")
check("paddle: Frostbolt", did("cast", "Frostbolt") ~= nil, S.RouteOf("PADPADDLE2"))
reset() S.Press("PADLTRIGGER") S.Tap("PADPADDLE2") S.Release("PADLTRIGGER")
check("LT + paddle: the potion", did("item", "item:858") ~= nil)
reset() S.Press("PADRTRIGGER") S.Tap("PADPADDLE2") S.Release("PADRTRIGGER")
check("RT + paddle: target yourself", did("target", "player") ~= nil)
reset() S.Press("PADLTRIGGER") S.Press("PADRTRIGGER") S.Tap("PADPADDLE2") S.Release("PADRTRIGGER") S.Release("PADLTRIGGER")
check("LT + RT + paddle: the emote", did("emote", "WAVE") ~= nil)
S.cvars.ActionButtonUseKeyDown = "0"
S.Fire("CVAR_UPDATE", "ActionButtonUseKeyDown", "0")
settle()
reset() S.Press("PADPADDLE2")
check("cast on key up set: nothing on the press", did("cast", "Frostbolt") == nil)
S.Release("PADPADDLE2")
check("...the cast on the release, once", did("cast", "Frostbolt") ~= nil and #S.performed == 1, #S.performed)
S.cvars.ActionButtonUseKeyDown = "1"
S.Fire("CVAR_UPDATE", "ActionButtonUseKeyDown", "1")
settle()
clean("paddle layers")

---------------------------------------------------------------------------
section("game windows")
check("bags closed: world bindings on", B.applied.PADPADDLE2 ~= nil)
G.OpenPanel(ContainerFrameCombinedBags)
settle()
check("bags open and focused: the game says its window has the pad", G.Manager().isUIFocused == true)
check("PadForge sees the window", not B.InGame())
check("...and takes its world bindings off", B.applied.PADPADDLE2 == nil and S.RouteOf("PADPADDLE2") == "nothing", S.RouteOf("PADPADDLE2"))
S.Tap("PADBACK")      -- the player takes the controls back, bags still open
settle()
check("bags open but unfocused: the game says the player has the pad", G.Manager().isUIFocused == false and G.CoreInput())
check("...so PadForge's bindings are back", B.applied.PADPADDLE2 ~= nil, S.RouteOf("PADPADDLE2"))
S.AsGame(G.ClosePanel, ContainerFrameCombinedBags)
settle()
check("bags closed: bindings on", B.applied.PADPADDLE2 ~= nil)
clean("game windows")

---------------------------------------------------------------------------
section("popup answers")
target({ harm = true, hp = 50, max = 100, name = "Wolf" })
local popup = G.ShowPopup("PARTY_INVITE")
check("the invite doesn't take the pad (as on the real client)", G.Manager().isUIFocused == false and G.CoreInput())
S.Advance(0.2)
reset()
S.Tap("PAD1")
check("a press inside the grace time doesn't answer", popup:IsShown() and did("popup", "PARTY_INVITE") == nil)
S.Advance(1)
reset()
S.Tap("PAD3")
check("Smart X still casts while the invite is up", did("cast", "Fireball") ~= nil, S.RouteOf("PAD3"))
reset()
S.Tap("PAD1")
local answer = did("popup", "PARTY_INVITE")
check("A answers the invite", answer ~= nil and answer.answer == 1 and answer.call == "AcceptGroup", S.RouteOf("PAD1"))
check("...through the game's own button, untainted", answer ~= nil and answer.tainted == false)
check("the popup is gone", not popup:IsShown())
settle()
check("A is jump again", S.RouteOf("PAD1") == "command:GAMEPADACTIONBUTTON8", S.RouteOf("PAD1"))
popup = G.ShowPopup("PARTY_INVITE")
S.Advance(1)
reset()
S.Tap("PAD2")
answer = did("popup", "PARTY_INVITE")
check("B declines", answer ~= nil and answer.answer == 2 and answer.call == "DeclineGroup", S.RouteOf("PAD2"))
settle()
-- a popup the player focuses: the game's own A / B, ours out of the way
popup = G.ShowPopup("PARTY_INVITE")
S.Advance(1)
S.Tap("PADBACK")
settle()
check("focused popup: the game has it", G.Manager().isUIFocused == true and not G.CoreInput())
check("...PadForge's answer is off A", (S.RouteOf("PAD1")):find("InputFunctionBindingButton") ~= nil, S.RouteOf("PAD1"))
reset()
S.Tap("PAD1")
check("...and the game's own A answers", did("popup", "PARTY_INVITE") ~= nil)
settle()
-- in combat
S.EnterCombat()
popup = G.ShowPopup("RESURRECT")
S.Advance(1)
check("a popup in combat changes no binding", S.RouteOf("PAD1") == "command:GAMEPADACTIONBUTTON8", S.RouteOf("PAD1"))
S.LeaveCombat()
S.Advance(1)
reset()
S.Tap("PAD1")
check("answered once combat ends", did("popup", "RESURRECT") ~= nil, S.RouteOf("PAD1"))
settle()
-- an answer lets go of A at once: a second press must never land on a
-- popup that took the first one's place
popup = G.ShowPopup("PARTY_INVITE")
S.Advance(1)
reset()
S.Tap("PAD1")
check("invite answered", did("popup", "PARTY_INVITE") ~= nil)
local second = G.ShowPopup("DUEL_REQUESTED")     -- shows in the same frame, StaticPopup1
check("the next popup reuses the frame", second == popup)
reset()
S.Tap("PAD1")
check("a second quick press doesn't answer the popup that replaced it", did("popup", "DUEL_REQUESTED") == nil and second:IsShown(), S.RouteOf("PAD1"))
S.Advance(1)
reset()
S.Tap("PAD1")
check("...nor later: duel answers are off by default", did("popup", "DUEL_REQUESTED") == nil)
S.AsGame(G.HidePopup, second)
settle()
-- a popup still up as a fight starts: A must be the game's for the fight
popup = G.ShowPopup("PARTY_INVITE")
S.Advance(1)
check("bound before the fight", (S.RouteOf("PAD1")):find("PadForgePromptYes") ~= nil, S.RouteOf("PAD1"))
S.EnterCombat()
check("a fight starting takes the answer off A (jump is never lost for a fight)", S.RouteOf("PAD1") == "command:GAMEPADACTIONBUTTON8", S.RouteOf("PAD1"))
S.AsGame(G.HidePopup, popup)
S.Advance(0.5)
reset()
S.Tap("PAD1")
check("A jumps in combat", did("command", "JUMP") ~= nil)
S.LeaveCombat()
settle()
target(nil)
clean("popup answers")

---------------------------------------------------------------------------
section("wheels")
local Wheels = PF.Wheels
Wheels.UseDefaultLayout()
settle()
check("R3 opens the wheels", (S.RouteOf("PADRSTICK")):find("PadForgeWheelTrigger") ~= nil, S.RouteOf("PADRSTICK"))
local items = Wheels.Data(1)
check("Items wheel filled", items ~= nil and #items.slots >= 2, items and #items.slots)
S.SetStick(0, 0)
S.Tap("PADRSTICK")
check("ring open", PadForgeRing:IsShown())
check("A is the wheel's while it is open", (S.RouteOf("PAD1")):find("PadForgeWheelUse") ~= nil, S.RouteOf("PAD1"))
S.SetStick(0, 1)        -- up: the first slot
S.Advance(0.1)
reset()
S.Tap("PAD1")
check("point up + A uses the first slot", did("item", "item:" .. tostring(items.slots[1].action:match("%d+"))) ~= nil, items.slots[1].action)
check("ring closed after use", not PadForgeRing:IsShown())
check("A back to jump", S.RouteOf("PAD1") == "command:GAMEPADACTIONBUTTON8", S.RouteOf("PAD1"))
S.SetStick(0, 0)
-- hold, aim, release
S.Press("PADRSTICK")
S.SetStick(0, 1)
reset()
S.Release("PADRSTICK")
check("hold R3, aim, release: uses the slot", #S.performed == 1 and S.performed[1].item ~= nil, #S.performed)
S.SetStick(0, 0)
-- markers (LT + R3): in combat, with no script permission
S.EnterCombat()
target({ harm = true, hp = 50, max = 100, name = "Wolf" })
S.Press("PADLTRIGGER")
S.Tap("PADRSTICK")
S.Release("PADLTRIGGER")
check("LT + R3 opens the Markers wheel in combat", PadForgeRing:IsShown() and PadForgeRing:GetAttribute("pf-active") == 2, PadForgeRing:GetAttribute("pf-active"))
S.SetStick(0, 1)
reset()
S.Tap("PAD1")
local mark = did("marker", 8)
check("the skull goes on the target", mark ~= nil and mark.unit == "target", S.performed[1] and S.performed[1].popup)
check("...without needing the player to allow scripts", did("popup", "DANGEROUS_SCRIPTS_WARNING") == nil and (mark == nil or not mark.viaScript))
S.SetStick(0, 0)
S.Tap("PADRSTICK")
S.Tap("PAD2")
check("B closes the wheel", not PadForgeRing:IsShown())
S.LeaveCombat()
settle()
target(nil)
clean("wheels")

---------------------------------------------------------------------------
section("group and quest item")
G.group = true
S.units.party1 = { hp = 30, max = 100, name = "Healme" }
S.units.party2 = { hp = 0, max = 100, dead = true, name = "Dead" }
S.Fire("GROUP_ROSTER_UPDATE")
settle()
Buttons.SetAction("PADPADDLE3", "N", "groupnext")
Buttons.SetAction("PADPADDLE4", "N", "questitem")
settle()
reset() S.Tap("PADPADDLE3")
check("group step: yourself first", did("target", "player") ~= nil, S.RouteOf("PADPADDLE3"))
reset() S.Tap("PADPADDLE3")
check("...then party1", did("target", "party1") ~= nil)
reset() S.Tap("PADPADDLE3")
check("...the dead member skipped", did("target", "player") ~= nil)
reset() S.Tap("PADPADDLE4")
check("quest item used", did("item", "item:7500") ~= nil, S.RouteOf("PADPADDLE4"))
local lowest = PF.Group.Lowest({ "player", "party1", "party2" })
check("lowest living member", lowest == "party1", lowest)
G.secretHealth, G.secretNames, G.secretCooldowns = true, true, true
check("secret health: no guess", PF.Group.Lowest({ "player", "party1" }) == nil)
PF.RefreshModule("wheels")
settle()
S.Press("PADLTRIGGER") S.Press("PADRTRIGGER")
S.Tap("PADRSTICK")
S.Release("PADRTRIGGER") S.Release("PADLTRIGGER")
S.Advance(0.5)
check("Group wheel opens with secret names and health", PadForgeRing:IsShown() and PadForgeRing:GetAttribute("pf-active") == 4)
S.Tap("PAD2")
G.secretHealth, G.secretNames, G.secretCooldowns = false, false, false
PF.RefreshModule("wheels")
settle()
clean("group and quest item")

---------------------------------------------------------------------------
section("combat queue")
S.EnterCombat()
Buttons.SetAction("PADLSTICK", "N", "spell:133")
Wheels.SetChord("RB", 5)
PF.Interface.SetHidden("Minimap", true)
PF.DB.SetActive(PF.DB.New("Combat test"))
S.Advance(0.5)
check("changes in combat touch nothing protected", #S.blocked == 0, S.blocked[1])
S.LeaveCombat()
settle()
check("the profile switch happened after combat", PF.DB.ActiveName() == "Combat test")
PF.DB.SetActive("Default")
settle()
reset() S.Tap("PADLSTICK")
check("the action set in combat works after it", did("cast", "Fireball") ~= nil, S.RouteOf("PADLSTICK"))
check("hiding a game frame never changes it", PF.IsFaded(Minimap) and #S.violations == 0, S.violations[1])
PF.Interface.SetHidden("Minimap", false)
clean("combat queue")

---------------------------------------------------------------------------
section("slash commands and the window")
local report = PF.SelfTest.Run()
check("the in-game self test passes on the simulated client", report.failed == 0, table.concat(report.lines, " | "))
for _, cmd in ipairs({ "", "", "help", "selftest", "profile", "questitem", "center", "pick", "hide Minimap", "hide Minimap", "nonsense" }) do
    SlashCmdList.PADFORGE(cmd)
    S.Advance(0.2)
    if PadForgePicker and PadForgePicker:IsShown() then S.Tap("PAD2") end
end
clean("slash commands")
-- every page, every row, with the pad: A on buttons is skipped (they
-- reset, delete, reload), everything else is pressed
SlashCmdList.PADFORGE("")
S.Advance(0.3)
local window = PF.Config.window
check("the window opens", window ~= nil and window:IsShown())
check("...and takes the pad itself", S.RouteOf("PAD1") == "frame:PadForgeWindow", S.RouteOf("PAD1"))
local pages, rows, subpages = 0, 0, 0
local function focusRow(i)
    for _ = 1, 80 do
        if window.focus == i then return true end
        local before = window.focus
        S.Tap(window.focus < i and "PADDDOWN" or "PADDUP")
        if window.focus == before then return false end
    end
end
local function closeModal()
    for _ = 1, 4 do
        if not window.modal then return end
        S.Tap("PAD2")
        S.Advance(0.1)
    end
end
local function walk(depth)
    local i = 0
    while i < 80 do
        i = i + 1
        if not (window.items and window.items[i]) then break end
        local item = window.items[i]
        if PF.Widgets.Focusable(item) and focusRow(i) then
            rows = rows + 1
            if item.kind == "choice" or item.kind == "range" or item.kind == "toggle" then
                S.Tap("PADDRIGHT") S.Tap("PADDLEFT")
            elseif item.kind == "action" then
                S.Tap("PAD1")           -- the action list
                S.Advance(0.1)
                S.Tap("PADRSHOULDER") S.Tap("PADDDOWN")
                closeModal()
            elseif item.kind == "button" and depth < 2 then
                local before = #window.stack
                local route = S.Tap("PAD1")
                S.Advance(0.1)
                if os.getenv("PF_DEBUG") then say("A on", i, tostring(type(item.label) == "function" and item.label() or item.label), route, #window.stack, window.modal ~= nil, PF.Config.IsShown()) end
                closeModal()
                if PF.Config.IsShown() and #window.stack > before then
                    subpages = subpages + 1
                    walk(depth + 1)
                    S.Tap("PAD2")
                    S.Advance(0.1)
                end
                if not PF.Config.IsShown() then
                    -- (a button that closes the window: moving the wheel, the picker)
                    S.Advance(0.2)
                    if PadForgeRingView:IsShown() then S.Tap("PAD1") end
                    if PadForgePicker:IsShown() then S.Tap("PAD2") end
                    S.Advance(3)
                    if not PF.Config.IsShown() then PF.Config.Show() end
                end
            end
        end
    end
end
if window then
    local count = 0
    for _, b in ipairs(window.navButtons) do if b.page then count = count + 1 end end
    for n = 1, count do
        pages = pages + 1
        if not PF.Config.IsShown() then PF.Config.Show() end
        S.AsGame(function() window.navButtons[n]:Click("LeftButton", false) end)    -- a mouse click on the page's name
        S.Advance(0.1)
        walk(0)
        closeModal()
        while PF.Config.IsShown() and #window.stack > 0 do S.Tap("PAD2") end
    end
end
check("walked every page and sub-page with the pad", pages >= 8 and rows > 100 and subpages >= 5,
    pages .. " pages, " .. subpages .. " sub-pages, " .. rows .. " rows")
if os.getenv("PF_VERBOSE") then say("   " .. pages .. " pages, " .. subpages .. " sub-pages, " .. rows .. " rows") end
S.Tap("PAD2")
S.Advance(0.3)
if PF.Config.IsShown() then PF.Config.Hide() end
clean("the window")

say(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
