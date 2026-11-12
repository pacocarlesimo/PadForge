-- Every controller press PadForge takes, in one place.
--
-- Modules register a claim source (Binds.Register); Apply() asks each for
-- its claims, resolves clashes (the earlier source wins, the clash is
-- reported in the UI), and sets them as priority override bindings on one
-- owner frame, so they beat the game's own gamepad bindings and nothing is
-- ever left half-bound. A claim:
--   { key = "PAD1", click = "ButtonName" [, mouse = "LeftButton"] }  a secure button
--   { key = "PADPADDLE1", command = "GAMEPADACTIONBUTTON8" }         a game binding moved
--   world = true (default): only while the game, not a window, has the pad
--   label = "what it does" (shown in the UI)
--
-- Who has the pad is read, never hooked or called: the isUIFocused field
-- of GamepadMode.FrameControlsManager (a game window or popup is focused).
-- While one is, our world bindings are off its buttons, until it lets go.
-- In combat they stay as they were at its start (PLAYER_REGEN_DISABLED
-- comes just before the lockdown).
local _, PF = ...
local Pad = PF.Pad

local B = {}
PF.Binds = B

B.PREFIXES = { "", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "CTRL-ALT-", "CTRL-ALT-SHIFT-" }
B.FACE = { "PAD1", "PAD2", "PAD3", "PAD4" }
B.DPAD = { "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT" }
-- Presses PadForge can put actions on (besides the face buttons)
B.EXTRA = { "PADPADDLE1", "PADPADDLE2", "PADPADDLE3", "PADPADDLE4", "PADLSTICK", "PADRSTICK", "PADSOCIAL" }

local IS_FACE = { PAD1 = true, PAD2 = true, PAD3 = true, PAD4 = true }
B.IS_FACE = IS_FACE

---------------------------------------------------------------------------
-- What the game keeps
---------------------------------------------------------------------------
local GAME_OWNED = {
    PADFORWARD = "the game's main menu",
    PADBACK = "the game's interface focus",
    PADSYSTEM = "the system",
    PADLSHOULDER = "friendly targeting",
    PADRSHOULDER = "enemy targeting",
    PADLTRIGGER = "the crossbar's left bar",
    PADRTRIGGER = "the crossbar's right bar",
    PADDUP = "the crossbar (set it in the game's action bar editor)",
    PADDDOWN = "the crossbar (set it in the game's action bar editor)",
    PADDLEFT = "the crossbar (set it in the game's action bar editor)",
    PADDRIGHT = "the crossbar (set it in the game's action bar editor)",
}

-- Why a key can't be taken, or nil
function B.GameOwns(key)
    return GAME_OWNED[key]
end

-- The game's own binding on a key (not our overrides), and a readable name
function B.NativeAction(key)
    if not GetBindingAction then return nil end
    local ok, action = pcall(GetBindingAction, key, false)
    if not ok or not action or action == "" then return nil end
    return action
end

local NATIVE_NAMES = {
    JUMP = "Jump", TOGGLEAUTORUN = "Auto Run", INTERACTTARGET = "Interact",
}
function B.NativeName(action)
    if not action then return "nothing" end
    local n = action:match("^GAMEPADACTIONBUTTON(%d)$")
    if n then
        local face = B.NativeFaceRole(tonumber(n))
        if face then return face end
        return "crossbar button " .. n
    end
    return NATIVE_NAMES[action] or (_G["BINDING_NAME_" .. action]) or action
end

---------------------------------------------------------------------------
-- Forever's crossbar (Blizzard_GamepadActionBars). GAMEPADACTIONBUTTON1-8
-- are its presses: 1-4 the D-pad (left, up, right, down), 5-8 the face
-- buttons (left, top, right, bottom). The top bar's face slots are the
-- game's own (jump, interact...); holding LT / RT / both picks the left /
-- right / bottom bar, whose buttons we can /click by name.
---------------------------------------------------------------------------
local BAR_NAMES = { N = "topBar", LT = "leftBar", RT = "rightBar", LTRT = "bottomBar" }

-- The crossbar press index (1-8) a key runs, from the game's bindings
function B.CrossbarIndex(key)
    if not GetBindingKey then return nil end
    for n = 1, 8 do
        for _, k in ipairs({ GetBindingKey("GAMEPADACTIONBUTTON" .. n) }) do
            if k == key then return n end
        end
    end
end

local FACE_ROLES = { [5] = "Interact", [6] = "Context menu", [7] = "Cancel / clear target", [8] = "Jump" }
function B.NativeFaceRole(n)
    return FACE_ROLES[n]
end

-- The global name of the crossbar button for a layer and press index, or
-- nil when this client's bars aren't laid out as expected
function B.CrossbarButtonName(layer, n)
    local main = _G.GamepadMainActionBarFrame
    local bars = main and main.PageUnit and main.PageUnit.actionBars
    local bar = bars and bars[BAR_NAMES[layer]]
    if not (bar and n) then return nil end
    local group, index
    if n >= 5 then group, index = bar.Right, n - 4 else group, index = bar.Left, n end
    local button = group and group["ActionButton" .. index]
    local name = button and button.GetName and button:GetName()
    return name
end

-- Whether a face key's trigger layers can be passed through to the crossbar
-- (needed to take its plain press without losing LT/RT + that key)
function B.CanPassThrough(key)
    local n = B.CrossbarIndex(key)
    if not n then return false, "the game has no crossbar binding on " .. Pad.Name(key) end
    for _, layer in ipairs({ "LT", "RT", "LTRT" }) do
        if not B.CrossbarButtonName(layer, n) then
            return false, "this client's crossbar buttons can't be reached"
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Focus
---------------------------------------------------------------------------
local inCombat = false

-- Whether a fight is on or about to start: true from PLAYER_REGEN_DISABLED
-- (just before the lockdown, while bindings can still change) until it
-- ends. What is bound then stays bound for the whole fight.
function B.Fighting()
    return inCombat or PF.InCombat()
end

-- (no exception for combat: at its start, a game window holding the pad
-- keeps our world bindings off for the fight. Binding the game's pad
-- buttons while its window has the focus taints that window's closing:
-- "blocked from SetPreferredGamepadInteractTarget".)
-- (fields read, never a method called: calling the game's window code
-- from addon code taints it)
local function Manager()
    local manager = GamepadMode and GamepadMode.FrameControlsManager
    return type(manager) == "table" and manager or nil
end

-- Whether the player's character has the pad. A game window that is only
-- shown does not take it: the manager keeps a focusedFrame for a popup
-- that came by itself (an invite, a resurrect, a summon) and for a
-- window the player stepped out of, "so it is the first thing focused
-- when the UI is refocused", while isUIFocused stays false and the game's
-- own A still jumps. Only isUIFocused says who has the pad.
function B.InGame()
    local manager = Manager()
    return not (manager and manager.isUIFocused)
end

function B.HasFocusAPI()
    return Manager() ~= nil
end

-- The game frame that has the gamepad's focus now, or nil (read only)
function B.FocusedFrame()
    local manager = Manager()
    if manager and manager.isUIFocused then return manager.focusedFrame end
    return nil
end

-- Whether a game window or popup has the pad now: then nothing of ours
-- may take or bind the pad's buttons
function B.WindowHasPad()
    return not B.InGame()
end

-- Said when one of our windows can't open over a game window
function B.WaitForWindow()
    PF.Print("Close the game's window first: it has the controller right now.")
end

---------------------------------------------------------------------------
-- Claims
---------------------------------------------------------------------------
local sources = {}
local owner = CreateFrame("Frame", "PadForgeBindings")
B.applied = {}     -- [key] = claim
B.conflicts = {}   -- { key, winner, loser }

function B.Register(name, fn, order)
    sources[#sources + 1] = { name = name, fn = fn, order = order or 50 }
    table.sort(sources, function(a, b) return a.order < b.order end)
end

-- Every claim the sources make now (world ones only when wanted)
function B.Collect(inGame)
    local list = {}
    for _, source in ipairs(sources) do
        local ok, claims = pcall(source.fn, inGame)
        if not ok then
            PF.Report("binds:" .. source.name, claims)
        elseif type(claims) == "table" then
            for _, claim in ipairs(claims) do
                claim.source = source.name
                if claim.world == nil then claim.world = true end
                if inGame or not claim.world then list[#list + 1] = claim end
            end
        end
    end
    return list
end

function B.Apply()
    if PF.InCombat() then return end
    ClearOverrideBindings(owner)
    wipe(B.applied)
    wipe(B.conflicts)
    if not PF.db then return end
    local inGame = not B.WindowHasPad()
    for _, claim in ipairs(B.Collect(inGame)) do
        local key = claim.key
        if B.GameOwns(key) and not claim.force then
            B.conflicts[#B.conflicts + 1] = { key = key, loser = claim, why = B.GameOwns(key) }
        elseif B.applied[key] then
            B.conflicts[#B.conflicts + 1] = { key = key, winner = B.applied[key], loser = claim }
        elseif claim.reserve then
            -- (bound by its own secure driver: only kept from others here)
            B.applied[key] = claim
        else
            B.applied[key] = claim
            for _, prefix in ipairs(claim.exact and { "" } or B.PREFIXES) do
                if claim.command then
                    SetOverrideBinding(owner, true, prefix .. key, claim.command)
                elseif claim.click then
                    SetOverrideBindingClick(owner, true, prefix .. key, claim.click, claim.mouse or "LeftButton")
                end
            end
        end
    end
    PF.Fire("PF_BINDS_APPLIED", inGame)
end

function B.Release()
    if PF.InCombat() then return end
    ClearOverrideBindings(owner)
    wipe(B.applied)
end

-- The claim on a key right now (for the UI)
function B.ClaimOn(key)
    return B.applied[key]
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
PF.On("PLAYER_REGEN_DISABLED", function()
    inCombat = true
    -- (just before the lockdown: the world bindings as the focus is now)
    B.Apply()
end)

PF.On("PLAYER_REGEN_ENABLED", function()
    inCombat = false
    -- (the focus may have moved during the fight)
    C_Timer.After(0, B.Apply)
end)

PF.On("UPDATE_BINDINGS", function()
    if PF.IsReady() then PF.AfterCombat("binds", B.Apply) end
end)

local poll = CreateFrame("Frame")
local lastInGame, wait = nil, 0
poll:SetScript("OnUpdate", function(_, elapsed)
    wait = wait - elapsed
    if wait > 0 or not PF.IsReady() then return end
    wait = 0.1
    if PF.InCombat() then return end
    local now = not B.WindowHasPad()
    if now ~= lastInGame then
        lastInGame = now
        B.Apply()
    end
end)

-- Whether the game fires action buttons on the press (true) or release
function B.KeyDown()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    return not (get and get("ActionButtonUseKeyDown") == "0")
end

PF.On("CVAR_UPDATE", function(_, name)
    if name == "ActionButtonUseKeyDown" or name == "ACTION_BUTTON_USE_KEY_DOWN" or (name and name:find("GamePadEmulate")) then
        PF.EnableModules()
    end
end)
