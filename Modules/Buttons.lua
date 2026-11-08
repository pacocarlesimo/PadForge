-- Buttons: the fix for the most asked-for thing on the WoW Forever forums,
-- "let us rebind A / B / X / Y".
--
-- Face buttons (plain press, no trigger held) can be:
--   game    the game's own (Jump, Cancel, Interact, Context menu)
--   action  always your action
--   smart   your action only while a condition holds (an enemy targeted,
--           in combat...), the game's own the rest of the time: a secure
--           state driver binds and unbinds it, so it switches in combat too
-- With a trigger held a face button stays the crossbar's (LT/RT + A...):
-- our button clicks the game's crossbar button of that bar.
--
-- Extra presses (paddles, L3, R3, Share) take an action per trigger layer
-- (plain, LT, RT, LT+RT).
--
-- Relocations move a key's game binding (Jump, Auto Run...) onto another
-- key, so freeing A doesn't mean losing Jump.
local _, PF = ...
local A, B, Pad = PF.Actions, PF.Binds, PF.Pad

local M = PF.NewModule("buttons", {
    title = "Buttons",
    desc = "Free A/B/X/Y, actions on paddles and stick clicks, move the game's own actions.",
    order = 10,
    compat = { ConsolePort = "ConsolePort", EasyController = "Easy Controller", EasyControllerForever = "Easy Controller" },
})
PF.Buttons = M

M.CONDITIONS = {
    enemy = { label = "Enemy targeted", macro = "[harm,nodead]" },
    combat = { label = "In combat", macro = "[combat]" },
    either = { label = "Enemy targeted or in combat", macro = "[harm,nodead][combat]" },
    fight = { label = "In combat with an enemy targeted", macro = "[combat,harm,nodead]" },
}
M.CONDITION_ORDER = { "enemy", "combat", "either", "fight" }
M.MODES = { "game", "action", "smart" }
M.MODE_LABELS = { game = "Game's own", action = "My action", smart = "Smart" }

local function Validate(t)
    t.keys = type(t.keys) == "table" and t.keys or {}
    t.relocate = type(t.relocate) == "table" and t.relocate or {}
    for key, e in pairs(t.keys) do
        if type(e) ~= "table" or type(key) ~= "string" then
            t.keys[key] = nil
        else
            if e.mode ~= "action" and e.mode ~= "smart" then e.mode = "game" end
            if not M.CONDITIONS[e.cond] then e.cond = "enemy" end
            e.layers = type(e.layers) == "table" and e.layers or {}
            for layer, action in pairs(e.layers) do
                if type(action) ~= "string" or not Pad.LAYER_LABEL[layer] then e.layers[layer] = nil end
            end
        end
    end
    for from, to in pairs(t.relocate) do
        if type(from) ~= "string" or type(to) ~= "string" or B.GameOwns(to) then t.relocate[from] = nil end
    end
    return t
end

PF.DB.RegisterDefaults("buttons", { keys = {}, relocate = {} }, Validate)

local function Section()
    local p = PF.P()
    return p and p.buttons
end

function M.Entry(key, create)
    local s = Section()
    if not s then return nil end
    local e = s.keys[key]
    if not e and create then
        e = { mode = B.IS_FACE[key] and "game" or "action", cond = "enemy", layers = {} }
        s.keys[key] = e
    end
    return e
end

-- The keys this module manages, in display order
function M.Keys()
    local list = {}
    for _, k in ipairs(B.FACE) do list[#list + 1] = k end
    for _, k in ipairs(B.EXTRA) do list[#list + 1] = k end
    return list
end

-- Layers a key takes actions on: a face button only its plain press
function M.LayersOf(key)
    if B.IS_FACE[key] then return { "N" } end
    return Pad.LAYERS
end

---------------------------------------------------------------------------
-- Secure dispatchers: one per key, picking the layer from the triggers held
---------------------------------------------------------------------------
local dispatchers, drivers = {}, {}

local CLEAR = [[
    self:SetAttribute("spell", nil)
    self:SetAttribute("item", nil)
    self:SetAttribute("macro", nil)
    self:SetAttribute("macrotext", nil)
    self:SetAttribute("unit", nil)
]]

local DISPATCH = [[
    if not down ~= not self:GetAttribute("pf-down") then return false end
    local state = GetGamePadState()
    local pad = state and state.buttons
    local lt, rt = self:GetAttribute("pf-idx-LT"), self:GetAttribute("pf-idx-RT")
    local layer = ((pad and lt and pad[lt]) and "LT" or "") .. ((pad and rt and pad[rt]) and "RT" or "")
    if layer == "" then layer = "N" end
]] .. CLEAR .. [[
    local t = self:GetAttribute("pf-t-" .. layer)
    if t then
        self:SetAttribute("type", t)
        local k = self:GetAttribute("pf-k-" .. layer)
        if k then self:SetAttribute(k, self:GetAttribute("pf-v-" .. layer)) end
        self:SetAttribute("unit", self:GetAttribute("pf-u-" .. layer))
        return
    end
    local native = self:GetAttribute("pf-nat-" .. layer)
    if native then
        self:SetAttribute("type", "macro")
        self:SetAttribute("macrotext", native)
        return
    end
    self:SetAttribute("type", nil)
    return false
]]
M.DISPATCH_SNIPPET = DISPATCH

local function Dispatcher(key)
    local b = dispatchers[key]
    if b then return b end
    b = CreateFrame("Button", "PadForgeKey_" .. key, UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    b:SetSize(1, 1)
    b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -50, 50)
    b:RegisterForClicks("AnyDown", "AnyUp")
    SecureHandlerWrapScript(b, "OnClick", b, DISPATCH)
    dispatchers[key] = b
    return b
end

local DRIVER_EVAL = [[
    self:ClearBindings()
    if self:GetAttribute("pf-enabled") and self:GetAttribute("state-pf") == "on" then
        local key, button = self:GetAttribute("pf-key"), self:GetAttribute("pf-button")
        for _, prefix in ipairs(newtable("", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "CTRL-ALT-", "CTRL-ALT-SHIFT-")) do
            self:SetBindingClick(true, prefix .. key, button, "LeftButton")
        end
    end
]]
M.DRIVER_SNIPPET = DRIVER_EVAL

local function Driver(key)
    local d = drivers[key]
    if d then return d end
    d = CreateFrame("Frame", "PadForgeSmart_" .. key, UIParent, "SecureHandlerStateTemplate")
    d:SetAttribute("pf-eval", DRIVER_EVAL)
    d:SetAttribute("_onstate-pf", [[ self:RunAttribute("pf-eval") ]])
    drivers[key] = d
    return d
end

local function SetDriver(key, cond, enabled)
    local d = Driver(key)
    UnregisterStateDriver(d, "pf")
    d:SetAttribute("pf-key", key)
    d:SetAttribute("pf-button", Dispatcher(key):GetName())
    d:SetAttribute("pf-enabled", enabled or nil)
    if cond then RegisterStateDriver(d, "pf", cond .. " on; off") end
    SecureHandlerExecute(d, [[ self:RunAttribute("pf-eval") ]])
end

local function StopDriver(key)
    local d = drivers[key]
    if not d then return end
    UnregisterStateDriver(d, "pf")
    d:SetAttribute("pf-enabled", nil)
    SecureHandlerExecute(d, [[ self:ClearBindings() ]])
end

---------------------------------------------------------------------------
-- What each key does now: its status for the UI too
---------------------------------------------------------------------------
M.status = {}

-- Whether an entry does anything (a mode other than the game's, and an
-- action that can run)
local function Active(key, e)
    if not e or e.mode == "game" then return false end
    for _, layer in ipairs(M.LayersOf(key)) do
        if e.layers[layer] and A.Secure(e.layers[layer]) then return true end
    end
    return false
end
M.Active = Active

-- Sets a key's dispatcher up from its entry; false and why if it can't
local function Prepare(key, e)
    local b = Dispatcher(key)
    b:SetAttribute("pf-down", B.KeyDown() or nil)
    b:SetAttribute("useOnKeyDown", B.KeyDown())
    b:SetAttribute("pf-idx-LT", Pad.Index("PADLTRIGGER"))
    b:SetAttribute("pf-idx-RT", Pad.Index("PADRTRIGGER"))
    for _, layer in ipairs(Pad.LAYERS) do
        for _, a in ipairs({ "pf-t-", "pf-k-", "pf-v-", "pf-u-", "pf-nat-" }) do b:SetAttribute(a .. layer, nil) end
    end
    if B.IS_FACE[key] then
        local ok, why = B.CanPassThrough(key)
        if not ok then return false, "Can't free " .. Pad.Name(key) .. ": " .. why .. "." end
        local n = B.CrossbarIndex(key)
        for _, layer in ipairs({ "LT", "RT", "LTRT" }) do
            b:SetAttribute("pf-nat-" .. layer, "/click " .. B.CrossbarButtonName(layer, n) .. " LeftButton true")
        end
    end
    for _, layer in ipairs(M.LayersOf(key)) do
        local action = e.layers[layer]
        if action then
            local t, attr, value, unit = A.Secure(action)
            if t then
                b:SetAttribute("pf-t-" .. layer, t)
                b:SetAttribute("pf-k-" .. layer, attr)
                b:SetAttribute("pf-v-" .. layer, value)
                b:SetAttribute("pf-u-" .. layer, unit)
            end
        end
    end
    return true
end

function M.Refresh()
    wipe(M.status)
    local s = Section()
    for _, key in ipairs(M.Keys()) do
        local e = s and s.keys[key]
        if Active(key, e) then
            local ok, why = Prepare(key, e)
            M.status[key] = ok and "ready" or why
        else
            M.status[key] = nil
        end
    end
end

-- The claims (Binds.lua): plain keys, smart keys (reserved: their drivers
-- bind them) and relocations
B.Register("buttons", function()
    local claims = {}
    if not M.running then return claims end
    local s = Section()
    if not s then return claims end
    for _, key in ipairs(M.Keys()) do
        local e = s.keys[key]
        if Active(key, e) and M.status[key] == "ready" then
            local label = A.Label(e.layers.N or e.layers.LT or e.layers.RT or e.layers.LTRT)
            if e.mode == "smart" then
                claims[#claims + 1] = { key = key, reserve = true, label = "Smart: " .. label }
            else
                claims[#claims + 1] = { key = key, click = Dispatcher(key):GetName(), label = label }
            end
        end
    end
    for from, to in pairs(s.relocate) do
        local action = B.NativeAction(from)
        if action then
            claims[#claims + 1] = { key = to, command = action, label = B.NativeName(action) .. " (moved from " .. Pad.Name(from) .. ")" }
        end
    end
    return claims
end, 10)

-- After every apply: smart drivers on only for the keys this module won,
-- and only while the game has the pad
PF.On("PF_BINDS_APPLIED", function(_, inGame)
    local s = Section()
    for _, key in ipairs(M.Keys()) do
        local e = s and s.keys[key]
        local claim = B.applied[key]
        local mine = claim and claim.source == "buttons" and claim.reserve
        if M.running and mine and e and e.mode == "smart" then
            SetDriver(key, M.CONDITIONS[e.cond].macro, inGame)
        else
            StopDriver(key)
        end
    end
end)

function M.Enable() M.Refresh() end

function M.Disable()
    wipe(M.status)
    for key in pairs(drivers) do StopDriver(key) end
end

---------------------------------------------------------------------------
-- Changes (from the UI); out of combat
---------------------------------------------------------------------------
local function Changed()
    PF.RefreshModule("buttons")
end

function M.SetMode(key, mode)
    local e = M.Entry(key, true)
    e.mode = mode
    Changed()
end

function M.SetCondition(key, cond)
    local e = M.Entry(key, true)
    e.cond = M.CONDITIONS[cond] and cond or "enemy"
    Changed()
end

function M.SetAction(key, layer, action)
    local e = M.Entry(key, true)
    e.layers[layer or "N"] = action
    if action and e.mode == "game" then e.mode = B.IS_FACE[key] and "smart" or "action" end
    Changed()
end

function M.SetRelocation(from, to)
    local s = Section()
    if to then
        -- (one target holds one moved binding)
        for f, t in pairs(s.relocate) do if t == to then s.relocate[f] = nil end end
    end
    s.relocate[from] = to
    Changed()
end

function M.Relocation(from)
    local s = Section()
    return s and s.relocate[from]
end

-- What a freed key loses, for the UI ("Jump", "Auto Run"...), or nil
function M.Loses(key)
    local e = M.Entry(key)
    if not Active(key, e) then return nil end
    local action = B.NativeAction(key)
    if not action then return nil end
    if M.Relocation(key) then return nil end
    if B.IS_FACE[key] and e.mode == "smart" then
        return B.NativeName(action) .. " (while the condition holds)"
    end
    return B.NativeName(action)
end
