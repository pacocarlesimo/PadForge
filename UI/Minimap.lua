-- The minimap button: click to open PadForge, drag it round the minimap's
-- edge to place it. Its place and whether it shows are account-wide.
local _, PF = ...

local MM = {}
PF.MinimapButton = MM

local DEFAULT_ANGLE = 225

local function Settings()
    local g = PF.db and PF.db.global
    if not g then return { angle = DEFAULT_ANGLE, hide = false } end
    g.minimap = type(g.minimap) == "table" and g.minimap or {}
    local m = g.minimap
    m.angle = tonumber(m.angle) or DEFAULT_ANGLE
    m.hide = m.hide == true
    return m
end
MM.Settings = Settings

local button

-- Round minimaps put the button on the circle; square ones on the square
local function Place()
    if not (button and Minimap) then return end
    local m = Settings()
    local a = math.rad(m.angle)
    local x, y = math.cos(a), math.sin(a)
    local w = (Minimap:GetWidth() or 140) / 2 + 10
    local h = (Minimap:GetHeight() or 140) / 2 + 10
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    if square then
        local scale = math.max(math.abs(x), math.abs(y))
        if scale > 0 then x, y = x / scale, y / scale end
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end
MM.Place = Place

local function DragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    Settings().angle = math.floor(math.deg(math.atan2(cy - my, cx - mx)) + 0.5) % 360
    Place()
end

local function Create()
    if button or not Minimap then return end
    -- (a frame of its own, only placed by the minimap: never a child of
    -- the game's frame, whose children the game's code walks)
    button = CreateFrame("Button", "PadForgeMinimapButton", UIParent)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(20)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\Icons\\INV_Gizmo_02")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            if PF.Config then PF.Config.Show("profiles") end
        else
            if PF.Config then PF.Config.Toggle() end
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", DragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
        Place()
    end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(PF.TITLE .. "  |cff999999v" .. PF.version .. "|r")
        GameTooltip:AddLine("Profile: |cffffffff" .. PF.DB.ActiveName() .. "|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffb74dClick|r: open PadForge (/pf)", 1, 1, 1)
        GameTooltip:AddLine("|cffffb74dRight-click|r: profiles", 1, 1, 1)
        GameTooltip:AddLine("|cffffb74dDrag|r: move this button", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function Wanted()
    return not Settings().hide and Minimap and Minimap:IsVisible()
end

function MM.Refresh()
    if not PF.db then return end
    Create()
    if not button then return end
    if Wanted() then
        Place()
        button:Show()
    else
        button:Hide()
    end
end

-- Shown with the minimap (read, never hooked)
local follow = CreateFrame("Frame")
local fWait = 0
follow:SetScript("OnUpdate", function(_, elapsed)
    fWait = fWait - elapsed
    if fWait > 0 or not (button and PF.db) then return end
    fWait = 0.5
    local want = Wanted() and true or false
    if want ~= button:IsShown() then MM.Refresh() end
end)

function MM.SetShown(show)
    Settings().hide = not show
    MM.Refresh()
end

function MM.IsShown()
    return not Settings().hide
end

PF.On("PF_READY", function() MM.Refresh() end)

PF.AddCommand("minimap", function()
    MM.SetShown(not MM.IsShown())
    PF.Print("Minimap button " .. (MM.IsShown() and "shown." or "hidden."))
end, "show or hide the minimap button")
