-- The game side of the simulated client: loads the game's own Lua from a
-- checkout of the WoW Forever UI source (secure handlers and templates,
-- the gamepad binding stack, the gamepad focus manager, the popup handler)
-- and models the rest (crossbar, popups, bags, spells) as small stand-ins
-- that follow that source.
local S = require("sim.wow")
local Docs = require("sim.docs")

local G = {}
local ADDONS

local function LoadGameFile(rel, ns)
    local path = ADDONS .. "/" .. rel
    local chunk, err = loadfile(path)
    if not chunk then error("can't load the game's " .. rel .. ": " .. tostring(err)) end
    local ok, e = xpcall(function() chunk(rel:match("^[^/]+"), ns) end, debug.traceback)
    if not ok then error("the game's " .. rel .. " failed to load in the simulator:\n" .. tostring(e)) end
end

local function Record(name)
    return function(...) S.performed[#S.performed + 1] = { call = name, args = { ... } } end
end

---------------------------------------------------------------------------
-- Data the tests can change
---------------------------------------------------------------------------
G.spells = { [133] = { "Fireball", 135812 }, [116] = { "Frostbolt", 135846 }, [10] = { "Blizzard", 135857 },
    [1459] = { "Arcane Intellect", 135932 }, [2136] = { "Fire Blast", 135807 }, [1953] = { "Blink", 135736 },
    [122] = { "Frost Nova", 135848 }, [999] = { "Swift Mount", 132261 } }
G.book = { 133, 116, 10, 1459 }
G.items = { [5350] = { "Conjured Water", 0, 5 }, [2512] = { "Rough Arrow", 2, 0 }, [858] = { "Lesser Healing Potion", 0, 1 },
    [7500] = { "Strange Book", 12, 0 }, [6948] = { "Hearthstone", 15, 0 } }
G.bags = { [0] = { 5350, 858, 7500, 6948 } }
G.macros = { { "Pull", 136377, "/cast Fireball" } }
G.loaded = {}
G.instance = "none"
G.group = false
G.raid = false
G.class = "MAGE"

local function InstallData()
    local _G = _G
    _G.UnitName = function(u)
        local unit = S.units[u]
        if not unit then return nil end
        if G.secretNames then return S.Secret(unit.name or u) end
        return unit.name or u, nil
    end
    _G.GetRealmName = function() return "Realm" end
    _G.GetBuildInfo = function() return "1.60.1", "70888", "Nov 10 2026", 16001 end
    _G.UnitClass = function() return "Mage", G.class end
    _G.UnitExists = function(u) return S.units[u] ~= nil end
    _G.UnitIsDead = function(u) return S.units[u] ~= nil and S.units[u].dead == true end
    _G.UnitIsGhost = function() return false end
    _G.UnitIsDeadOrGhost = _G.UnitIsDead
    _G.UnitCanAttack = function(_, u) return S.units[u] ~= nil and S.units[u].harm == true end
    _G.UnitCanAssist = function(_, u) return S.units[u] ~= nil and not S.units[u].harm end
    _G.UnitAffectingCombat = function() return S.combat end
    _G.UnitHealth = function(u)
        local hp = S.units[u] and S.units[u].hp or 0
        return G.secretHealth and S.Secret(hp) or hp
    end
    _G.UnitHealthMax = function(u)
        local max = S.units[u] and S.units[u].max or 0
        return G.secretHealth and S.Secret(max) or max
    end
    _G.IsInRaid = function() return G.raid end
    _G.IsInGroup = function() return G.group or G.raid end
    _G.GetNumGroupMembers = function() return G.raid and G.raidSize or (G.group and 5 or 0) end
    _G.IsInInstance = function() return G.instance ~= "none", G.instance end
    _G.GetActiveTalentGroup = function() return 1 end

    _G.C_Timer = {
        After = function(d, fn) S.timers[#S.timers + 1] = { at = S.now + d, fn = fn, noArgs = true } end,
        NewTimer = function(d, fn)
            local t = { at = S.now + d, fn = fn, Cancel = function(self) self.cancelled = true end, IsCancelled = function(self) return self.cancelled end }
            S.timers[#S.timers + 1] = t
            return t
        end,
        NewTicker = function(d, fn)
            local t = { at = S.now + d, every = d, fn = fn, Cancel = function(self) self.cancelled = true end }
            S.timers[#S.timers + 1] = t
            return t
        end,
    }
    _G.C_AddOns = {
        GetAddOnMetadata = function(_, field) return field == "Version" and "sim" or nil end,
        IsAddOnLoaded = function(n) return G.loaded[n] or false end,
    }
    _G.C_CVar = {
        GetCVar = function(n) return S.cvars[n] end,
        GetCVarDefault = function(n) return G.cvarDefaults[n] end,
        SetCVar = function(n, v)
            if S.cvars[n] == nil then return false end
            S.cvars[n] = tostring(v)
            G.cvarWrites[#G.cvarWrites + 1] = { name = n, value = tostring(v), by = S.taint or "game" }
            S.Fire("CVAR_UPDATE", n, tostring(v))
            return true
        end,
    }
    _G.SetCVar = _G.C_CVar.SetCVar
    _G.GetCVarDefault = _G.C_CVar.GetCVarDefault
    -- (C_Console and C_GamePad.StickConfigNameToIndex are not on this
    -- client: its documentation doesn't list them)
    _G.C_GamePad = {
        IsEnabled = function() return true end,
        GetActiveDeviceID = function() return S.padConnected and 1 or nil end,
        GetDeviceMappedState = function() return S.padConnected and S.pad or nil end,
        ButtonBindingToIndex = function(b) return S.padIndex[b] end,
        StickIndexToConfigName = function(i) return S.stickNames[i] end,
        SetVibration = Record("C_GamePad.SetVibration"),
        StopVibration = Record("C_GamePad.StopVibration"),
    }
    _G.C_Texture = { GetAtlasInfo = function(name) return type(name) == "string" and {} or nil end }
    _G.C_Spell = {
        GetSpellInfo = function(id)
            local s = G.spells[id]
            if s then return { name = s[1], iconID = s[2], spellID = id } end
        end,
        GetSpellCooldown = function()
            if G.secretCooldowns then return { startTime = S.Secret(0), duration = S.Secret(0) } end
            return { startTime = 0, duration = 0 }
        end,
        IsPressHoldReleaseSpell = function() return false end,
        IsSpellHarmful = function() return false end,
        IsSpellHelpful = function() return false end,
    }
    _G.C_SpellBook = {
        GetNumSpellBookSkillLines = function() return 1 end,
        GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #G.book } end,
        GetSpellBookItemInfo = function(i)
            local id = G.book[i]
            if id then return { itemType = 1, spellID = id, actionID = id, isPassive = false } end
        end,
    }
    _G.IsSpellKnown = function(id)
        for _, known in ipairs(G.book) do if known == id then return true end end
        return false
    end
    _G.Enum = _G.Enum or {}
    _G.Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
    _G.Enum.SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 }
    _G.Enum.ItemClass = { Consumable = 0, Questitem = 12, Miscellaneous = 15 }
    _G.C_Item = {
        GetItemInfo = function(id) return G.items[id] and G.items[id][1] end,
        GetItemIconByID = function() return 134400 end,
        GetItemInfoInstant = function(id)
            local i = G.items[id]
            if i then return id, nil, nil, "", 134400, i[2], i[3] end
        end,
        GetItemSpell = function(id) if G.items[id] and id ~= 2512 then return "Use", 1 end end,
        GetItemCount = function() return 3 end,
        IsEquippableItem = function() return false end,
        IsEquippedItem = function() return false end,
        IsHarmfulItem = function() return false end,
        IsHelpfulItem = function() return false end,
    }
    _G.C_Container = {
        GetContainerNumSlots = function(bag) return G.bags[bag] and #G.bags[bag] or 0 end,
        GetContainerItemInfo = function(bag, slot)
            local id = G.bags[bag] and G.bags[bag][slot]
            if id then return { itemID = id } end
        end,
        GetContainerItemQuestInfo = function(bag, slot)
            local id = G.bags[bag] and G.bags[bag][slot]
            return { isQuestItem = id == 7500, questID = id == 7500 and 123 or nil, isActive = false }
        end,
        GetItemCooldown = function() return 0, 0, 1 end,
    }
    _G.GetInventoryItemID = function() return nil end
    _G.NUM_BAG_SLOTS = 4
    _G.MAX_ACCOUNT_MACROS = 120
    _G.GetNumMacros = function() return #G.macros, 0 end
    _G.GetMacroInfo = function(i)
        for index, m in ipairs(G.macros) do
            if i == index or i == m[1] then return m[1], m[2], m[3] end
        end
    end
    _G.GetMacroIndexByName = function(name)
        for index, m in ipairs(G.macros) do if m[1] == name then return index end end
        return 0
    end
    _G.C_Macro = { RunMacroText = function(text) S.RunMacroText(text) end }
    _G.GetCursorPosition = function() return 0, 0 end
    _G.GetCursorInfo = function() return nil end
    _G.GetPhysicalScreenSize = function() return 1920, 1080 end
    _G.GetMouseFoci = function() return {} end
    _G.EnumerateFrames = function(prev)
        if not prev then return S.frames[1] end
        for i, f in ipairs(S.frames) do if f[0] == prev[0] then return S.frames[i + 1] end end
    end
    _G.PlaySound = function() end
    _G.SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
    _G.SlashCmdList = {}
    _G.AcceptGroup = Record("AcceptGroup")
    _G.DeclineGroup = Record("DeclineGroup")
    _G.RepopMe = Record("RepopMe")
    _G.AcceptResurrect = Record("AcceptResurrect")
    _G.DeclineResurrect = Record("DeclineResurrect")
    _G.ConfirmReadyCheck = Record("ConfirmReadyCheck")
    _G.C_SummonInfo = { ConfirmSummon = Record("ConfirmSummon"), CancelSummon = Record("CancelSummon") }
    _G.AcceptDuel = Record("AcceptDuel")
    _G.CancelDuel = Record("CancelDuel")
end

---------------------------------------------------------------------------
-- The game's own Lua
---------------------------------------------------------------------------
local function InstallGameStubs()
    local _G = _G
    local function Namespace(names)
        local t = {}
        for _, n in ipairs(names) do t[n] = function() end end
        return t
    end
    -- (filled from the documentation in Boot)
    for _, ns in ipairs({ "C_ActionBar", "C_AssistedCombat", "C_TransmogOutfitInfo", "C_ClickBindings", "C_EquipmentSet",
        "C_PaperDollInfo", "C_Housing" }) do
        _G[ns] = Namespace({})
    end
    _G.C_Widget = { IsFrameWidget = function(f) return type(f) == "table" and S.state[f[0]] ~= nil end }
    for _, n in ipairs({ "FindSpellBookSlotBySpellID", "GetMultiCastTotemSpells", "UnitTargetsVehicleInRaidUI", "GetActionInfo",
        "GetShapeshiftForm", "IsStealthed", "UnitPlayerOrPetInParty", "UnitPlayerOrPetInRaid", "IsRightAltKeyDown",
        "IsLeftAltKeyDown", "IsRightControlKeyDown", "IsLeftControlKeyDown", "IsLeftShiftKeyDown", "IsRightShiftKeyDown",
        "IsModifierKeyDown", "GetMouseButtonClicked", "IsMounted", "IsSwimming", "IsSubmerged", "IsFlying", "IsFlyableArea",
        "IsAdvancedFlyableArea", "IsDrivableArea", "IsIndoors", "IsOutdoors", "CanExitVehicle", "UnitChannelInfo",
        "UnitCreatureFamily", "UnitHasVehicleUI", "SpellStopTargeting", "RegisterUnitWatch", "UnregisterUnitWatch",
        "InGlue", "GetRaidTargetIndex", "DisplayInterfaceActionBlockedMessage" }) do
        _G[n] = _G[n] or function() end
    end
    _G.NUM_ACTIONBAR_BUTTONS = 12
    _G.ATTRIBUTE_NOOP = ""
    _G.ERROR_NO_FRAME_TO_FOCUS = "No frame to focus"
    _G.GetModifiedClick = function() return "NONE" end
    _G.StringToBoolean = function(s, default)
        s = (s or ""):lower()
        if s == "true" or s == "1" then return true end
        if s == "false" or s == "0" then return false end
        return default
    end
    _G.UIErrorsFrame = { AddExternalErrorMessage = function(_, msg) S.chat[#S.chat + 1] = "UIERROR: " .. tostring(msg) end }
    _G.InputUtil = setmetatable({
        IsGamepadUIEnabled = function() return true end,
        RegisterGamepadInit = function(_, fn) G.gamepadInit[#G.gamepadInit + 1] = fn end,
    }, { __index = function() return function() end end })
    -- A callback registry like the game's (EventRegistry, PopupEventManager)
    local function Registry()
        local r = { callbacks = {} }
        function r:RegisterCallback(event, fn, owner)
            self.callbacks[event] = self.callbacks[event] or {}
            table.insert(self.callbacks[event], { fn = fn, owner = owner })
        end
        function r:UnregisterCallback(event, owner)
            local list = self.callbacks[event] or {}
            for i = #list, 1, -1 do if list[i].owner == owner then table.remove(list, i) end end
        end
        function r:TriggerEvent(event, ...)
            for _, cb in ipairs(self.callbacks[event] or {}) do cb.fn(cb.owner, ...) end
        end
        function r:RegisterFrameEventAndCallback() end
        return r
    end
    _G.EventRegistry = Registry()
    _G.PopupEventManager = Registry()
    _G.SmartNavigation = setmetatable({}, { __index = function() return function() end end })
    _G.GamepadRadial = setmetatable({}, { __index = function() return function() end end })
    _G.RaidTargetingFreeSelection = { SetActive = function() end }
    _G.Menu = { IsMenuProxy = function() return false end }
    _G.GetScaledCenter = function(frame) return frame:GetCenter() end
    _G.GetAppropriateTopLevelParent = function() return UIParent end
    _G.HideUIPanel = function(frame) G.ClosePanel(frame) end
    _G.StaticPopup_EscapePressed = function() end
    -- (Blizzard_GamepadSmartNavigation's SecureHelper: calls straight through)
    local SecureHelper = {
        SecureCallOptionalFunction = function(obj, name, ...)
            if obj and type(obj[name]) == "function" then return obj[name](...) end
        end,
        WrapFunction = function(_, fn) return fn end,
    }
    _G.import = function(name)
        if name:find("SecureHelper") then return SecureHelper end
        error("import of " .. name .. " is not modelled")
    end
end

local function LoadGameLua()
    local secure = {}
    for _, f in ipairs({ "RestrictedInfrastructure", "RestrictedEnvironment", "RestrictedExecution", "RestrictedFrames",
        "SecureHandlers", "SecureStateDriver" }) do
        LoadGameFile("Blizzard_RestrictedAddOnEnvironment/" .. f .. ".lua", secure)
    end
    LoadGameFile("Blizzard_FrameXML/SecureTemplates.lua", {})
    LoadGameFile("Blizzard_SharedXML/Shared/GamepadConstants.lua", {})
    local shared = {}
    LoadGameFile("Blizzard_GamepadSharedUtility/GamepadSharedUtility.lua", shared)
    GamepadSharedUtility.CreateDownClickButton = function(name, parent)
        local b = CreateFrame("Button", name, parent)
        b:RegisterForClicks("AnyDown")
        return b
    end
    GamepadMode.AddGamepadIconToButton = function(button) return CreateFrame("Frame", nil, button) end
    GamepadMode.SetGamepadIconShown = function(icon, shown) if icon then icon:SetShown(shown) end end
    for _, f in ipairs({ "InputButtonBinding", "InputActionBinding", "InputFunctionBinding", "InputAxisBinding", "InputBindingSet",
        "InputBindingManager", "BindingSetFactory" }) do
        LoadGameFile("Blizzard_GamepadSharedUtility/InputBindingStack/" .. f .. ".lua", shared)
    end
    LoadGameFile("Blizzard_StaticPopup/StaticPopupGamepad.lua", {})
    LoadGameFile("Blizzard_GamepadSharedUtility/FrameControlsManager.lua", shared)
    for _, fn in ipairs(G.gamepadInit) do fn() end
end

---------------------------------------------------------------------------
-- Popups: StaticPopup1-4, as GameDialog.xml builds them
---------------------------------------------------------------------------
G.dialogs = {
    PARTY_INVITE = { skipGamepadAutoFocus = 1, OnAccept = "AcceptGroup", OnCancel = "DeclineGroup" },
    RESURRECT = { skipGamepadAutoFocus = 1, OnAccept = "AcceptResurrect", OnCancel = "DeclineResurrect" },
    DEATH = { skipGamepadAutoFocus = 1, OnAccept = "RepopMe" },
    CONFIRM_SUMMON = { skipGamepadAutoFocus = 1, OnAccept = "ConfirmSummon", OnCancel = "CancelSummon" },
    DUEL_REQUESTED = { skipGamepadAutoFocus = 1, OnAccept = "AcceptDuel", OnCancel = "CancelDuel" },
    LOOT_BIND = { OnAccept = "ConfirmLootSlot" },
    DELETE_ITEM = { OnAccept = "DeleteCursorItem" },
}

local function BuildPopups()
    for i = 1, 4 do
        local f = CreateFrame("Frame", "StaticPopup" .. i, UIParent)
        f:Hide()
        f.ButtonContainer = CreateFrame("Frame", nil, f)
        f.ButtonContainer.Buttons = {}
        for n = 1, 4 do
            local b = CreateFrame("Button", "StaticPopup" .. i .. "Button" .. n, f.ButtonContainer)
            b:RegisterForClicks("LeftButtonUp")
            b:SetScript("OnClick", function() G.AnswerPopup(f, n) end)
            f.ButtonContainer["Button" .. n] = b
            f.ButtonContainer.Buttons[n] = b
        end
        f.ExtraButton = CreateFrame("Button", "StaticPopup" .. i .. "ExtraButton", f)
        f.Text = f:CreateFontString("StaticPopup" .. i .. "Text")
        f.GetButton = function(self, n) return self.ButtonContainer.Buttons[n] end
        f.GetButton1 = function(self) return self:GetButton(1) end
        f.GetButton2 = function(self) return self:GetButton(2) end
        f.GetButton3 = function(self) return self:GetButton(3) end
        f.GetButton4 = function(self) return self:GetButton(4) end
        f.GetExtraButton = function(self) return self.ExtraButton end
        f.OnGainGamepadFocus = function() end
        f.OnLoseGamepadFocus = function() end
    end
end

-- The game showing a popup (StaticPopup_Show)
function G.ShowPopup(which)
    local info = G.dialogs[which]
    if not info then error("no dialog " .. tostring(which)) end
    return S.AsGame(function()
        for i = 1, 4 do
            local f = _G["StaticPopup" .. i]
            if not f:IsShown() then
                f.which = which
                f.dialogInfo = info
                f.skipGamepadAutoFocus = info.skipGamepadAutoFocus
                f.Text:SetText(which)
                f:GetButton2():SetShown(info.OnCancel ~= nil)
                f:GetButton3():Hide()
                f:GetButton4():Hide()
                f.ExtraButton:Hide()
                f:Show()
                PopupEventManager:TriggerEvent("PopupOpened", f)
                return f
            end
        end
    end)
end

function G.HidePopup(f)
    if not f:IsShown() then return end
    -- (hidden by addon code: the game's popup and focus code runs tainted,
    -- which is what gets the next protected call blocked)
    if S.taint then S.Violation("addon code closed the game's " .. tostring(f.which) .. " popup") end
    f:Hide()
    PopupEventManager:TriggerEvent("PopupClosed", f)
    f.which = nil
end

function G.AnswerPopup(f, n)
    local info = f.dialogInfo
    local what = n == 1 and info.OnAccept or info.OnCancel
    S.performed[#S.performed + 1] = { popup = f.which, answer = n, call = what, tainted = S.taint ~= nil }
    G.HidePopup(f)
end

---------------------------------------------------------------------------
-- Game windows (bags, the map...): they go through the focus manager
---------------------------------------------------------------------------
function G.OpenPanel(frame)
    S.AsGame(function()
        frame:Show()
        GamepadMode.FrameControlsManager:FrameShown(frame)
    end)
end

function G.ClosePanel(frame)
    if S.taint then S.Violation("addon code closed a game window") end
    frame:Hide()
    GamepadMode.FrameControlsManager:FrameHidden(frame)
end

function G.Manager() return GamepadMode.FrameControlsManager end

-- Whether the player's own controls are live (the game's own test)
function G.CoreInput()
    return S.AsGame(function() return GamepadSharedUtility.InputBindingManager:IsOnlyCoreBindingSetActive() end)
end

---------------------------------------------------------------------------
-- The crossbar (Blizzard_GamepadActionBars), following MainActionBarFrame
-- and PageUnit: four bars of eight buttons, the active one picked by the
-- triggers, presses sent down and up to the button that took the down
---------------------------------------------------------------------------
local function BuildCrossbar()
    local frame = CreateFrame("Frame", "GamepadMainActionBarFrame", UIParent)
    frame.PageUnit = CreateFrame("Frame", "GamepadMainActionBarFramePageUnit", frame)
    local bars = {}
    for _, name in ipairs({ "topBar", "leftBar", "rightBar", "bottomBar" }) do
        local bar = CreateFrame("Frame", "GamepadMainActionBarFramePageUnit_" .. name, frame.PageUnit, "SecureFrameTemplate")
        bar.Left, bar.Right = CreateFrame("Frame", nil, bar), CreateFrame("Frame", nil, bar)
        for i = 1, 8 do
            local side = i <= 4 and bar.Left or bar.Right
            local n = i <= 4 and i or i - 4
            local b = CreateFrame("CheckButton", bar:GetName() .. (i <= 4 and "L" or "R") .. "ActionButton" .. n, side, "SecureFrameTemplate")
            b:RegisterForClicks("AnyUp", "AnyDown")
            b:SetAttribute("useOnKeyDown", true)
            b:SetScript("OnClick", function(_, _, down)
                if not S.Protected("UseAction()") then return end
                if name == "topBar" and i >= 5 then
                    -- (the top bar's face slots are the game's own actions)
                    local role = ({ "INTERACT", "INSPECT", "BACK", "JUMP" })[n]
                    if down then S.performed[#S.performed + 1] = { command = role } end
                elseif down then
                    S.performed[#S.performed + 1] = { action = name .. ":" .. i }
                end
            end)
            side["ActionButton" .. n] = b
            bar[i] = b
        end
        bars[name] = bar
    end
    frame.PageUnit.actionBars = bars
    frame.buttonOwners = {}
    function frame.PageUnit:GetActiveBar()
        if not G.CoreInput() then return bars.topBar end
        local lt, rt = S.held.PADLTRIGGER, S.held.PADRTRIGGER
        if lt and rt then return bars.bottomBar end
        if lt then return bars.leftBar end
        if rt then return bars.rightBar end
        return bars.topBar
    end
    function frame:PressActionButton(index, button, down)
        button = button or "LeftButton"
        local owner = self.buttonOwners[index]
        if down then
            local b = self.PageUnit:GetActiveBar()[index]
            if owner then self:PressActionButton(index, button, false) end
            self.buttonOwners[index] = b
            b:Click(button, true)
        elseif owner then
            self.buttonOwners[index] = nil
            owner:Click(button, false)
        end
    end
    for n = 1, 8 do
        S.commands["GAMEPADACTIONBUTTON" .. n] = function(down) frame:PressActionButton(n, "LeftButton", down) end
    end
    S.commands.TOGGLEUIFOCUS = function(down)
        if down then
            local m = GamepadMode.FrameControlsManager
            m:SetUIFocusState(not m.isUIFocused)
        end
    end
    S.commands.GAMEPADLEFTMOD = function() end
    S.commands.GAMEPADRIGHTMOD = function() end
end

-- The client's own gamepad bindings (Blizzard_GamepadActionBars' comment:
-- 1-4 the D-pad left, up, right, down; 5-8 the face left, top, right, bottom)
local KEYBINDS = {
    PADDLEFT = "GAMEPADACTIONBUTTON1", PADDUP = "GAMEPADACTIONBUTTON2", PADDRIGHT = "GAMEPADACTIONBUTTON3", PADDDOWN = "GAMEPADACTIONBUTTON4",
    PAD3 = "GAMEPADACTIONBUTTON5", PAD4 = "GAMEPADACTIONBUTTON6", PAD2 = "GAMEPADACTIONBUTTON7", PAD1 = "GAMEPADACTIONBUTTON8",
    PADLTRIGGER = "GAMEPADLEFTMOD", PADRTRIGGER = "GAMEPADRIGHTMOD", PADBACK = "TOGGLEUIFOCUS", PADFORWARD = "OPENRADIAL",
    PADRSTICK = "TOGGLEPINGSYSTEM", PADLSTICK = "TOGGLEAUTORUN",
}

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------
function G.Boot(root)
    ADDONS = root .. "/Interface/AddOns"
    G.root = root
    G.gamepadInit = {}
    G.cvarWrites = {}
    G.cvarDefaults = { GamePadRunThreshold = "0.5", GamePadCameraYawSpeed = "1" }
    S.cvars = { ActionButtonUseKeyDown = "1", ActionButtonUseKeyHeldSpell = "0", GamePadRunThreshold = "0.5", GamePadCameraYawSpeed = "1" }
    S.BuildWidgets(Docs.Load(root))
    -- Font objects the client defines (CreateFontString's third argument)
    S.fonts = {}
    local p = io.popen('grep -rhoE "<Font(Family)? name=\\"[A-Za-z0-9_]+\\"" "' .. ADDONS .. '" --include=*.xml 2>/dev/null')
    if p then
        for line in p:lines() do S.fonts[line:match('name="([^"]+)"')] = true end
        p:close()
    end
    S.InstallBase()
    InstallData()
    InstallGameStubs()
    for key, cmd in pairs(KEYBINDS) do S.keybinds[key] = cmd end
    -- Every function the documentation lists for a namespace exists (as a
    -- no-op where the simulator has nothing to say); nothing else does
    for ns, fns in pairs(S.docs.namespace) do
        local t = rawget(_G, ns)
        if type(t) == "table" and ns:find("^C_") then
            for name in pairs(fns) do
                if t[name] == nil then t[name] = function() end end
            end
            for name in pairs(t) do
                if not fns[name] then error("the simulator defines " .. ns .. "." .. name .. ", which this client doesn't document") end
            end
        end
    end
    S.taint = nil
    _G.UIParent = CreateFrame("Frame", "UIParent")
    _G.WorldFrame = CreateFrame("Frame", "WorldFrame")
    _G.Minimap = CreateFrame("Frame", "Minimap", UIParent)
    -- (the tooltip's own methods aren't in the documentation: not checked)
    _G.GameTooltip = setmetatable({}, { __index = function() return function() end end })
    -- (parenting to UIParent / reading it is what every addon does)
    S.St(UIParent).shared = true
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) S.chat[#S.chat + 1] = tostring(msg) end }
    LoadGameLua()
    BuildPopups()
    BuildCrossbar()
    _G.ContainerFrameCombinedBags = CreateFrame("Frame", "ContainerFrameCombinedBags", UIParent)
    ContainerFrameCombinedBags:Hide()
    _G.ReadyCheckFrame = CreateFrame("Frame", "ReadyCheckFrame", UIParent)
    ReadyCheckFrame:Hide()
    CreateFrame("Button", "ReadyCheckFrameYesButton", ReadyCheckFrame)
    CreateFrame("Button", "ReadyCheckFrameNoButton", ReadyCheckFrame)
    -- Game functions an addon must not call (it would run the game's
    -- gamepad code tainted): calling one from addon code is recorded
    local function Guard(tbl, label)
        for k, v in pairs(tbl) do
            if type(v) == "function" then
                tbl[k] = function(...)
                    if S.taint then S.Violation("addon code called the game's " .. label .. "." .. tostring(k) .. "()") end
                    return v(...)
                end
            end
        end
    end
    Guard(GamepadMode.FrameControlsManager, "GamepadMode.FrameControlsManager")
    Guard(GamepadSharedUtility.InputBindingManager, "GamepadSharedUtility.InputBindingManager")
    Guard(GamepadMode, "GamepadMode")
end

-- Loads an addon from its .toc, as the client does: every file gets the
-- addon's name and one shared table, and runs as addon (tainted) code
function G.LoadAddon(dir, name)
    local ns = {}
    S.addonName = name
    S.addonEnv = setmetatable({}, { __index = _G, __newindex = function(_, k, v) rawset(_G, k, v) end })
    local files = {}
    for line in io.lines(dir .. "/" .. name .. ".toc") do
        line = line:gsub("\r", "")
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = (line:gsub("\\", "/")) end
    end
    for _, file in ipairs(files) do
        local chunk, err = loadfile(dir .. "/" .. file)
        if not chunk then error(err) end
        setfenv(chunk, S.addonEnv)
        S.Call(chunk, name, ns)
    end
    S.Fire("ADDON_LOADED", name)
    S.Fire("PLAYER_LOGIN")
    S.Fire("PLAYER_ENTERING_WORLD", true, false)
    return ns
end

return G
