-- Wheels: radial menus that work in combat.
--
-- Press the wheel button (LT / RT / both / LB / RB held pick another
-- wheel), point with the right stick, press A. Holding the wheel button
-- while you aim and letting it go also uses the slot. The D-pad steps
-- through slots, B closes, the left stick still walks.
--
-- Every press is a secure button: the pick is read from the pad inside
-- secure code (GetGamePadState). No game setting is changed for it. Wheel
-- contents are rebuilt out of combat only.
--
-- Built-in sources fill themselves: Items (quest items, then consumables),
-- Consumables, Quest items, Raid markers, Chat phrases, Group (target a
-- member), Mounts. Custom wheels hold whatever you put in them.
local _, PF = ...
local A, B, Pad = PF.Actions, PF.Binds, PF.Pad

local M = PF.NewModule("wheels", {
    title = "Wheels",
    desc = "Radial menus for items, quest items, markers, chat, group targeting and your own picks.",
    order = 30,
    compat = { ConsolePort = "ConsolePort", ImprovedForever_Wheel = "Improved Forever: Wheel" },
})
PF.Wheels = M

local MAX_SLOTS, MAX_WHEELS = 12, 8
M.MAX_SLOTS, M.MAX_WHEELS = MAX_SLOTS, MAX_WHEELS
M.CHORDS = { "N", "LT", "RT", "LTRT", "LB", "RB" }
M.CHORD_LABELS = { N = "Alone", LT = "LT held", RT = "RT held", LTRT = "LT+RT held", LB = "LB held", RB = "RB held" }
M.SOURCES = {
    items = "Items (quest items, then consumables)",
    consumables = "Consumables",
    questitems = "Quest items",
    markers = "Raid markers",
    phrases = "Chat phrases",
    group = "Group members",
    mounts = "Mounts",
    pets = "Pets",
    custom = "Custom",
}
M.SOURCE_ORDER = { "custom", "items", "consumables", "questitems", "markers", "phrases", "group", "mounts", "pets" }
M.WHEEL_KEYS = { "PADRSTICK", "PADLSTICK", "PADPADDLE1", "PADPADDLE2", "PADPADDLE3", "PADPADDLE4", "PADSOCIAL" }

local function Validate(t)
    t.list = type(t.list) == "table" and t.list or {}
    local clean = {}
    for _, w in ipairs(t.list) do
        if type(w) == "table" and M.SOURCES[w.source] and #clean < MAX_WHEELS then
            w.name = type(w.name) == "string" and w.name:sub(1, 24) or "Wheel"
            if w.source == "custom" then
                local slots = {}
                for _, a in ipairs(type(w.slots) == "table" and w.slots or {}) do
                    if type(a) == "string" and #slots < MAX_SLOTS then slots[#slots + 1] = a end
                end
                w.slots = slots
            else
                w.slots = nil
            end
            clean[#clean + 1] = w
        end
    end
    t.list = clean
    t.chords = type(t.chords) == "table" and t.chords or {}
    for chord, index in pairs(t.chords) do
        if not M.CHORD_LABELS[chord] or type(index) ~= "number" or not clean[index] then t.chords[chord] = nil end
    end
    t.select = "confirm"
    local okKey = false
    for _, k in ipairs(M.WHEEL_KEYS) do if k == t.key then okKey = true end end
    if not okKey then t.key = "PADRSTICK" end
    t.phrases = type(t.phrases) == "table" and t.phrases or PF.Util.Copy(A.DEFAULT_PHRASES)
    t.scale = tonumber(t.scale) or 1
    t.look = M.ValidateLook(t.look)
    return t
end

PF.DB.RegisterDefaults("wheels", {
    list = {
        { name = "Items", source = "items" },
        { name = "Markers", source = "markers" },
        { name = "Chat", source = "phrases" },
        { name = "Group", source = "group" },
        { name = "Mounts", source = "mounts" },
    },
    -- (no wheel on a button until chosen: R3 is the game's ping)
    chords = {},
    key = "PADRSTICK",
    select = "confirm",
    phrases = PF.Util.Copy(A.DEFAULT_PHRASES),
    scale = 1,
    look = { theme = "dark", bg = "theme", glow = "theme", opacity = 0.45, radius = 120, icon = 44,
        title = true, labels = true, hint = true, x = 480, y = -60 },
}, Validate)

local function Section()
    local p = PF.P()
    return p and p.wheels
end

---------------------------------------------------------------------------
-- Contents
---------------------------------------------------------------------------
local CONSUMABLE = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
local MISC = (Enum and Enum.ItemClass and Enum.ItemClass.Miscellaneous) or 15
local MOUNT_SUB = 5
-- Consumables in this order: potions, food & drink, bandages, elixirs,
-- flasks, scrolls, the rest
local CONSUMABLE_RANK = { [1] = 1, [5] = 2, [7] = 3, [2] = 4, [3] = 5, [4] = 6 }

local function Consumables()
    local list = {}
    A.EachBagItem(function(id)
        local classID, sub = A.ItemClass(id)
        if classID == CONSUMABLE and A.ItemSpell(id) then list[#list + 1] = { id = id, rank = CONSUMABLE_RANK[sub] or 9 } end
    end)
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.id < b.id
    end)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = "item:" .. e.id end
    return out
end

local function QuestItems()
    local out = {}
    if PF.QuestItem then
        for _, c in ipairs(PF.QuestItem.Candidates()) do out[#out + 1] = "item:" .. c.id end
    end
    return out
end

-- Class mounts and travel forms (cast by name: the rank you have)
local MOUNT_SPELLS = { 13819, 23214, 5784, 23161, 783, 2645, 5118, 13159, 33943, 40120, 1066 }
local COMPANION = 2   -- (Miscellaneous: Companion Pets)

local function Companions(kind, out, seen)
    if not (GetNumCompanions and GetCompanionInfo) then return end
    local ok, n = pcall(GetNumCompanions, kind)
    if not ok then return end
    for i = 1, n or 0 do
        local _, _, spellID = GetCompanionInfo(kind, i)
        if spellID and not seen["spell:" .. spellID] then
            seen["spell:" .. spellID] = true
            out[#out + 1] = "spell:" .. spellID
        end
    end
end

local function Mounts()
    local out, seen = {}, {}
    local book = A.SpellbookNames()
    for _, id in ipairs(MOUNT_SPELLS) do
        local name = A.SpellInfo(id)
        local known = name and book[name]
        if known and not seen[name] then
            seen[name] = true
            out[#out + 1] = "spell:" .. known
        end
    end
    if C_MountJournal and C_MountJournal.GetMountIDs then
        for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
            local _, spellID, _, _, usable, _, favorite, _, _, hidden, collected = C_MountJournal.GetMountInfoByID(mountID)
            if collected and usable and not hidden and spellID and not seen["spell:" .. spellID] then
                seen["spell:" .. spellID] = true
                table.insert(out, favorite and 1 or (#out + 1), "spell:" .. spellID)
            end
        end
    end
    Companions("MOUNT", out, seen)
    A.EachBagItem(function(id)
        local classID, sub = A.ItemClass(id)
        if classID == MISC and sub == MOUNT_SUB and A.ItemSpell(id) then out[#out + 1] = "item:" .. id end
    end)
    return out
end

local function Pets()
    local out, seen = {}, {}
    Companions("CRITTER", out, seen)
    A.EachBagItem(function(id)
        local classID, sub = A.ItemClass(id)
        if classID == MISC and sub == COMPANION and A.ItemSpell(id) then out[#out + 1] = "item:" .. id end
    end)
    return out
end

function M.Contents(w)
    local s = Section()
    local src = w.source
    local list
    if src == "custom" then
        list = w.slots or {}
    elseif src == "items" then
        list = QuestItems()
        for _, a in ipairs(Consumables()) do list[#list + 1] = a end
    elseif src == "consumables" then
        list = Consumables()
    elseif src == "questitems" then
        list = QuestItems()
    elseif src == "markers" then
        list = { "marker:8", "marker:7", "marker:6", "marker:5", "marker:4", "marker:3", "marker:2", "marker:1", "marker:0" }
    elseif src == "phrases" then
        list = {}
        for _, text in ipairs(s.phrases or {}) do list[#list + 1] = "say:auto|" .. text end
    elseif src == "group" then
        list = { "target:player", "target:party1", "target:party2", "target:party3", "target:party4", "target:pet", "target:focus", "target:targettarget" }
    elseif src == "mounts" then
        list = Mounts()
    elseif src == "pets" then
        list = Pets()
    end
    local out, seen = {}, {}
    for _, action in ipairs(list or {}) do
        if #out >= MAX_SLOTS then break end
        if not seen[action] and A.Secure(action) then
            seen[action] = true
            out[#out + 1] = action
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Secure frames
---------------------------------------------------------------------------
local ring = CreateFrame("Frame", "PadForgeRing", UIParent, "SecureHandlerBaseTemplate")
ring:SetSize(10, 10)
ring:SetPoint("CENTER")
ring:Hide()
M.ring = ring

-- While a wheel is up this child takes both sticks (the right one aims
-- without turning the camera; the left one walks through bindings below)
local capture = CreateFrame("Frame", nil, ring)
capture:SetAllPoints(ring)
if capture.EnableGamePadStick then
    capture:EnableGamePadStick(true)
    capture:SetScript("OnGamePadStick", function() end)
end

local CLEAR = [[
    self:SetAttribute("spell", nil)
    self:SetAttribute("item", nil)
    self:SetAttribute("macro", nil)
    self:SetAttribute("macrotext", nil)
    self:SetAttribute("unit", nil)
]]

-- (self: a button; `ring`, `pick` set) the picked slot onto self, the ring closed
local LOAD = CLEAR .. [[
    local p = "pf-w" .. (ring:GetAttribute("pf-active") or 0) .. "-"
    self:SetAttribute("type", ring:GetAttribute(p .. "t-" .. pick))
    local k = ring:GetAttribute(p .. "k-" .. pick)
    if k then self:SetAttribute(k, ring:GetAttribute(p .. "v-" .. pick)) end
    self:SetAttribute("unit", ring:GetAttribute(p .. "u-" .. pick))
    ring:SetAttribute("pf-usedn", (ring:GetAttribute("pf-usedn") or 0) + 1)
    ring:SetAttribute("pf-used", pick)
    ring:Hide()
]]

-- The slot the right stick points at, or nil under `needed` (squared length)
ring:SetAttribute("pf-pick", [[
    local needed = ...
    local state = GetGamePadState()
    local stick = state and state.sticks and state.sticks[self:GetAttribute("pf-stick") or 2]
    if not (stick and stick.x and stick.y) then return nil end
    local x, y = stick.x, stick.y
    if x * x + y * y < needed then return nil end
    local p = "pf-w" .. (self:GetAttribute("pf-active") or 0) .. "-"
    local best, bestDot
    for i = 1, self:GetAttribute(p .. "n") or 0 do
        local dot = x * (self:GetAttribute(p .. "dx-" .. i) or 0) + y * (self:GetAttribute(p .. "dy-" .. i) or 0)
        if not bestDot or dot > bestDot then best, bestDot = i, dot end
    end
    return best
]])

local function SecureButton(name, clicks)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    b:SetSize(1, 1)
    b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -50, 50)
    b:RegisterForClicks(unpack(clicks))
    SecureHandlerSetFrameRef(b, "ring", ring)
    return b
end

-- The wheel button: opens on the press (the wheel of the buttons held);
-- on the release, a slot pointed at is used (hold, aim, release). Pressed
-- again while a wheel is up: closes it.
local trigger = SecureButton("PadForgeWheelTrigger", { "AnyDown", "AnyUp" })
trigger:SetAttribute("useOnKeyDown", false)
M.TRIGGER_SNIPPET = [[
    local ring = self:GetFrameRef("ring")
    self:SetAttribute("type", nil)
    if down then
        if ring:IsShown() then
            ring:Hide()
            self:SetAttribute("pf-armed", nil)
            return false
        end
        local state = GetGamePadState()
        local pad = state and state.buttons
        local iLT, iRT = ring:GetAttribute("pf-idx-LT"), ring:GetAttribute("pf-idx-RT")
        local iLB, iRB = ring:GetAttribute("pf-idx-LB"), ring:GetAttribute("pf-idx-RB")
        local lt = pad and iLT and pad[iLT]
        local rt = pad and iRT and pad[iRT]
        local chord
        if lt and rt then chord = "LTRT"
        elseif lt then chord = "LT"
        elseif rt then chord = "RT"
        elseif pad and iLB and pad[iLB] then chord = "LB"
        elseif pad and iRB and pad[iRB] then chord = "RB"
        else chord = "N" end
        local w = ring:GetAttribute("pf-chord-" .. chord)
        if not w or (ring:GetAttribute("pf-w" .. w .. "-n") or 0) == 0 then
            self:SetAttribute("pf-armed", nil)
            return false
        end
        ring:SetAttribute("pf-active", w)
        ring:SetAttribute("pf-sticky", nil)
        ring:SetAttribute("pf-axis", 0)
        -- (the slot a stick already pushed points at as it opens: turning
        -- the camera as R3 went down must not fire it on the release)
        ring:SetAttribute("pf-stale", ring:RunAttribute("pf-pick", 0.25))
        ring:Show()
        self:SetAttribute("pf-armed", true)
        return false
    end
    if not self:GetAttribute("pf-armed") then return false end
    self:SetAttribute("pf-armed", nil)
    if not ring:IsShown() then return false end
    local pick = ring:RunAttribute("pf-pick", 0.25)
    if not pick or pick == ring:GetAttribute("pf-stale") then return false end
]] .. LOAD
SecureHandlerWrapScript(trigger, "OnClick", trigger, M.TRIGGER_SNIPPET)

-- Stick directions (as keys): keep the pick; in flick mode, the stick
-- coming back to the middle uses it
local aim = SecureButton("PadForgeWheelAim", { "AnyDown", "AnyUp" })
aim:SetAttribute("useOnKeyDown", false)
M.AIM_SNIPPET = [[
    local ring = self:GetFrameRef("ring")
    self:SetAttribute("type", nil)
    if not ring:IsShown() then return false end
    local p = ring:RunAttribute("pf-pick", 0.1)
    if p then ring:SetAttribute("pf-sticky", p) end
    return false
]]
SecureHandlerWrapScript(aim, "OnClick", aim, M.AIM_SNIPPET)

-- A: use the slot pointed at now, else the kept pick
local use = SecureButton("PadForgeWheelUse", { "AnyDown" })
use:SetAttribute("useOnKeyDown", true)
M.USE_SNIPPET = [[
    local ring = self:GetFrameRef("ring")
    self:SetAttribute("type", nil)
    if not ring:IsShown() then return false end
    local pick = ring:RunAttribute("pf-pick", 0.25) or ring:GetAttribute("pf-sticky")
    if not pick then return false end
]] .. LOAD
SecureHandlerWrapScript(use, "OnClick", use, M.USE_SNIPPET)

-- D-pad: step round the wheel
local step = SecureButton("PadForgeWheelStep", { "AnyDown" })
M.STEP_SNIPPET = [[
    local ring = self:GetFrameRef("ring")
    if not ring:IsShown() then return false end
    local n = ring:GetAttribute("pf-w" .. (ring:GetAttribute("pf-active") or 0) .. "-n") or 0
    if n < 1 then return false end
    local current = ring:GetAttribute("pf-sticky")
    local forward = button == "PADDRIGHT" or button == "PADDDOWN"
    if not current then
        current = forward and 1 or n
    elseif forward then
        current = current % n + 1
    else
        current = (current - 2) % n + 1
    end
    ring:SetAttribute("pf-sticky", current)
    return false
]]
SecureHandlerWrapScript(step, "OnClick", step, M.STEP_SNIPPET)

local close = SecureButton("PadForgeWheelClose", { "AnyDown" })
SecureHandlerWrapScript(close, "OnClick", close, [[
    self:GetFrameRef("ring"):Hide()
    return false
]])

-- While up the wheel owns: the right stick's directions, A, B, the D-pad,
-- and the left stick's directions (bound to walking)
M.SHOW_SNIPPET = [[
    for _, prefix in ipairs(newtable("", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "CTRL-ALT-", "CTRL-ALT-SHIFT-")) do
        for _, key in ipairs(newtable("PADRSTICKUP", "PADRSTICKDOWN", "PADRSTICKLEFT", "PADRSTICKRIGHT")) do
            self:SetBindingClick(true, prefix .. key, "PadForgeWheelAim", key)
        end
        self:SetBindingClick(true, prefix .. "PAD1", "PadForgeWheelUse", "LeftButton")
        self:SetBindingClick(true, prefix .. "PAD2", "PadForgeWheelClose", "LeftButton")
        for _, key in ipairs(newtable("PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT")) do
            self:SetBindingClick(true, prefix .. key, "PadForgeWheelStep", key)
        end
        self:SetBinding(true, prefix .. "PADLSTICKUP", "MOVEFORWARD")
        self:SetBinding(true, prefix .. "PADLSTICKDOWN", "MOVEBACKWARD")
        self:SetBinding(true, prefix .. "PADLSTICKLEFT", "STRAFELEFT")
        self:SetBinding(true, prefix .. "PADLSTICKRIGHT", "STRAFERIGHT")
    end
]]
SecureHandlerWrapScript(ring, "OnShow", ring, M.SHOW_SNIPPET)
SecureHandlerWrapScript(ring, "OnHide", ring, [[ self:ClearBindings() ]])

---------------------------------------------------------------------------
-- No game setting is ever changed from here. (Earlier versions turned the
-- stick's directions into keys, GamePadStickAxisButtons, around each fight:
-- changing a gamepad setting from addon code runs the game's gamepad code
-- under our name, and the next window closing was blocked,
-- "SetPreferredGamepadInteractTarget". A wheel slot is used with A, or by
-- letting the wheel button go while aiming.)
---------------------------------------------------------------------------
PF.OnLogin(function() if PF.db then PF.db.global.axisSaved = nil end end)

---------------------------------------------------------------------------
-- Look: themes and colours (a palette, so the pad can pick them), sizes,
-- what is shown, and the position (dragged with the mouse or nudged with
-- the D-pad: M.StartMove)
---------------------------------------------------------------------------
M.PALETTE = {
    { "amber", "Amber", 1, 0.72, 0.25 }, { "gold", "Gold", 1, 0.84, 0.1 }, { "sky", "Sky", 0.31, 0.76, 0.97 },
    { "ice", "Ice", 0.78, 0.94, 1 }, { "fel", "Fel green", 0.4, 0.95, 0.3 }, { "blood", "Blood red", 0.92, 0.16, 0.2 },
    { "violet", "Violet", 0.7, 0.45, 1 }, { "rose", "Rose", 1, 0.5, 0.72 }, { "white", "White", 1, 1, 1 },
    { "night", "Night", 0.03, 0.04, 0.06 }, { "slate", "Slate", 0.12, 0.14, 0.18 }, { "navy", "Navy", 0.04, 0.07, 0.17 },
    { "forest", "Forest", 0.03, 0.10, 0.05 }, { "wine", "Wine", 0.14, 0.02, 0.05 }, { "black", "Black", 0, 0, 0 },
}
local PALETTE = {}
for _, c in ipairs(M.PALETTE) do PALETTE[c[1]] = c end

M.THEMES = {
    { "dark", "Dark", bg = "night", glow = "amber" },
    { "midnight", "Midnight", bg = "navy", glow = "sky" },
    { "frost", "Frost", bg = "slate", glow = "ice" },
    { "fel", "Fel", bg = "forest", glow = "fel" },
    { "blood", "Blood", bg = "wine", glow = "blood" },
    { "arcane", "Arcane", bg = "navy", glow = "violet" },
    { "glass", "Glass", bg = "black", glow = "white", opacity = 0.3 },
}
local THEMES = {}
for _, t in ipairs(M.THEMES) do THEMES[t[1]] = t end

M.LOOK_DEFAULTS = { theme = "dark", bg = "theme", glow = "theme", opacity = 0.45, radius = 120, icon = 44,
    title = true, labels = true, hint = true, x = 480, y = -60 }

local function Look()
    local s = Section()
    local look = s and s.look or M.LOOK_DEFAULTS
    local theme = THEMES[look.theme] or THEMES.dark
    local bg = PALETTE[look.bg ~= "theme" and look.bg or theme.bg] or PALETTE.night
    local glow = PALETTE[look.glow ~= "theme" and look.glow or theme.glow] or PALETTE.amber
    return look, bg, glow
end

function M.ValidateLook(look)
    look = type(look) == "table" and look or {}
    for k, v in pairs(M.LOOK_DEFAULTS) do if look[k] == nil then look[k] = v end end
    if not THEMES[look.theme] then look.theme = "dark" end
    if look.bg ~= "theme" and not PALETTE[look.bg] then look.bg = "theme" end
    if look.glow ~= "theme" and not PALETTE[look.glow] then look.glow = "theme" end
    look.opacity = math.max(0.1, math.min(1, tonumber(look.opacity) or 0.45))
    look.radius = math.max(80, math.min(220, tonumber(look.radius) or 120))
    look.icon = math.max(28, math.min(72, tonumber(look.icon) or 44))
    look.x = math.max(-2000, math.min(2000, tonumber(look.x) or 480))
    look.y = math.max(-1200, math.min(1200, tonumber(look.y) or -60))
    for _, k in ipairs({ "title", "labels", "hint" }) do look[k] = look[k] ~= false end
    return look
end

---------------------------------------------------------------------------
-- Visuals (a plain frame beside the secure one: drawn in combat freely)
---------------------------------------------------------------------------
local view = CreateFrame("Frame", "PadForgeRingView", UIParent)
view:SetSize(340, 340)
view:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
view:SetFrameStrata("DIALOG")
view:SetClampedToScreen(true)
view:Hide()
M.view = view

local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function Round(tex, parent)
    if parent.CreateMaskTexture then
        local mask = parent:CreateMaskTexture()
        mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(tex)
        tex:AddMaskTexture(mask)
    end
end

view.bg = view:CreateTexture(nil, "BACKGROUND")
view.bg:SetPoint("CENTER")
Round(view.bg, view)
view.edge = view:CreateTexture(nil, "BACKGROUND", nil, -1)
view.edge:SetPoint("CENTER")
Round(view.edge, view)
view.hub = view:CreateTexture(nil, "BORDER")
view.hub:SetPoint("CENTER")
Round(view.hub, view)
view.title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
view.title:SetPoint("BOTTOM", view, "TOP", 0, 6)
view.label = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
view.label:SetPoint("CENTER", 0, 8)
view.label:SetWordWrap(true)
view.sub = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
view.sub:SetPoint("TOP", view.label, "BOTTOM", 0, -4)
view.hint = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
view.hint:SetPoint("TOP", view, "BOTTOM", 0, -6)

view.slots = {}
for i = 1, MAX_SLOTS do
    local s = CreateFrame("Frame", nil, view)
    s.glow = s:CreateTexture(nil, "BACKGROUND")
    s.glow:SetPoint("TOPLEFT", -7, 7)
    s.glow:SetPoint("BOTTOMRIGHT", 7, -7)
    Round(s.glow, s)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetAllPoints()
    Round(s.icon, s)
    s.count = s:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    s.count:SetPoint("BOTTOMRIGHT", 4, -2)
    s.cd = CreateFrame("Cooldown", nil, s, "CooldownFrameTemplate")
    s.cd:SetAllPoints()
    if s.cd.SetSwipeTexture then s.cd:SetSwipeTexture(MASK) end
    -- (group slots: health under the icon, the one most in need marked)
    s.hpBg = s:CreateTexture(nil, "OVERLAY")
    s.hpBg:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -3)
    s.hpBg:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -3)
    s.hpBg:SetHeight(5)
    s.hpBg:SetColorTexture(0, 0, 0, 0.7)
    s.hp = s:CreateTexture(nil, "OVERLAY", nil, 1)
    s.hp:SetPoint("TOPLEFT", s.hpBg, "TOPLEFT")
    s.hp:SetHeight(5)
    s.need = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.need:SetPoint("BOTTOM", s, "TOP", 0, 4)
    s.need:SetTextColor(1, 0.35, 0.3)
    view.slots[i] = s
end

local wheelData = {}   -- [index] = { name, slots = { { action, label, icon, sub } } }
local preview          -- the wheel shown while moving it (M.StartMove)

local function Shown()
    if preview then return preview end
    return wheelData[ring:GetAttribute("pf-active") or 0]
end

local function Angle(i, n)
    -- First slot at the top, clockwise
    return math.pi / 2 - (i - 1) * 2 * math.pi / n
end

local function SlotCooldown(action)
    local kind, value = A.Parse(action)
    local id = tonumber(value)
    if kind == "item" and id then
        local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
        if fn then return fn(id) end
    elseif kind == "spell" and id then
        if C_Spell and C_Spell.GetSpellCooldown then
            local info = C_Spell.GetSpellCooldown(id)
            if info then return info.startTime, info.duration end
        elseif GetSpellCooldown then
            return GetSpellCooldown(id)
        end
    end
end

-- Position, size and colours from the profile
local function ApplyLook()
    local s = Section()
    local look, bg, glow = Look()
    local scale = s and s.scale or 1
    local R, I = look.radius, look.icon
    view:SetScale(scale)
    if not view.pfMoving then
        view:ClearAllPoints()
        view:SetPoint("CENTER", UIParent, "CENTER", look.x / scale, look.y / scale)
    end
    local size = 2 * R + I + 36
    view:SetSize(size, size)
    view.bg:SetSize(size - 8, size - 8)
    view.bg:SetColorTexture(bg[3], bg[4], bg[5], look.opacity)
    view.edge:SetSize(size, size)
    view.edge:SetColorTexture(glow[3], glow[4], glow[5], 0.25 * look.opacity + 0.05)
    local hub = math.max(90, 2 * R - I - 34)
    view.hub:SetSize(hub, hub)
    view.hub:SetColorTexture(math.min(1, bg[3] + 0.07), math.min(1, bg[4] + 0.08), math.min(1, bg[5] + 0.10), math.min(1, look.opacity + 0.18))
    view.label:SetWidth(hub - 16)
    view.sub:SetWidth(hub - 16)
    view.title:SetShown(look.title)
    view.label:SetShown(look.labels)
    view.sub:SetShown(look.labels)
    view.hint:SetShown(look.hint or view.pfMoving)
    for _, slot in ipairs(view.slots) do
        slot:SetSize(I, I)
        slot.glow:SetColorTexture(glow[3], glow[4], glow[5], 0.95)
    end
end
M.ApplyLook = ApplyLook

local function Layout()
    local w = Shown()
    if not w then return end
    ApplyLook()
    local n = #w.slots
    local s = Section()
    local R = Look().radius
    view.title:SetText(w.name)
    for i, slot in ipairs(view.slots) do
        local data = w.slots[i]
        if data then
            local a = Angle(i, n)
            slot:ClearAllPoints()
            slot:SetPoint("CENTER", view, "CENTER", math.cos(a) * R, math.sin(a) * R)
            slot.icon:SetTexture(data.icon or 134400)
            local kind, value = A.Parse(data.action)
            slot.unit = kind == "target" and value or nil
            if not slot.unit then slot.icon:SetDesaturated(false) end
            slot.hpBg:SetShown(slot.unit ~= nil)
            slot.hp:SetShown(slot.unit ~= nil)
            slot.need:SetText("")
            local count = kind == "item" and PF.Num(A.ItemCount(tonumber(value))) or nil
            slot.count:SetText(count and count > 1 and count or "")
            local start, duration = SlotCooldown(data.action)
            start, duration = PF.Num(start), PF.Num(duration)
            if start and duration and duration > 1.5 then slot.cd:SetCooldown(start, duration) else slot.cd:Clear() end
            slot.glow:Hide()
            slot:SetScale(1)
            slot:Show()
        else
            slot:Hide()
        end
    end
    if view.pfMoving then
        view.hint:SetText("Drag it with the mouse   " .. Pad.Glyph("PADDUP", 14) .. Pad.Glyph("PADDLEFT", 14) .. " nudge   "
            .. Pad.Glyph("PAD4", 14) .. " default place   " .. Pad.Glyph("PAD1", 14) .. " done")
    else
        view.hint:SetText("Point with " .. Pad.Glyph("PADRSTICK", 14) .. ", then " .. Pad.Glyph("PAD1", 14) .. " to use   "
            .. Pad.Glyph("PAD2", 14) .. " close")
    end
end

-- Group slots: health now, and who needs it most
local hpWait = 0
local function UpdateHealth(elapsed)
    hpWait = hpWait - elapsed
    if hpWait > 0 or not PF.Group then return end
    hpWait = 0.2
    local s = PF.P().group
    local units = {}
    for _, slot in ipairs(view.slots) do
        if slot:IsShown() and slot.unit then units[#units + 1] = slot.unit end
    end
    local lowest = (s == nil or s.health) and PF.Group.Lowest(units) or nil
    for _, slot in ipairs(view.slots) do
        if slot:IsShown() and slot.unit then
            local pct, dead = PF.Group.Health(slot.unit)
            if s and not s.health then pct = nil end
            slot.hpBg:SetShown(pct ~= nil)
            slot.hp:SetShown(pct ~= nil and pct > 0)
            if pct and pct > 0 then
                slot.hp:SetWidth(math.max(1, slot:GetWidth() * pct))
                slot.hp:SetColorTexture(1 - pct, 0.25 + 0.65 * pct, 0.25, 1)
            end
            slot.icon:SetDesaturated(dead or pct == nil)
            slot.need:SetText(slot.unit == lowest and "LOWEST" or "")
        end
    end
end

local lit
view:SetScript("OnUpdate", function(_, elapsed)
    local w = Shown()
    if not w then return end
    UpdateHealth(elapsed or 0)
    local n = #w.slots
    local pick = not preview and ring:GetAttribute("pf-sticky") or nil
    local x, y = Pad.Stick("Right")
    if x * x + y * y > 0.25 then
        local best, bestDot
        for i = 1, n do
            local a = Angle(i, n)
            local dot = x * math.cos(a) + y * math.sin(a)
            if not bestDot or dot > bestDot then best, bestDot = i, dot end
        end
        pick = best
    end
    if pick ~= lit then
        if lit and view.slots[lit] then
            view.slots[lit].glow:Hide()
            view.slots[lit]:SetScale(1)
        end
        lit = pick
        if lit and view.slots[lit] then
            view.slots[lit].glow:Show()
            view.slots[lit]:SetScale(1.15)
        end
    end
    local data = pick and w.slots[pick]
    view.label:SetText(data and data.label or w.name)
    view.sub:SetText(data and data.sub or "")
end)

ring:HookScript("OnShow", function()
    if view.pfMoving then M.StopMove() end
    lit = nil
    Layout()
    view:Show()
end)
ring:HookScript("OnHide", function() if not view.pfMoving then view:Hide() end end)
-- (a slot used: secure code counts it; the rest of the addon hears it)
ring:HookScript("OnAttributeChanged", function(_, name)
    if name == "pf-usedn" then PF.Fire("PF_WHEEL_USED") end
end)

---------------------------------------------------------------------------
-- Moving the wheel: drag it with the mouse, or nudge it with the D-pad
---------------------------------------------------------------------------
local function SavePosition()
    local look = Section().look
    local scale = view:GetScale()
    local vx, vy = view:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (vx and ux) then return end
    look.x = math.floor(vx * scale - ux + 0.5)
    look.y = math.floor(vy * scale - uy + 0.5)
    view:ClearAllPoints()
    view:SetPoint("CENTER", UIParent, "CENTER", look.x / scale, look.y / scale)
end

view:SetMovable(true)
view:RegisterForDrag("LeftButton")
view:SetScript("OnDragStart", function(self) if self.pfMoving then self:StartMoving() end end)
view:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if self.pfMoving then SavePosition() end
end)
view:SetScript("OnMouseUp", function(self, button)
    if self.pfMoving and button == "RightButton" then M.StopMove() end
end)
view:EnableMouse(false)

if view.EnableGamePadButton then
    view:SetScript("OnGamePadButtonDown", function(_, key)
        if not view.pfMoving then return end
        local look = Section().look
        local step = 10
        if key == "PADDUP" then look.y = look.y + step
        elseif key == "PADDDOWN" then look.y = look.y - step
        elseif key == "PADDLEFT" then look.x = look.x - step
        elseif key == "PADDRIGHT" then look.x = look.x + step
        elseif key == "PAD4" then look.x, look.y = M.LOOK_DEFAULTS.x, M.LOOK_DEFAULTS.y
        elseif key == "PAD1" or key == "PAD2" or key == "PADFORWARD" then M.StopMove() return
        else return end
        ApplyLook()
    end)
    -- (setting the handler turns pad input on: off until moving)
    view:EnableGamePadButton(false)
end

function M.StartMove()
    if PF.InCombat() then return PF.Print("Move the wheel after combat.") end
    if B.FocusedFrame() then return B.WaitForWindow() end
    if ring:IsShown() then ring:Hide() end
    local sample = wheelData[1]
    if not (sample and #sample.slots > 0) then
        sample = { name = "Wheel", slots = {} }
        for i = 1, 8 do sample.slots[i] = { action = "", label = "Slot " .. i, icon = 134400 } end
    end
    preview = sample
    view.pfMoving = true
    if PF.Config then PF.Config.Hide() end
    view:EnableMouse(true)
    if view.EnableGamePadButton then view:EnableGamePadButton(true) end
    lit = nil
    Layout()
    view:Show()
end

function M.StopMove(stayClosed)
    if not view.pfMoving then return end
    view.pfMoving = nil
    preview = nil
    view:EnableMouse(false)
    if view.EnableGamePadButton then view:EnableGamePadButton(false) end
    view:Hide()
    ApplyLook()
    if not stayClosed and PF.Config and not PF.InCombat() then PF.Config.Show() end
end

-- A look at the wheel without opening it (the settings page shows changes)
function M.ShowSample()
    if PF.InCombat() or view.pfMoving or ring:IsShown() then return end
    preview = wheelData[1] and #wheelData[1].slots > 0 and wheelData[1] or nil
    if not preview then return end
    lit = nil
    Layout()
    view:Show()
    C_Timer.After(2.5, function()
        if not view.pfMoving and not ring:IsShown() then
            preview = nil
            view:Hide()
        end
    end)
end

PF.On("PLAYER_REGEN_DISABLED", function() M.StopMove(true) end)
PF.On("PF_PROFILE_CHANGED", function() C_Timer.After(0, ApplyLook) end)

---------------------------------------------------------------------------
-- Rebuild: contents and secure attributes (out of combat)
---------------------------------------------------------------------------
local function ClearWheel(i)
    local p = "pf-w" .. i .. "-"
    local n = ring:GetAttribute(p .. "n") or 0
    for j = 1, n do
        for _, a in ipairs({ "t-", "k-", "v-", "u-", "dx-", "dy-" }) do ring:SetAttribute(p .. a .. j, nil) end
    end
    ring:SetAttribute(p .. "n", 0)
end

local function Rebuild()
    if PF.InCombat() then return PF.AfterCombat("wheels:rebuild", Rebuild) end
    local s = Section()
    for i = 1, MAX_WHEELS do ClearWheel(i) end
    wipe(wheelData)
    if not (M.running and s) then return end
    for i, w in ipairs(s.list) do
        local actions = M.Contents(w)
        local data = { name = w.name, slots = {} }
        local p = "pf-w" .. i .. "-"
        local n = 0
        for _, action in ipairs(actions) do
            local t, attr, value, unit = A.Secure(action)
            if t then
                n = n + 1
                ring:SetAttribute(p .. "t-" .. n, t)
                ring:SetAttribute(p .. "k-" .. n, attr)
                ring:SetAttribute(p .. "v-" .. n, value)
                ring:SetAttribute(p .. "u-" .. n, unit)
                local label, icon, sub = A.Describe(action)
                data.slots[n] = { action = action, label = label, icon = icon, sub = sub }
            end
        end
        for j = 1, n do
            local a = Angle(j, n)
            ring:SetAttribute(p .. "dx-" .. j, math.cos(a))
            ring:SetAttribute(p .. "dy-" .. j, math.sin(a))
        end
        ring:SetAttribute(p .. "n", n)
        wheelData[i] = data
    end
    for _, chord in ipairs(M.CHORDS) do ring:SetAttribute("pf-chord-" .. chord, s.chords[chord]) end
    ring:SetAttribute("pf-stick", Pad.StickIndex("Right") or 2)
    for name, binding in pairs({ LT = "PADLTRIGGER", RT = "PADRTRIGGER", LB = "PADLSHOULDER", RB = "PADRSHOULDER" }) do
        ring:SetAttribute("pf-idx-" .. name, Pad.Index(binding))
    end
end
M.Rebuild = Rebuild

function M.Data(i) return wheelData[i] end

local queued = false
local function Queue()
    if queued or not M.running then return end
    queued = true
    C_Timer.After(0.3, function()
        queued = false
        Rebuild()
    end)
end
M.Queue = Queue

for _, event in ipairs({ "BAG_UPDATE_DELAYED", "GROUP_ROSTER_UPDATE", "SPELLS_CHANGED", "UPDATE_MACROS",
    "PLAYER_EQUIPMENT_CHANGED", "NEW_MOUNT_ADDED", "QUEST_LOG_UPDATE", "COMPANION_LEARNED", "COMPANION_UPDATE", "LEARNED_SPELL_IN_TAB" }) do
    PF.On(event, Queue)
end

B.Register("wheels", function()
    if not M.running then return {} end
    local s = Section()
    local any = false
    for _ in pairs(s.chords) do any = true end
    if not any then return {} end
    return { { key = s.key, click = trigger:GetName(), label = "Wheels" } }
end, 30)

function M.Enable() Rebuild() end
function M.Refresh() Rebuild() end
function M.Disable()
    if not PF.InCombat() then ring:Hide() end
    Rebuild()
end

---------------------------------------------------------------------------
-- Changes (from the UI)
---------------------------------------------------------------------------
local function Changed() PF.RefreshModule("wheels") end
M.Changed = Changed

function M.Add(source, name)
    local s = Section()
    if #s.list >= MAX_WHEELS then return nil end
    s.list[#s.list + 1] = { name = name or M.SOURCES[source] or "Wheel", source = source, slots = source == "custom" and {} or nil }
    Changed()
    return #s.list
end

function M.Remove(index)
    local s = Section()
    table.remove(s.list, index)
    for chord, i in pairs(s.chords) do
        if i == index then s.chords[chord] = nil elseif i > index then s.chords[chord] = i - 1 end
    end
    Changed()
end

function M.SetChord(chord, index)
    Section().chords[chord] = index
    Changed()
end

M.DEFAULT_CHORDS = { N = 1, LT = 2, RT = 3, LTRT = 4, RB = 5 }

-- The four built-in wheels on the wheel button (alone, LT, RT, LT+RT)
function M.UseDefaultLayout()
    local s = Section()
    wipe(s.chords)
    for chord, index in pairs(M.DEFAULT_CHORDS) do
        if s.list[index] then s.chords[chord] = index end
    end
    Changed()
end

function M.ChordOf(index)
    for chord, i in pairs(Section().chords) do if i == index then return chord end end
end

function M.SetSlot(index, slot, action)
    local w = Section().list[index]
    if not (w and w.source == "custom") then return end
    if action then
        w.slots[slot] = action
    else
        table.remove(w.slots, slot)
    end
    Changed()
end

-- Open a wheel from the UI to look at it (out of combat)
function M.Preview(index)
    if PF.InCombat() or not wheelData[index] or B.FocusedFrame() then return end
    ring:SetAttribute("pf-active", index)
    ring:SetAttribute("pf-sticky", nil)
    ring:Show()
end
