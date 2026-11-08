-- Quick setup: a starting layout for the class in hand, offered the first
-- time PadForge opens (and any time after from its page).
--
-- Only spells the character already knows are ever used: each suggestion
-- is checked against the spellbook, so a level 5 mage never gets Blink.
-- The Spells wheel it makes keeps growing as the suggestions are learned
-- (out of combat, one line in chat each time).
local _, PF = ...
local A = PF.Actions

local M = PF.NewModule("setup", {
    title = "Quick setup",
    desc = "A starting layout for your class, with only the spells you already know.",
    order = 3,
})
PF.Setup = M

PF.DB.RegisterDefaults("setup", { done = false }, function(t)
    t.done = t.done == true
    return t
end)

-- Rank 1 spell IDs, the class's everyday spells first. The first one is
-- the main attack (for Smart X).
M.CLASS = {
    MAGE = { 133, 116, 2136, 122, 1449, 118, 2139, 1953, 168, 1459 },
    WARRIOR = { 78, 772, 100, 6343, 1715, 7384, 6673, 7386, 2457, 71 },
    ROGUE = { 1752, 2098, 1784, 53, 1776, 1766, 2983, 5171, 1856, 921 },
    PRIEST = { 585, 2050, 17, 589, 139, 2054, 8092, 586, 1243, 528 },
    HUNTER = { 2973, 1978, 3044, 5116, 1130, 136, 2974, 13165, 883, 75 },
    WARLOCK = { 686, 348, 172, 980, 1454, 5782, 689, 687, 688, 702 },
    PALADIN = { 20271, 21084, 635, 465, 19740, 498, 853, 1152, 633, 642 },
    DRUID = { 5176, 5185, 8921, 774, 339, 1126, 5487, 768, 467, 783 },
    SHAMAN = { 403, 8042, 331, 8017, 324, 8071, 8050, 3599, 2645, 2484 },
}

local function ClassList()
    local _, class = UnitClass("player")
    return M.CLASS[class] or {}
end

-- The suggestions the character knows now: { action, id, label, icon }
-- (the rank they have: casting by name casts it)
function M.Known()
    local book = A.SpellbookNames()
    local out = {}
    for _, id in ipairs(ClassList()) do
        local name = A.SpellInfo(id)
        local have = name and book[name]
        if have and A.KnownSpell(id, book) then
            local action = "spell:" .. have
            local label, icon = A.Describe(action)
            out[#out + 1] = { action = action, id = id, label = label, icon = icon }
        end
    end
    return out
end

-- The main attack, when known
function M.MainAttack()
    local first = ClassList()[1]
    for _, e in ipairs(M.Known()) do
        if e.id == first then return e end
    end
end

local function SpellsWheel()
    local list = PF.P().wheels.list
    for i, w in ipairs(list) do
        if w.source == "custom" and w.auto then return i, w end
    end
end

-- opts: { wheels = bool, spells = bool, smartX = bool }
function M.Apply(opts)
    local Wheels, Buttons = PF.Wheels, PF.Buttons
    if opts.wheels then Wheels.UseDefaultLayout() end
    if opts.spells then
        local known = M.Known()
        if #known > 0 then
            local index, w = SpellsWheel()
            if not w then
                index = Wheels.Add("custom", "Spells")
                w = index and PF.P().wheels.list[index]
            end
            if w then
                w.auto = true
                w.slots = {}
                for i, e in ipairs(known) do
                    if i > Wheels.MAX_SLOTS then break end
                    w.slots[i] = e.action
                end
                local old = Wheels.ChordOf(index)
                if old ~= "LB" then
                    if PF.P().wheels.chords.LB then PF.P().wheels.chords.LB = nil end
                    Wheels.SetChord("LB", index)
                end
            end
        end
    end
    if opts.smartX then
        local main = M.MainAttack()
        if main then
            Buttons.SetAction("PAD3", "N", main.action)
            Buttons.SetMode("PAD3", "smart")
            Buttons.SetCondition("PAD3", "enemy")
        end
    end
    PF.P().setup.done = true
    PF.EnableModules()
end

function M.Done() return PF.P() and PF.P().setup.done end

---------------------------------------------------------------------------
-- Growing the Spells wheel as suggestions are learned
---------------------------------------------------------------------------
local function Grow()
    if PF.InCombat() then return PF.AfterCombat("setup:grow", Grow) end
    if not (M.running and PF.P()) then return end
    local _, w = SpellsWheel()
    if not w then return end
    local have = {}
    for _, action in ipairs(w.slots) do
        local name = A.Label(action)
        have[name] = true
    end
    local added = {}
    for _, e in ipairs(M.Known()) do
        if #w.slots >= PF.Wheels.MAX_SLOTS then break end
        if not have[e.label] then
            w.slots[#w.slots + 1] = e.action
            added[#added + 1] = e.label
            have[e.label] = true
        end
    end
    if #added > 0 then
        PF.Print("Added to your Spells wheel: " .. table.concat(added, ", ") .. ".")
        PF.Wheels.Changed()
    end
end
M.Grow = Grow

local pending = false
local function Queue()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        Grow()
    end)
end
for _, event in ipairs({ "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP", "SPELLS_CHANGED" }) do
    PF.On(event, Queue)
end

function M.Enable() end
