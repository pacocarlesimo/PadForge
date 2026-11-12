-- luajit tests/run.lua  (from the repo root)
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
M.Install()

local ROOT = "./"
local NS = {}
local passed, failed = 0, 0

local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. (detail and ("  -- " .. tostring(detail)) or ""))
    end
end

-- Load in TOC order
for line in io.lines(ROOT .. "PadForge.toc") do
    line = line:gsub("\r", "")
    if line:match("%.lua$") then
        local path = ROOT .. line:gsub("\\", "/")
        local chunk = assert(loadfile(path))
        local ok, err = pcall(chunk, "PadForge", NS)
        check("load " .. line, ok, err)
    end
end

local PF = NS
M.Fire("ADDON_LOADED", "PadForge")
M.Fire("PLAYER_LOGIN")
M.Advance(0.5)
check("no errors at login", #PF.errors == 0, PF.errors[1])
check("database ready", PF.db and PF.P() ~= nil)
check("all modules running (opt-in ones off)", (function()
    for _, def in ipairs(PF.moduleOrder) do if not def.running ~= (def.defaultOff or false) then return false end end
    return true
end)())

---------------------------------------------------------------------------
-- Buttons: Smart X (Square) = Fireball while an enemy is targeted
---------------------------------------------------------------------------
local Buttons, B = PF.Buttons, PF.Binds
Buttons.SetAction("PAD3", "N", "spell:133")
M.Advance(0.2)
check("PAD3 set to smart by picking an action", Buttons.Entry("PAD3").mode == "smart")
check("PAD3 status ready", Buttons.status.PAD3 == "ready", Buttons.status.PAD3)
check("PAD3 reserved for smart driver", B.applied.PAD3 and B.applied.PAD3.reserve)

M.target.harm = false
M.UpdateDrivers()
check("smart off without enemy: native press", M.Press("PAD3", true) == "native")
M.target.harm = true
M.UpdateDrivers()
local r = M.Press("PAD3", true)
check("smart on with enemy: casts Fireball", type(r) == "table" and r.type == "spell" and r.spell == "Fireball", r and r.type)
check("release edge does nothing (key-down mode)", M.Press("PAD3", false) == nil)
M.Hold("PADLTRIGGER", true)
r = M.Press("PAD3", true)
check("LT + Square passes to the crossbar's left bar", type(r) == "table" and r.macrotext == "/click GP_leftBar_R1 LeftButton true", r and r.macrotext)
M.Hold("PADLTRIGGER", false)
M.Hold("PADLTRIGGER", true) M.Hold("PADRTRIGGER", true)
r = M.Press("PAD3", true)
check("LT+RT + Square passes to the bottom bar", type(r) == "table" and r.macrotext and r.macrotext:find("GP_bottomBar_R1"), r and r.macrotext)
M.Hold("PADLTRIGGER", false) M.Hold("PADRTRIGGER", false)

-- Combat: the driver switches with no binding change from insecure code
M.combat = true
M.Fire("PLAYER_REGEN_DISABLED")
M.target.harm = false
M.UpdateDrivers()
check("in combat, target lost: native again", M.Press("PAD3", true) == "native")
M.target.harm = true
M.UpdateDrivers()
r = M.Press("PAD3", true)
check("in combat, enemy again: Fireball", type(r) == "table" and r.spell == "Fireball")
-- A change asked for in combat waits
Buttons.SetAction("PAD4", "N", "spell:116")
check("no error from a change in combat", #PF.errors == 0, PF.errors[1])
M.combat = false
M.Fire("PLAYER_REGEN_ENABLED")
M.Advance(0.3)
check("queued change applied after combat", Buttons.status.PAD4 == "ready", Buttons.status.PAD4)

-- Action mode on A, Jump moved to Paddle 1
Buttons.SetMode("PAD1", "action")
Buttons.SetAction("PAD1", "N", "spell:10")
Buttons.SetRelocation("PAD1", "PADPADDLE1")
M.Advance(0.2)
r = M.Press("PAD1", true)
check("A casts Blizzard (always)", type(r) == "table" and r.spell == "Blizzard")
check("Jump moved to Paddle 1", M.Press("PADPADDLE1", true) == "command:GAMEPADACTIONBUTTON8")
check("A has no 'lost' warning once Jump is moved", Buttons.Loses("PAD1") == nil)

-- Layers on a paddle
Buttons.SetAction("PADPADDLE2", "N", "item:858")
Buttons.SetAction("PADPADDLE2", "RT", "questitem")
M.Advance(0.2)
r = M.Press("PADPADDLE2", true)
check("Paddle 2 uses the potion", type(r) == "table" and r.type == "item" and r.item == "item:858", r and r.type)
M.Hold("PADRTRIGGER", true)
r = M.Press("PADPADDLE2", true)
check("RT + Paddle 2 uses the quest item", type(r) == "table" and r.macrotext == "/click PadForgeQuestItemButton LeftButton true")
M.Hold("PADRTRIGGER", false)
check("quest item button holds the quest book", _G.PadForgeQuestItemButton:GetAttribute("item") == "item:7500", _G.PadForgeQuestItemButton:GetAttribute("item"))
M.Hold("PADLTRIGGER", true)
check("LT + Paddle 2 (unset) does nothing", M.Press("PADPADDLE2", true) == nil)
M.Hold("PADLTRIGGER", false)

-- A window takes the pad: world bindings step aside
M.inGame = false
M.Advance(0.3)
check("window focus: A back to the game", M.Press("PAD1", true) == "native")
check("window focus: smart driver off", (function()
    M.target.harm = true
    M.UpdateDrivers()
    return M.Press("PAD3", true) == "native"
end)())
M.inGame = true
M.Advance(0.3)
check("focus back: A is ours again", type(M.Press("PAD1", true)) == "table")

-- Game-owned keys are refused
Buttons.SetAction("PADLSHOULDER", "N", "spell:133")
M.Advance(0.2)
check("LB can't be taken", B.applied.PADLSHOULDER == nil)

---------------------------------------------------------------------------
-- Wheels
---------------------------------------------------------------------------
local Wheels = PF.Wheels
local ring = _G.PadForgeRing
check("no wheel on R3 by default (it's the game's ping)", M.Binding("PADRSTICK") == nil)
Wheels.UseDefaultLayout()
M.Advance(0.5)
check("wheel trigger bound on R3", M.Binding("PADRSTICK") and M.Binding("PADRSTICK").target == "PadForgeWheelTrigger")
check("Items wheel has slots", (ring:GetAttribute("pf-w1-n") or 0) > 0, ring:GetAttribute("pf-w1-n"))
check("Markers wheel has 9 slots", ring:GetAttribute("pf-w2-n") == 9, ring:GetAttribute("pf-w2-n"))
check("Items wheel: quest item first", Wheels.Data(1).slots[1].action == "item:7500", Wheels.Data(1).slots[1].action)

-- Hold-aim-release with LT: markers wheel, aim at slot 1 (top: skull)
M.Hold("PADLTRIGGER", true)
M.Press("PADRSTICK", true)
check("LT + R3 opens the markers wheel", ring:IsShown() and ring:GetAttribute("pf-active") == 2)
check("A is the wheel's while up", M.Binding("PAD1").target == "PadForgeWheelUse")
M.SetStick(0, 1)
r = M.Press("PADRSTICK", false)
check("release while aiming up uses the top slot (Skull)", type(r) == "table" and r.macrotext == "/tm 8", r and r.macrotext)
check("wheel closed after use", not ring:IsShown())
check("A back to its owner after the wheel", M.Binding("PAD1").target ~= "PadForgeWheelUse")
M.SetStick(0, 0)
M.Hold("PADLTRIGGER", false)

-- Tap R3, point right, A
M.Press("PADRSTICK", true)
M.Press("PADRSTICK", false)
check("a tap leaves the wheel open", ring:IsShown())
M.SetStick(1, 0)
r = M.Press("PAD1", true)
check("A uses the slot the stick points at", type(r) == "table" and r.type == "item", r and r.type)
check("wheel closed after A", not ring:IsShown())
M.SetStick(0, 0)

-- A stick already pushed when the wheel opens (camera turning): its release doesn't fire
M.SetStick(0.9, 0)
M.Press("PADRSTICK", true)
r = M.Press("PADRSTICK", false)
check("R3 clicked while the stick turns the camera: nothing used", r == nil and ring:IsShown())
M.Press("PAD2", true)
check("B closes the wheel", not ring:IsShown())
M.SetStick(0, 0)

-- D-pad steps, A uses
M.Press("PADRSTICK", true) M.Press("PADRSTICK", false)
M.Press("PADDDOWN", true)
r = M.Press("PAD1", true)
check("the D-pad picks a slot, A uses it", type(r) == "table", r)

-- No game setting changed by the wheels, ever
local before = M.cvars.GamePadStickAxisButtons
M.combat = true
M.Fire("PLAYER_REGEN_DISABLED")
M.Hold("PADRTRIGGER", true)
M.Press("PADRSTICK", true)
check("combat: RT + R3 opens the chat wheel", ring:IsShown() and ring:GetAttribute("pf-active") == 3)
M.SetStick(0, 1)
r = M.Press("PADRSTICK", false)
check("combat: release uses a chat line", type(r) == "table" and r.macrotext and r.macrotext:find("^/s "), r and r.macrotext)
M.Hold("PADRTRIGGER", false)
M.SetStick(0, 0)
M.combat = false
M.Fire("PLAYER_REGEN_ENABLED")
M.Advance(0.5)
check("the stick-keys setting was never touched", M.cvars.GamePadStickAxisButtons == before)

-- Custom wheel
local idx = Wheels.Add("custom", "Mine")
Wheels.SetSlot(idx, 1, "spell:1459")
Wheels.SetChord("LB", idx)
M.Advance(0.5)
check("custom wheel built", ring:GetAttribute("pf-w" .. idx .. "-n") == 1)
M.Hold("PADLSHOULDER", true)
M.Press("PADRSTICK", true)
check("LB + R3 opens the custom wheel", ring:IsShown() and ring:GetAttribute("pf-active") == idx)
M.SetStick(0, 1)
r = M.Press("PADRSTICK", false)
check("custom slot casts Arcane Intellect", type(r) == "table" and r.spell == "Arcane Intellect")
M.Hold("PADLSHOULDER", false)
M.SetStick(0, 0)

---------------------------------------------------------------------------
-- Prompts
---------------------------------------------------------------------------
local popup = _G.StaticPopup1
popup.which = "PARTY_INVITE"
popup:Show()
M.Advance(0.1)
check("no answer during the grace time", M.Binding("PAD1").target ~= "PadForgePromptYes")
M.Advance(0.6)
check("A answers the invite", M.Binding("PAD1") and M.Binding("PAD1").target == "PadForgePromptYes", M.Binding("PAD1") and M.Binding("PAD1").target)
r = M.Press("PAD1", true)
check("yes clicks the popup's own button", type(r) == "table" and r.macrotext == "/click StaticPopup1Button1", r and r.macrotext)
r = M.Press("PAD2", true)
check("no clicks button 2", type(r) == "table" and r.macrotext == "/click StaticPopup1Button2")
check("the hint shows", _G.PadForgePromptHint:IsShown())
popup:Hide()
M.Advance(0.4)
check("popup gone: A is the buttons module's again", M.Binding("PAD1") and M.Binding("PAD1").target == "PadForgeKey_PAD1", M.Binding("PAD1") and M.Binding("PAD1").target)
check("hint hidden", not _G.PadForgePromptHint:IsShown())

-- A popup with the game's window holding the pad: left alone
-- (focused, as the game's manager has it: isUIFocused and a focusedFrame)
M.inGame = false
_G.GamepadMode.FrameControlsManager.focusedFrame = _G.SomeBag or {}
popup.which = "RESURRECT"
popup:Show()
M.Advance(1)
check("focused window: no prompt binding (nor any of ours)", M.Binding("PAD1") == nil)
popup:Hide()
M.inGame = true
_G.GamepadMode.FrameControlsManager.focusedFrame = nil
M.Advance(0.5)

-- A popup that came by itself (an invite): the game's manager keeps it as
-- its focusedFrame without focusing the UI. It doesn't have the pad, so
-- this is exactly when PadForge answers, and its other bindings stay.
_G.GamepadMode.FrameControlsManager.focusedFrame = popup
popup.which = "PARTY_INVITE"
popup:Show()
M.Advance(1)
check("unfocused popup (focusedFrame set, UI not focused): A answers it",
    M.Binding("PAD1") and M.Binding("PAD1").target == "PadForgePromptYes", M.Binding("PAD1") and M.Binding("PAD1").target)
check("...and the game still counts as having no window on the pad", PF.Binds.InGame() and not PF.Binds.WindowHasPad())
check("...and world bindings stay", M.Binding("PADPADDLE1") ~= nil)
popup:Hide()
_G.GamepadMode.FrameControlsManager.focusedFrame = nil
M.Advance(0.5)

-- Release spirit waits longer and has no "no"
popup.which = "DEATH"
popup:Show()
M.Advance(0.7)
check("release: still waiting at 0.7 s", M.Binding("PAD1").target ~= "PadForgePromptYes")
M.Advance(0.8)
check("release: A after 1.2 s", M.Binding("PAD1").target == "PadForgePromptYes")
check("release: B untouched", M.Binding("PAD2") == nil or M.Binding("PAD2").target ~= "PadForgePromptNo")
popup:Hide()
M.Advance(0.5)

---------------------------------------------------------------------------
-- Profiles, export, import, snapshots
---------------------------------------------------------------------------
local DB = PF.DB
local str = DB.Export()
check("export string", type(str) == "string" and str:find("^!PF1!"), str and str:sub(1, 12))
local info, why = DB.ReadImport(str)
check("import reads back", info ~= nil, why)
check("import of own profile: no changes", info and #info.changes == 0, info and #info.changes)
local name = DB.ApplyImport(info, "new")
check("import made a new active profile", DB.ActiveName() == name and name ~= "Default", name)
check("imported profile has the smart Square", PF.P().buttons.keys.PAD3.layers.N == "spell:133")
DB.SetActive("Default")
local partial = DB.Export(nil, { wheels = true })
local pinfo = DB.ReadImport(partial)
check("partial export holds only wheels", pinfo and #pinfo.sections == 1 and pinfo.sections[1] == "wheels")
check("garbage import refused", DB.ReadImport("hello") == nil)
local hostile = PF.Util.Encode({ format = 1, kind = "profile", data = { buttons = { keys = { PAD1 = { mode = "evil", layers = { N = 5, Q = "x" } } }, relocate = { PAD1 = "PADFORWARD" } }, junk = { a = 1 } } })
local hinfo = DB.ReadImport(hostile)
check("hostile import cleaned", hinfo and hinfo.data.buttons.keys.PAD1.mode == "game" and hinfo.data.buttons.keys.PAD1.layers.N == nil
    and hinfo.data.buttons.relocate.PAD1 == nil and hinfo.data.junk == nil)
local count = #PF.db.snapshots
DB.Delete(name)
check("delete keeps a snapshot", #PF.db.snapshots == count + 1)
check("restore brings it back", DB.Restore(1) and DB.Exists(name))
local newer = PF.Util.Encode({ format = 9, kind = "profile", data = { wheels = {} } })
check("newer format refused politely", select(2, DB.ReadImport(newer)):find("newer"))

---------------------------------------------------------------------------
-- UI: every page builds, every row renders, the pad drives it
---------------------------------------------------------------------------
PF.Config.Show("start")
local f = PF.Config.window
check("window open", f and f:IsShown())
local pageCount = 0
for i = 1, 9 do
    pageCount = pageCount + 1
    -- walk every row; change choices; render
    for _ = 1, #f.items + 2 do
        PF.Widgets.Press(f, "PADDDOWN")
        local item = f.items[f.focus]
        if item and (item.kind == "choice" or item.kind == "range") then
            PF.Widgets.Press(f, "PADDRIGHT")
            PF.Widgets.Press(f, "PADDLEFT")
        end
    end
    PF.Widgets.Press(f, "PADRSHOULDER")
end
check("all pages render with no error", #PF.errors == 0, PF.errors[1])
-- Sub-pages: Buttons > A
PF.Config.Show("buttons")
f.focus = 2
PF.Widgets.Press(f, "PAD1")
check("pushed the A page", #f.stack == 1)
PF.Widgets.Press(f, "PAD2")
check("B goes back", #f.stack == 0 and f:IsShown())
-- Wheels sub-pages
PF.Config.Show("wheels")
for i, item in ipairs(f.items) do
    if item.kind == "button" and item.verb == "Edit" then
        f.focus = i
        PF.Widgets.Press(f, "PAD1")
        PF.Widgets.Press(f, "PAD2")
    end
end
check("wheel pages render", #PF.errors == 0, PF.errors[1])
-- Picker
PF.Picker.Open("Test", nil, function(a) NS._picked = a end)
for _ = 1, 10 do PF.Widgets.Press(f, "PADRSHOULDER") end
PF.Widgets.Press(f, "PAD1")
check("picker picks", NS._picked ~= nil, NS._picked)
-- Capture a press
local captured
PF.Widgets.Capture(f, { set = function(s) captured = s end, keys = function() return { "PADPADDLE3" } end })
PF.Widgets.Press(f, "PAD1")
check("capture refuses a key not allowed", captured == nil and f.modal ~= nil)
M.Hold("PADRTRIGGER", true)
PF.Widgets.Press(f, "PADPADDLE3")
M.Hold("PADRTRIGGER", false)
check("capture records RT + Paddle 3", captured == "RT:PADPADDLE3", captured)
-- Combat closes the window
M.combat = true
M.Fire("PLAYER_REGEN_DISABLED")
check("combat closes the window", not f:IsShown())
M.combat = false
M.Fire("PLAYER_REGEN_ENABLED")
M.Advance(0.3)

---------------------------------------------------------------------------
-- Compatibility and safe mode
---------------------------------------------------------------------------
PF.safeMode = true
PF.EnableModules()
M.Advance(0.2)
check("safe mode: nothing bound", M.Binding("PAD1") == nil and M.Binding("PADRSTICK") == nil)
PF.safeMode = false
PF.EnableModules()
M.Advance(0.2)
check("safe mode off: bound again", M.Binding("PADRSTICK") ~= nil)

-- Movement: written only when the player changes it
PF.P().movement.cvars.GamePadCameraYawSpeed = "2"
PF.EnableModules()
M.Fire("PF_PROFILE_CHANGED")
M.Advance(0.5)
check("a profile's setting is not written by itself", M.cvars.GamePadCameraYawSpeed == "1")
check("the page says it differs", PF.Movement.Differs() == 1)
PF.Movement.Apply()
check("written when the player asks", M.cvars.GamePadCameraYawSpeed == "2")
PF.Movement.SetValue("GamePadRunThreshold", 0.3)
check("cvar applied", M.cvars.GamePadRunThreshold == "0.3", M.cvars.GamePadRunThreshold)
PF.Movement.SetValue("GamePadRunThreshold", nil)
M.Advance(0.1)
check("cvar back to default", M.cvars.GamePadRunThreshold == "0.5", M.cvars.GamePadRunThreshold)

-- Interface hide by name
_G.GamepadSwingTimerFrame = M.CreateFrame("Frame", "GamepadSwingTimerFrame")
local found = PF.Interface.Discover()
check("swing timer discovered", #found >= 1 and found[1].name == "GamepadSwingTimerFrame")
PF.Interface.SetHidden("GamepadSwingTimerFrame", true)
check("swing timer faded (not touched)", PF.IsFaded(_G.GamepadSwingTimerFrame) and _G.GamepadSwingTimerFrame:IsShown())

-- Quest item icon: hidden until a button uses it
PF.P().buttons.keys.PADPADDLE2 = nil
PF.RefreshModule("buttons")
M.Advance(0.3)
PF.QuestItem.RefreshIcon()
check("quest icon hidden with no button", not _G.PadForgeQuestItemIcon:IsShown())
PF.Buttons.SetAction("PADPADDLE3", "N", "questitem")
M.Advance(0.3)
check("quest icon shown once bound", _G.PadForgeQuestItemIcon:IsShown())


-- Wheel look & position
local view = _G.PadForgeRingView
local look = PF.P().wheels.look
check("wheel look defaults: right of centre, see-through", look.theme == "dark" and look.radius == 120 and look.x == 480 and look.opacity == 0.45)
Wheels.StartMove()
check("move mode: wheel shown, mouse on, window closed", view:IsShown() and view:IsMouseEnabled() and not PF.Config.IsShown())
view._scripts.OnGamePadButtonDown(view, "PADDRIGHT")
view._scripts.OnGamePadButtonDown(view, "PADDRIGHT")
view._scripts.OnGamePadButtonDown(view, "PADDUP")
check("D-pad nudges the wheel", look.x == 500 and look.y == -50, look.x .. "," .. look.y)
view._scripts.OnGamePadButtonDown(view, "PAD4")
check("Y puts it back to its default place", look.x == 480 and look.y == -60)
view._scripts.OnDragStop(view)
check("drag stop saves a position", type(look.x) == "number")
view._scripts.OnGamePadButtonDown(view, "PAD1")
check("A ends moving and reopens the settings", not view:IsShown() and not view:IsMouseEnabled() and PF.Config.IsShown())
look.theme = "fel"
look.glow = "violet"
look.opacity = 0.5
Wheels.ApplyLook()
check("background from the theme", view.bg._color[2] == 0.10 and view.bg._color[4] == 0.5, view.bg._color[2])
check("highlight colour picked", view.slots[1].glow._color[1] == 0.7)
look.radius = 160 look.icon = 60
Wheels.ApplyLook()
check("radius and icon size", view:GetWidth() and view.slots[1] ~= nil)
local bad = Wheels.ValidateLook({ theme = "nope", bg = "x", opacity = 9, radius = 5 })
check("bad look values cleaned", bad.theme == "dark" and bad.bg == "theme" and bad.opacity == 1 and bad.radius == 80)
Wheels.StartMove()
M.combat = true
M.Fire("PLAYER_REGEN_DISABLED")
check("combat ends moving", not view:IsShown())
M.combat = false
M.Fire("PLAYER_REGEN_ENABLED")
M.Advance(0.3)
PF.Config.Show("wheels")
for i, item in ipairs(f.items) do
    if item.kind == "button" and item.label == "Look & position" then
        f.focus = i
        PF.Widgets.Press(f, "PAD1")
    end
end
check("look page opens", #f.stack == 1)
for _ = 1, 30 do
    PF.Widgets.Press(f, "PADDDOWN")
    local item = f.items[f.focus]
    if item and (item.kind == "choice" or item.kind == "range") then PF.Widgets.Press(f, "PADDRIGHT") end
end
check("look page works with the pad", #PF.errors == 0, PF.errors[1])
PF.Config.Hide()

-- Minimap button
local mb = _G.PadForgeMinimapButton
check("minimap button exists and shows", mb and mb:IsShown())
PF.Config.Hide()
mb._scripts.OnClick(mb, "LeftButton")
check("click opens PadForge", PF.Config.IsShown())
mb._scripts.OnClick(mb, "LeftButton")
check("click again closes it", not PF.Config.IsShown())
M.cursor = { 900, 400 }   -- right of the minimap centre (500, 400)
mb._scripts.OnDragStart(mb)
mb._scripts.OnUpdate(mb, 0.1)
mb._scripts.OnDragStop(mb)
check("drag sets the angle", PF.db.global.minimap.angle == 0, PF.db.global.minimap.angle)
M.cursor = { 500, 800 }
mb._scripts.OnDragStart(mb) mb._scripts.OnUpdate(mb, 0.1) mb._scripts.OnDragStop(mb)
check("drag above: 90 degrees", PF.db.global.minimap.angle == 90, PF.db.global.minimap.angle)
mb._scripts.OnEnter(mb)
PF.MinimapButton.SetShown(false)
check("hidden from settings", not mb:IsShown())
PF.MinimapButton.SetShown(true)
check("shown again", mb:IsShown())

-- Game macros (made with /macro) on a button
PF.Config.Show("buttons")
local got
PF.Picker.Open("Paddle 4", nil, function(a) got = a end)
PF.Widgets.Press(f, "PADRSHOULDER")   -- (second tab: Macros)
PF.Widgets.Press(f, "PAD1")
check("a game macro picked from the Macros tab", got == "macro:Pull", got)
PF.Buttons.SetAction("PADPADDLE4", "N", got)
M.Advance(0.3)
r = M.Press("PADPADDLE4", true)
check("Paddle 4 runs the game macro", type(r) == "table" and r.type == "macro" and r.macro == "Pull", r and r.type)
check("free macro text never runs (import safety)", PF.Actions.Secure("cmd:/run DoSomething()") == nil)
PF.Buttons.SetAction("PADPADDLE3", "N", "cmd:/run DoSomething()")
M.Advance(0.3)
check("a button holding free text does nothing", M.Press("PADPADDLE3", true) ~= "table" and PF.Buttons.status.PADPADDLE3 == nil)
PF.Config.Hide()


-- Secret values (the client hides combat numbers): nothing of ours errors
local errorsNow = #PF.errors
M.Fire("UNIT_COMBAT", "player", "WOUND", "", M.Secret(500), 1)
check("a secret damage amount: no error", #PF.errors == errorsNow, PF.errors[1])
M.secretHealth = true
M.Advance(1.6)
check("secret health: the low-health check doesn't error", #PF.errors == errorsNow, PF.errors[1])
M.Fire("CHAT_MSG_LOOT", M.Secret("You receive loot: x"))
check("a secret chat line: no error", #PF.errors == errorsNow, PF.errors[1])
M.Fire("UNIT_THREAT_SITUATION_UPDATE", M.Secret("player"))
check("a secret unit token: no error", #PF.errors == errorsNow, PF.errors[1])
check("secret health is simply unknown", PF.Group.Health("player") == nil)
M.secretHealth = false

-- Group targeting
M.units.party1 = { hp = 80, max = 100 }
M.units.party2 = { hp = 0, max = 100, dead = true }
M.units.party3 = { hp = 30, max = 100 }
M.Fire("GROUP_ROSTER_UPDATE")
M.Advance(0.2)
local cyc = _G.PadForgeGroupCycle
local seq = {}
for _ = 1, 5 do
    local rec = M.Click(cyc, "LeftButton", true)
    seq[#seq + 1] = rec and rec.unit or "-"
end
check("next member: skips the dead and the absent", table.concat(seq, ",") == "player,party1,party3,player,party1", table.concat(seq, ","))
local rec = M.Click(cyc, "RightButton", true)
check("previous member", rec and rec.unit == "player", rec and rec.unit)
check("the lowest alive is party3", PF.Group.Lowest({ "player", "party1", "party2", "party3" }) == "party3")
M.secretHealth = true
check("with secret health no LOWEST is guessed", PF.Group.Lowest({ "player", "party1", "party3" }) == nil)
PF.Wheels.UseDefaultLayout()
M.Advance(0.5)
M.Hold("PADLTRIGGER", true) M.Hold("PADRTRIGGER", true)
M.Press("PADRSTICK", true)
M.Hold("PADLTRIGGER", false) M.Hold("PADRTRIGGER", false)
local e0 = #PF.errors
M.Advance(0.5)
check("the Group wheel open with secret health: no error", #PF.errors == e0, PF.errors[1])
M.Press("PAD2", true)
M.secretHealth = false
PF.Buttons.SetAction("PADPADDLE1", "N", "groupnext")
M.Advance(0.3)
r = M.Press("PADPADDLE1", true)
check("a button steps the group", type(r) == "table" and r.macrotext == "/click PadForgeGroupCycle LeftButton true")

-- Profile per place
local dungeonProfile = PF.DB.New("Dungeon")
PF.DB.SetContextProfile("dungeon", dungeonProfile)
check("in the world: the usual profile", PF.DB.ActiveName() ~= dungeonProfile)
M.instance = "party"
M.Fire("PLAYER_ENTERING_WORLD")
check("entering a dungeon switches profile", PF.DB.ActiveName() == dungeonProfile, PF.DB.ActiveName())
M.instance = "none"
M.Fire("PLAYER_ENTERING_WORLD")
check("leaving it switches back", PF.DB.ActiveName() ~= dungeonProfile)
PF.DB.SetContextProfile("dungeon", nil)
M.Advance(0.5)

-- Quick setup: known spells only
local S = PF.Setup
local names = {}
for _, e in ipairs(S.Known()) do names[#names + 1] = e.label end
check("only known class spells suggested", table.concat(names, ",") == "Fireball,Frostbolt,Arcane Intellect", table.concat(names, ","))
check("Blink (not learned) is not offered", not table.concat(names, ","):find("Blink"))
S.Apply({ wheels = true, spells = true, smartX = true })
M.Advance(0.5)
local idx2
for i, w in ipairs(PF.P().wheels.list) do if w.auto then idx2 = i end end
check("a Spells wheel made on LB", idx2 and PF.P().wheels.chords.LB == idx2 and #PF.P().wheels.list[idx2].slots == 3)
check("Smart X is the main attack", PF.P().buttons.keys.PAD3.layers.N == "spell:133" and PF.P().buttons.keys.PAD3.mode == "smart")
check("setup marked done", S.Done())
table.insert(M.book, 2136)
M.Fire("SPELLS_CHANGED")
M.Advance(1.5)
check("a newly learned spell joins the Spells wheel", #PF.P().wheels.list[idx2].slots == 4 and PF.P().wheels.list[idx2].slots[4] == "spell:2136")
M.Fire("SPELLS_CHANGED")
M.Advance(1.5)
check("but only once", #PF.P().wheels.list[idx2].slots == 4)
PF.P().setup.done = false
PF.Config.setupOffered = nil
PF.Config.Show()
check("first open shows the quick setup", f.items[1] and #f.items > 3 and PF.Config.window and PF.errors[1] == nil)
PF.Config.Hide()

-- Mounts
local mw
for i, w in ipairs(PF.P().wheels.list) do if w.source == "mounts" then mw = w end end
check("a Mounts wheel is built in", mw ~= nil)
local mc = PF.Wheels.Contents(mw)
check("companion mounts in it", mc[1] == "spell:999", mc[1])

check("no frame of ours ever takes the keyboard", #M.keyboardTaken == 0, table.concat(M.keyboardTaken, ","))

-- The rules (static): nothing PadForge may not do on WoW Forever's gamepad UI
local BANNED = {
    { "StaticPopup_FindVisible", "calls the game's Lua (popups are read, not asked)" },
    { "InputDeviceIconSetManager", "calls the game's Lua" },
    { "IsOnlyCoreBindingSetActive", "calls the game's binding manager" },
    { "GamepadSharedUtility", "the game's binding manager" },
    { "UISpecialFrames", "a name of ours in the game's Escape list taints its menu" },
    { "RegisterAddOnCategory", "an entry of ours in the game's Settings lists" },
    { "RegisterCanvasLayoutCategory", "an entry of ours in the game's Settings lists" },
    { "hooksecurefunc", "hooks the game's functions" },
    { "AddManagedFrame", "lays our frames out in the game's columns" },
    { "EventRegistry", "the game's shared event frame" },
    { "ShowUIPanel", "the game's window code" },
    { "HideUIPanel", "the game's window code" },
    { "SetPropagateKeyboardInput", "keyboard capture" },
    { "EnableKeyboard%(true", "keyboard capture" },
    { "GamePadStickAxisButtons\", ", "changing a gamepad setting by itself" },
    { "ReloadUI", "reloads" },
    { "geterrorhandler", "runs the game's error code under our name (taint)" },
    { "FrameControlsManager:", "calling the game's window manager (read its fields only)" },
}
local files = {}
for line in io.lines(ROOT .. "PadForge.toc") do
    line = line:gsub("\r", "")
    if line:match("%.lua$") then files[#files + 1] = ROOT .. line:gsub("\\", "/") end
end
local found = {}
for _, path in ipairs(files) do
    local n = 0
    for line in io.lines(path) do
        n = n + 1
        local code = line:gsub("%-%-.*$", "")
        for _, b in ipairs(BANNED) do
            if code:find(b[1]) then found[#found + 1] = path .. ":" .. n .. " " .. b[1] .. " (" .. b[2] .. ")" end
        end
        -- game settings: only on the player's own action, in these two places
        if code:find("SetCVar") and not path:find("Movement.lua") then
            found[#found + 1] = path .. ":" .. n .. " SetCVar outside the player's own actions"
        end
        -- no frame of ours made a child of the game's
        if code:find("CreateFrame%(.-,%s*Minimap%s*[,%)]") then
            found[#found + 1] = path .. ":" .. n .. " a child of the minimap"
        end
    end
end
check("nothing forbidden in the code", #found == 0, table.concat(found, "\n  "))

check("no errors overall", #PF.errors == 0, PF.errors[1])
-- SetPreferredGamepadInteractTarget: nothing of ours on the pad while a game window has it
local GM = _G.GamepadMode.FrameControlsManager
M.inGame = false
GM.focusedFrame = { name = "LootFrame" }
M.Advance(0.3)
check("a game window has the pad: no world bindings", M.Binding("PAD1") == nil and M.Binding("PADPADDLE1") == nil)
M.combat = true
M.Fire("PLAYER_REGEN_DISABLED")
check("combat starting with it open: still none", M.Binding("PAD1") == nil)
M.combat = false
M.Fire("PLAYER_REGEN_ENABLED")
M.Advance(0.3)
GM.focusedFrame = _G.StaticPopup1
_G.StaticPopup1.which = "PARTY_INVITE"
_G.StaticPopup1:Show()
M.Advance(1)
check("a popup holding the pad: we don't bind A / B", M.Binding("PAD1") == nil or M.Binding("PAD1").target ~= "PadForgePromptYes")
_G.StaticPopup1:Hide()
GM.focusedFrame = { name = "Bags" }
M.Advance(0.3)
PF.Config.Show("start")
check("our window won't open over a game window", not PF.Config.IsShown())
M.inGame = true
GM.focusedFrame = nil
M.Advance(0.3)
PF.Config.Show("start")
check("it opens once the game window is closed", PF.Config.IsShown())
M.inGame = false
GM.focusedFrame = { name = "Bags" }
M.Advance(0.3)
check("and steps aside if a game window takes the pad", not PF.Config.IsShown())
M.inGame = true
GM.focusedFrame = nil
M.Advance(0.3)
check("world bindings back when the window closes", M.Binding("PAD1") ~= nil)

-- 1.0.0: vibration and the debug log are gone, and old saves are cleaned
check("no vibration module", PF.Vibration == nil)
local old = { schema = 5, log = { { why = "x" } }, profiles = { P = { vibration = { strength = 1 }, modules = { vibration = true }, movement = { cvars = { GamePadVibrationStrength = 1 } } } } }
PF.DB.Migrate(old)
check("old saves lose vibration and the log", old.schema == 6 and old.log == nil and old.profiles.P.vibration == nil
    and old.profiles.P.modules.vibration == nil and old.profiles.P.movement.cvars.GamePadVibrationStrength == nil)
check("nothing of ours in the game's Escape list", _G.UISpecialFrames == nil or #_G.UISpecialFrames == 0)

for _, l in ipairs(M.log) do if l:find("ERROR") and not l:find("blocked") then print(l) end end
print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
