-- What a press or a wheel slot runs, as a short string (compact in saved
-- data and export strings):
--   spell:<id>              a spell (cast by name: the highest rank)
--   item:<id>               an item (bags or equipped)
--   macro:<name>            one of the player's macros
--   emote:<token>           an emote ("WAVE")
--   say:<chan>|<text>       a chat line; chan s, p, g, ra, y, or "auto"
--                           (raid, else party, else say)
--   marker:<0-8>            a raid marker on the target (0 clears)
--   target:<unit>           target a unit (player, party1, focus...)
--   ground:<at>:<spellid>   a ground spell at your feet / the target / cursor
--   groupnext / groupprev   the next / previous living group member
--   questitem               the best usable quest item right now
--   open                    open PadForge
-- (No free macro text: a shared profile can only name the player's own
-- macros, made in the game with /macro, never bring commands of its own.)
local _, PF = ...

local A = {}
PF.Actions = A

---------------------------------------------------------------------------
-- Game API across client versions
---------------------------------------------------------------------------
function A.SpellInfo(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info then return info.name, info.iconID end
    end
    if GetSpellInfo then
        local name, _, icon = GetSpellInfo(id)
        return name, icon
    end
end

function A.ItemInfo(id)
    if not id then return nil end
    local name, icon
    if C_Item and C_Item.GetItemInfo then name = C_Item.GetItemInfo(id) elseif GetItemInfo then name = GetItemInfo(id) end
    if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id) end
    if not icon then
        local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if instant then icon = select(5, instant(id)) end
    end
    return name, icon
end

function A.ItemClass(id)
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not instant then return nil end
    local _, _, _, equipLoc, _, classID, subclassID = instant(id)
    return classID, subclassID, equipLoc
end

function A.ItemSpell(id)
    local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    return fn and fn(id) or nil
end

function A.ItemCount(id)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    return fn and fn(id) or 0
end

local function NumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function SlotItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and info.itemID
    end
    return GetContainerItemID and GetContainerItemID(bag, slot)
end

local function SlotQuest(bag, slot)
    if C_Container and C_Container.GetContainerItemQuestInfo then
        local info = C_Container.GetContainerItemQuestInfo(bag, slot)
        if info then return info.isQuestItem, info.questID, info.isActive end
    elseif GetContainerItemQuestInfo then
        return GetContainerItemQuestInfo(bag, slot)
    end
end

-- Every bag item, once per item ID: fn(itemID, bag, slot)
function A.EachBagItem(fn)
    local seen = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, NumSlots(bag) or 0 do
            local id = SlotItem(bag, slot)
            if id and not seen[id] then
                seen[id] = true
                fn(id, bag, slot)
            end
        end
    end
end
A.SlotQuest = SlotQuest

---------------------------------------------------------------------------
-- Parsing and describing
---------------------------------------------------------------------------
function A.Parse(action)
    if type(action) ~= "string" or action == "" then return nil end
    local kind, value = action:match("^(%a+):(.*)$")
    if kind then return kind, value end
    return action, nil
end

local MARKER_NAMES = { [0] = "Clear marker", "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
A.MARKER_NAMES = MARKER_NAMES
local UNIT_NAMES = {
    player = "Yourself", party1 = "Party member 1", party2 = "Party member 2", party3 = "Party member 3",
    party4 = "Party member 4", pet = "Your pet", focus = "Focus", targettarget = "Target's target",
}
local GROUND_AT = { player = "at your feet", target = "at the target", cursor = "at the cursor" }
A.GROUND_AT = GROUND_AT
local CHANNELS = { auto = "Group", s = "Say", p = "Party", g = "Guild", ra = "Raid", y = "Yell" }
A.CHANNELS = CHANNELS
local QUESTION = 134400

local function UnitLabel(unit)
    if UnitExists and UnitExists(unit) and unit ~= "player" then
        local name = UnitName(unit)
        if name then return name end
    end
    return UNIT_NAMES[unit] or unit
end

-- label, icon (a file ID or path)
function A.Describe(action)
    local kind, value = A.Parse(action)
    if not kind then return "Nothing", nil end
    if kind == "spell" then
        local name, icon = A.SpellInfo(tonumber(value))
        return name or ("Spell " .. value), icon or QUESTION
    elseif kind == "item" then
        local name, icon = A.ItemInfo(tonumber(value))
        return name or ("Item " .. value), icon or QUESTION
    elseif kind == "macro" then
        local _, icon = GetMacroInfo and GetMacroInfo(value)
        return value, icon or QUESTION
    elseif kind == "emote" then
        return "/" .. value:lower(), 132282
    elseif kind == "say" then
        local chan, text = (value or ""):match("^(%a+)|(.*)$")
        return (text or value or ""), 132281, CHANNELS[chan]
    elseif kind == "marker" then
        local n = tonumber(value) or 0
        return MARKER_NAMES[n] or "Marker", n > 0 and ("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. n) or 136813
    elseif kind == "target" then
        return "Target " .. UnitLabel(value), 132212
    elseif kind == "ground" then
        local at, id = (value or ""):match("^(%a+):(%d+)$")
        local name, icon = A.SpellInfo(tonumber(id))
        return (name or "Spell") .. " " .. (GROUND_AT[at] or ""), icon or QUESTION
    elseif kind == "groupnext" then
        return "Next group member", 132212
    elseif kind == "groupprev" then
        return "Previous group member", 132212
    elseif kind == "questitem" then
        local id = PF.QuestItem and PF.QuestItem.Current()
        local _, icon = A.ItemInfo(id)
        return "Quest item" .. (id and (": " .. (A.ItemInfo(id) or "")) or ""), icon or 133469
    elseif kind == "open" then
        return "Open PadForge", "Interface\\Icons\\INV_Gizmo_02"
    end
    return action, QUESTION
end

function A.Label(action) return (A.Describe(action)) end
function A.Icon(action) return select(2, A.Describe(action)) end

---------------------------------------------------------------------------
-- What a secure button needs to run an action: type, the attribute that
-- carries it, its value, a unit (or nil). Only out of combat (it reads
-- spell names and the group).
---------------------------------------------------------------------------
local function ChannelCommand(chan)
    if chan == "auto" then
        if IsInRaid and IsInRaid() then return "/ra" end
        if IsInGroup and IsInGroup() then return "/p" end
        return "/s"
    end
    return "/" .. (CHANNELS[chan] and chan or "s")
end

local function SafeText(text)
    -- (one line, macro length)
    return (text or ""):gsub("[\r\n]+", " "):sub(1, 240)
end

function A.Secure(action)
    local kind, value = A.Parse(action)
    if not kind then return nil end
    if kind == "spell" then
        local name = A.SpellInfo(tonumber(value))
        if not name then return nil end
        return "spell", "spell", name
    elseif kind == "item" then
        return "item", "item", "item:" .. (tonumber(value) or 0)
    elseif kind == "macro" then
        if GetMacroIndexByName and GetMacroIndexByName(value) == 0 then return nil end
        return "macro", "macro", value
    elseif kind == "emote" then
        return "macro", "macrotext", "/" .. value:lower():gsub("[^%w]", "")
    elseif kind == "say" then
        local chan, text = (value or ""):match("^(%a+)|(.*)$")
        if not text or text == "" then return nil end
        return "macro", "macrotext", ChannelCommand(chan) .. " " .. SafeText(text)
    elseif kind == "marker" then
        local n = math.max(0, math.min(8, tonumber(value) or 0))
        return "macro", "macrotext", "/run SetRaidTarget(\"target\"," .. n .. ")"
    elseif kind == "target" then
        return "target", nil, nil, value
    elseif kind == "ground" then
        local at, id = (value or ""):match("^(%a+):(%d+)$")
        local name = A.SpellInfo(tonumber(id))
        if not name or not GROUND_AT[at] then return nil end
        local cond = at == "target" and "[@target,exists][@player]" or ("[@" .. at .. "]")
        return "macro", "macrotext", "/cast " .. cond .. " " .. name
    elseif kind == "groupnext" then
        return "macro", "macrotext", "/click PadForgeGroupCycle LeftButton true"
    elseif kind == "groupprev" then
        return "macro", "macrotext", "/click PadForgeGroupCycle RightButton true"
    elseif kind == "questitem" then
        return "macro", "macrotext", "/click PadForgeQuestItemButton LeftButton true"
    elseif kind == "open" then
        return "macro", "macrotext", "/click PadForgeOpenButton"
    end
end

-- Sets an action straight onto a secure button (out of combat); false if
-- it can't run
function A.ApplyTo(button, action, prefix)
    prefix = prefix or ""
    local t, attr, value, unit = A.Secure(action)
    for _, a in ipairs({ "spell", "item", "macro", "macrotext", "unit" }) do button:SetAttribute(prefix .. a, nil) end
    button:SetAttribute(prefix .. "type", t)
    if attr then button:SetAttribute(prefix .. attr, value) end
    if unit then button:SetAttribute(prefix .. "unit", unit) end
    return t ~= nil
end

---------------------------------------------------------------------------
-- Lists for the pickers: { action, label, icon } each
---------------------------------------------------------------------------
local function Entry(action)
    local label, icon = A.Describe(action)
    return { action = action, label = label, icon = icon }
end

function A.SpellbookSpells()
    local list, byName = {}, {}
    local function add(id, isPassive)
        if not id or isPassive then return end
        local name = A.SpellInfo(id)
        if not name then return end
        -- (one per name: the highest rank, which is what casting the name does)
        if byName[name] then
            if id > byName[name].id then byName[name].id, byName[name].action = id, "spell:" .. id end
            return
        end
        local e = { id = id, action = "spell:" .. id }
        byName[name] = e
        list[#list + 1] = e
    end
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info and not info.shouldHide then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
                    if item and item.itemType == Enum.SpellBookItemType.Spell then add(item.spellID or item.actionID, item.isPassive) end
                end
            end
        end
    elseif GetNumSpellTabs and GetSpellTabInfo then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, count = GetSpellTabInfo(tab)
            for i = offset + 1, offset + count do
                local kind, id = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
                if kind == "SPELL" then add(id, IsPassiveSpell and IsPassiveSpell(i, BOOKTYPE_SPELL or "spell")) end
            end
        end
    end
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = Entry(e.action) end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

-- Whether the player knows a spell now (any rank of it): the game's own
-- answer when it has one, else its name in the spellbook. A spell the
-- character is too low to have is never "known".
function A.KnownSpell(id, book)
    if not id then return false end
    for _, fn in ipairs({ IsPlayerSpell, IsSpellKnown }) do
        if fn then
            local ok, known = pcall(fn, id)
            if ok and known then return true end
        end
    end
    local name = A.SpellInfo(id)
    if not name then return false end
    book = book or A.SpellbookNames()
    return book[name] ~= nil
end

-- name -> highest known spell ID, from the spellbook
function A.SpellbookNames()
    local out = {}
    for _, e in ipairs(A.SpellbookSpells()) do
        local id = tonumber(e.action:match("^spell:(%d+)$"))
        if id then out[e.label] = id end
    end
    return out
end

-- Usable items: in the bags with a use, and equipped ones with a use
function A.UsableItems()
    local out = {}
    A.EachBagItem(function(id)
        if A.ItemSpell(id) then out[#out + 1] = Entry("item:" .. id) end
    end)
    for _, slot in ipairs({ 13, 14, 6, 10, 15, 2 }) do
        local id = GetInventoryItemID("player", slot)
        if id and A.ItemSpell(id) then out[#out + 1] = Entry("item:" .. id) end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

function A.Macros()
    local out = {}
    if not GetNumMacros then return out end
    local global, perChar = GetNumMacros()
    local function add(i)
        local name = GetMacroInfo(i)
        if name then out[#out + 1] = Entry("macro:" .. name) end
    end
    for i = 1, global do add(i) end
    for i = 1, perChar do add((MAX_ACCOUNT_MACROS or 120) + i) end
    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
    return out
end

A.EMOTES = { "WAVE", "HELLO", "BYE", "THANK", "CHEER", "BOW", "DANCE", "LAUGH", "SALUTE", "APPLAUD",
    "ROAR", "FLEX", "SIT", "SLEEP", "KNEEL", "POINT", "OOM", "HEALME", "HELPME", "FOLLOW", "WAIT",
    "CHARGE", "ATTACKMYTARGET", "INCOMING", "OPENFIRE", "FLEE", "TRAIN", "CHICKEN", "NO", "YES" }

function A.Emotes()
    local out = {}
    for _, token in ipairs(A.EMOTES) do out[#out + 1] = Entry("emote:" .. token) end
    return out
end

function A.Markers()
    local out = {}
    for n = 8, 0, -1 do out[#out + 1] = Entry("marker:" .. n) end
    return out
end

function A.Units()
    local out = { Entry("groupnext"), Entry("groupprev") }
    for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4", "pet", "focus", "targettarget" }) do
        out[#out + 1] = Entry("target:" .. unit)
    end
    return out
end

A.DEFAULT_PHRASES = { "Thanks!", "Ready?", "One sec", "OOM", "Inc!", "Good game", "Sorry!", "On my way", "LF more", "Need a heal" }

function A.Phrases()
    local out = {}
    local p = PF.P()
    for _, text in ipairs((p and p.wheels and p.wheels.phrases) or A.DEFAULT_PHRASES) do
        out[#out + 1] = Entry("say:auto|" .. text)
    end
    return out
end

function A.Specials()
    return { Entry("questitem"), Entry("open") }
end
