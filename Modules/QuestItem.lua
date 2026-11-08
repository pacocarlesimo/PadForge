-- Quest item: players can't use quest-starting or quest objective items
-- from the bags with the pad (forum report). One secure button always
-- holds the best usable quest item; any press or wheel slot set to "Quest
-- item" runs it. A small icon shows which item it is and the press that
-- uses it. The item can only change out of combat; loot from a fight is
-- picked up as it ends.
local _, PF = ...
local A, Pad = PF.Actions, PF.Pad

local M = PF.NewModule("questitem", {
    title = "Quest item",
    desc = "One press (or wheel slot) always uses the right quest item.",
    order = 20,
})
PF.QuestItem = M

PF.DB.RegisterDefaults("questitem", { showIcon = true, x = 0, y = 210, skip = {} })

local QUEST_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12

local button = CreateFrame("Button", "PadForgeQuestItemButton", UIParent, "SecureActionButtonTemplate")
button:SetSize(1, 1)
button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -50, 50)
button:RegisterForClicks("AnyDown", "AnyUp")
-- (reached by "/click PadForgeQuestItemButton LeftButton true": the press)
button:SetAttribute("useOnKeyDown", true)
button:SetAttribute("type", "item")

local current
local firstSeen = {}   -- [itemID] = time it was first in the bags this session
local loginTime = GetTime()

function M.Current() return current end

-- Every usable quest item in the bags: { id, quest = bool, seen }
function M.Candidates()
    local list = {}
    local section = PF.P() and PF.P().questitem
    local skip = section and section.skip or {}
    A.EachBagItem(function(id, bag, slot)
        if skip[id] or not A.ItemSpell(id) then return end
        local classID = A.ItemClass(id)
        local isQuest, questID = A.SlotQuest(bag, slot)
        if classID == QUEST_CLASS or isQuest or questID then
            firstSeen[id] = firstSeen[id] or GetTime()
            list[#list + 1] = { id = id, starts = questID ~= nil and questID ~= 0, seen = firstSeen[id] }
        end
    end)
    -- Newest first (the item you just looted is the one you want); an item
    -- that starts a quest before one that doesn't
    table.sort(list, function(a, b)
        if a.seen ~= b.seen then return a.seen > b.seen end
        if a.starts ~= b.starts then return a.starts end
        return a.id < b.id
    end)
    return list
end

local function Pick()
    local list = M.Candidates()
    local best = list[1] and list[1].id or nil
    if best == current then return end
    current = best
    button:SetAttribute("item", best and ("item:" .. best) or nil)
    PF.Fire("PF_QUESTITEM_CHANGED", best)
end

function M.Update()
    if not M.running then return end
    PF.AfterCombat("questitem", Pick)
end

-- Never use this item (cycles to the next); reset with M.ClearSkips
function M.Skip(id)
    local section = PF.P().questitem
    if id then section.skip[id] = true end
    M.Update()
end

function M.ClearSkips()
    wipe(PF.P().questitem.skip)
    M.Update()
end

---------------------------------------------------------------------------
-- The icon
---------------------------------------------------------------------------
local icon = CreateFrame("Frame", "PadForgeQuestItemIcon", UIParent)
icon:SetSize(44, 44)
icon:SetFrameStrata("MEDIUM")
icon:Hide()
icon.tex = icon:CreateTexture(nil, "ARTWORK")
icon.tex:SetAllPoints()
icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
icon.border = icon:CreateTexture(nil, "OVERLAY")
icon.border:SetPoint("TOPLEFT", -3, 3)
icon.border:SetPoint("BOTTOMRIGHT", 3, -3)
icon.border:SetColorTexture(1, 0.82, 0, 0.35)
icon.border:SetDrawLayer("BACKGROUND")
icon.glyph = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
icon.glyph:SetPoint("TOP", icon, "BOTTOM", 0, -3)
icon.count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
icon.count:SetPoint("BOTTOMRIGHT", -2, 2)
icon.cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
icon.cd:SetAllPoints()

-- The press that runs "questitem", for the label
local function BoundSpec()
    local p = PF.P()
    for key, e in pairs(p.buttons.keys) do
        for layer, action in pairs(e.layers) do
            if action == "questitem" and e.mode ~= "game" then return Pad.Spec(layer, key) end
        end
    end
end

function M.RefreshIcon()
    local section = PF.P() and PF.P().questitem
    -- (only once a button uses it: an icon nobody can press is clutter)
    local spec = BoundSpec()
    if not (M.running and section and section.showIcon and current and spec) then
        icon:Hide()
        return
    end
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", UIParent, "CENTER", section.x or 0, section.y or 210)
    local _, tex = A.ItemInfo(current)
    icon.tex:SetTexture(tex or 133469)
    local count = PF.Num(A.ItemCount(current))
    icon.count:SetText(count and count > 1 and count or "")
    icon.glyph:SetText(Pad.SpecText(spec, 14))
    local startFn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if startFn then
        local start, duration = startFn(current)
        start, duration = PF.Num(start), PF.Num(duration)
        if start and duration and duration > 1.5 then icon.cd:SetCooldown(start, duration) else icon.cd:Clear() end
    end
    icon:Show()
end

PF.On("PF_QUESTITEM_CHANGED", function() M.RefreshIcon() end)
PF.On("PF_PROFILE_CHANGED", function() C_Timer.After(0, M.RefreshIcon) end)
PF.On("PF_PAD_STYLE", function() M.RefreshIcon() end)
PF.On("PF_BINDS_APPLIED", function() M.RefreshIcon() end)

for _, event in ipairs({ "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "UNIT_QUEST_LOG_CHANGED" }) do
    PF.On(event, function() M.Update() end)
end
PF.On("BAG_UPDATE_COOLDOWN", function() if icon:IsShown() then M.RefreshIcon() end end)

function M.Enable()
    -- (items already in the bags at login count as old)
    A.EachBagItem(function(id) firstSeen[id] = firstSeen[id] or loginTime - 1 end)
    M.Update()
end

function M.Refresh()
    current = nil
    Pick()
    M.RefreshIcon()
end

function M.Disable()
    icon:Hide()
end

PF.AddCommand("questitem", function(rest)
    if rest == "skip" then
        M.Skip(current)
        PF.Print("Skipping that item. /pf questitem reset to bring skipped items back.")
    elseif rest == "reset" then
        M.ClearSkips()
        PF.Print("Skipped quest items cleared.")
    else
        local list = M.Candidates()
        PF.Print("Quest items: " .. (#list == 0 and "none" or ""))
        for i, c in ipairs(list) do DEFAULT_CHAT_FRAME:AddMessage("  " .. i .. ". " .. (A.ItemInfo(c.id) or c.id) .. (i == 1 and " (used)" or "")) end
    end
end, "[skip|reset]: list quest items, skip the current one")

-- Open button (an action "open" clicks it)
local open = CreateFrame("Button", "PadForgeOpenButton", UIParent)
open:SetScript("OnClick", function() if PF.Config then PF.Config.Toggle() end end)
