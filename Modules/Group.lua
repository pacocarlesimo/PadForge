-- Group targeting for healers. The game lets no addon pick a target by
-- health in combat, so PadForge makes the picking fast instead:
--   * "Next / Previous group member": a secure button steps through the
--     group (you, party, or the raid), skipping the dead and the absent,
--     in combat too
--   * the Group wheel shows each member's health live and marks the one
--     who needs it most: point at it, let go
local _, PF = ...

local M = PF.NewModule("group", {
    title = "Group targeting",
    desc = "Step through your group with one button; the Group wheel shows health and marks who needs healing most.",
    order = 25,
})
PF.Group = M

PF.DB.RegisterDefaults("group", { includeSelf = true, health = true }, function(t)
    t.includeSelf = t.includeSelf ~= false
    t.health = t.health ~= false
    return t
end)
PF.DB.SECTION_LABELS.group = "Group targeting"

local function Section()
    local p = PF.P()
    return p and p.group
end

---------------------------------------------------------------------------
-- Health (insecure: for drawing only)
---------------------------------------------------------------------------
-- pct (0..1) and dead, or nil when the unit isn't there
-- (health can be secret in combat on this client: then it isn't known,
-- and no bar or LOWEST mark is drawn rather than a wrong one)
function M.Health(unit)
    local exists = UnitExists and UnitExists(unit)
    if PF.IsSecret(exists) or not exists then return nil end
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    if PF.IsSecret(dead) then return nil end
    if dead then return 0, true end
    local hp, max = PF.Num(UnitHealth(unit)), PF.Num(UnitHealthMax(unit))
    if not (hp and max and max > 0) then return nil end
    return hp / max, false
end

-- The living unit with the lowest health of a list, under 100%
function M.Lowest(units)
    local best, bestPct
    for _, unit in ipairs(units) do
        local pct, dead = M.Health(unit)
        if pct and not dead and pct < 0.999 and (not bestPct or pct < bestPct) then best, bestPct = unit, pct end
    end
    return best, bestPct
end

---------------------------------------------------------------------------
-- The stepping button: LeftButton next, RightButton previous
---------------------------------------------------------------------------
local cycle = CreateFrame("Button", "PadForgeGroupCycle", UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
cycle:SetSize(1, 1)
cycle:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -50, 50)
cycle:RegisterForClicks("AnyDown")
cycle:SetAttribute("useOnKeyDown", true)

M.CYCLE_SNIPPET = [[
    self:SetAttribute("type", nil)
    local n = self:GetAttribute("pf-n") or 0
    if n < 1 then return false end
    local cur = self:GetAttribute("pf-cur") or 0
    local dir = button == "RightButton" and -1 or 1
    for _ = 1, n do
        cur = (cur - 1 + dir) % n + 1
        local unit = self:GetAttribute("pf-unit-" .. cur)
        if unit and SecureCmdOptionParse("[@" .. unit .. ",exists,nodead] 1; 0") == "1" then
            self:SetAttribute("pf-cur", cur)
            self:SetAttribute("type", "target")
            self:SetAttribute("unit", unit)
            return
        end
    end
    return false
]]
SecureHandlerWrapScript(cycle, "OnClick", cycle, M.CYCLE_SNIPPET)

-- The group's units now (you first when set)
function M.Units()
    local units = {}
    local s = Section()
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do units[#units + 1] = "raid" .. i end
    else
        if not s or s.includeSelf then units[1] = "player" end
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    return units
end

local function Build()
    if PF.InCombat() then return PF.AfterCombat("group", Build) end
    local old = cycle:GetAttribute("pf-n") or 0
    for i = 1, old do cycle:SetAttribute("pf-unit-" .. i, nil) end
    local units = M.running and M.Units() or {}
    for i, unit in ipairs(units) do cycle:SetAttribute("pf-unit-" .. i, unit) end
    cycle:SetAttribute("pf-n", #units)
    cycle:SetAttribute("pf-cur", 0)
end
M.Build = Build

PF.On("GROUP_ROSTER_UPDATE", function() if M.running then Build() end end)
PF.On("PLAYER_ENTERING_WORLD", function() if M.running then Build() end end)

function M.Enable() Build() end
function M.Refresh() Build() end
function M.Disable() Build() end
