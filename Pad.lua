-- The controller in hand: button names and glyphs per style, the pad's
-- live state for our own windows, and how a press (a "spec") is written.
--
-- Buttons are named by place, as the game binds them: PAD1 bottom face
-- (A / Cross), PAD2 right (B / Circle), PAD3 left (X / Square), PAD4 top
-- (Y / Triangle). The glyph atlases are the game's own (the same lists
-- Improved Forever ships, MIT: see LICENSE-ThirdParty.md).
--
-- A spec is "KEY" or "LAYER:KEY" where LAYER is LT, RT or LTRT (the
-- triggers held, as Forever's crossbar reads them): "LT:PADPADDLE1".
local _, PF = ...

local Pad = {}
PF.Pad = Pad

Pad.STYLES = { "auto", "Shapes", "Letters", "Reverse" }
Pad.STYLE_LABELS = { auto = "Automatic", Shapes = "PlayStation", Letters = "Xbox", Reverse = "Nintendo Switch" }

-- Glyph keys of the game's button names
local GLYPH_KEY = {
    PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y",
    PADLSHOULDER = "LB", PADRSHOULDER = "RB", PADLTRIGGER = "LT", PADRTRIGGER = "RT",
    PADLSTICK = "LS", PADRSTICK = "RS",
    PADDUP = "DPAD_UP", PADDDOWN = "DPAD_DOWN", PADDLEFT = "DPAD_LEFT", PADDRIGHT = "DPAD_RIGHT",
    PADBACK = "BACK", PADFORWARD = "START", PADSOCIAL = "SHARE", PADSYSTEM = "HOME",
    PADPADDLE1 = "PADDLE1", PADPADDLE2 = "PADDLE2", PADPADDLE3 = "PADDLE3", PADPADDLE4 = "PADDLE4",
}
Pad.GLYPH_KEY = GLYPH_KEY

local ATLAS = {
    Shapes = {
        A = { "gamepad-ps-buttoncrox-normal", "Gamepad_Shp_Cross_64" },
        B = { "gamepad-ps-buttoncircle-normal", "Gamepad_Shp_Circle_64" },
        X = { "gamepad-ps-buttonsquare-normal", "Gamepad_Shp_Square_64" },
        Y = { "gamepad-ps-buttontriangle-normal", "Gamepad_Shp_Triangle_64" },
        LB = { "gamepad-ps-triggerl1-normal", "Gamepad_Shp_LShoulder_64" },
        RB = { "gamepad-ps-triggerr1-normal", "Gamepad_Shp_RShoulder_64" },
        LT = { "gamepad-ps-triggerl2-normal", "Gamepad_Shp_LTrigger_64" },
        RT = { "gamepad-ps-triggerr2-normal", "Gamepad_Shp_RTrigger_64" },
        LS = { "gamepad-ps-stickl3-normal", "Gamepad_Shp_LStickIn_64" },
        RS = { "gamepad-ps-stickr3-normal", "Gamepad_Shp_RStickIn_64" },
        DPAD_UP = { "gamepad-ps-dpadup-normal", "Gamepad_Shp_Up_64" },
        DPAD_DOWN = { "gamepad-ps-dpaddown-normal", "Gamepad_Shp_Down_64" },
        DPAD_LEFT = { "gamepad-ps-dpadleft-normal", "Gamepad_Shp_Left_64" },
        DPAD_RIGHT = { "gamepad-ps-dpadright-normal", "Gamepad_Shp_Right_64" },
        BACK = { "gamepad-ps-touchpad-normal", "Gamepad_Shp_TouchpadL_64" },
        START = { "gamepad-ps-options-normal", "Gamepad_Shp_Menu_64" },
        SHARE = { "gamepad-ps-create-normal", "gamepad-ps-share-normal", "Gamepad_Shp_Share_64" },
        HOME = { "gamepad-ps-pslogo-normal", "Gamepad_Shp_System_64" },
    },
    Letters = {
        A = { "gamepad-xbox1-buttona-normal", "Gamepad_Ltr_A_64" },
        B = { "gamepad-xbox1-buttonb-normal", "Gamepad_Ltr_B_64" },
        X = { "gamepad-xbox1-buttonx-normal", "Gamepad_Ltr_X_64" },
        Y = { "gamepad-xbox1-buttony-normal", "Gamepad_Ltr_Y_64" },
        LB = { "gamepad-xbox1-trigger-lb-normal", "Gamepad_Ltr_LShoulder_64" },
        RB = { "gamepad-xbox1-trigger-rb-normal", "Gamepad_Ltr_RShoulder_64" },
        LT = { "gamepad-xbox1-trigger-lt-normal", "Gamepad_Ltr_LTrigger_64" },
        RT = { "gamepad-xbox1-trigger-rt-normal", "Gamepad_Ltr_RTrigger_64" },
        LS = { "gamepad-xbox1-stick-l3-normal" },
        RS = { "gamepad-xbox1-stick-r3-normal" },
        DPAD_UP = { "gamepad-xbox1-dpadup-normal", "Gamepad_Ltr_Up_64" },
        DPAD_DOWN = { "gamepad-xbox1-dpaddown-normal", "Gamepad_Ltr_Down_64" },
        DPAD_LEFT = { "gamepad-xbox1-dpadleft-normal", "Gamepad_Ltr_Left_64" },
        DPAD_RIGHT = { "gamepad-xbox1-dpadright-normal", "Gamepad_Ltr_Right_64" },
        BACK = { "gamepad-xbox1-view-normal", "Gamepad_Ltr_View_64" },
        START = { "gamepad-xbox1-menu-normal", "Gamepad_Ltr_Menu_64" },
        SHARE = { "gamepad-xbox1-share-normal", "Gamepad_Ltr_Share_64" },
        HOME = { "gamepad-xbox1-xblogo-normal", "Gamepad_Ltr_System_64" },
    },
    Reverse = {
        A = { "gamepad-switch-128x-face-b-normal", "Gamepad_Rev_B_64" },
        B = { "gamepad-switch-128x-face-a-normal", "Gamepad_Rev_A_64" },
        X = { "gamepad-switch-128x-face-y-normal", "Gamepad_Rev_Y_64" },
        Y = { "gamepad-switch-128x-face-x-normal", "Gamepad_Rev_X_64" },
        LB = { "gamepad-switch-128x-shoulder-l-normal", "Gamepad_Rev_LShoulder_64" },
        RB = { "gamepad-switch-128x-shoulder-r-normal", "Gamepad_Rev_RShoulder_64" },
        LT = { "gamepad-switch-128x-zl-normal", "Gamepad_Rev_LTrigger_64" },
        RT = { "gamepad-switch-128x-zr-normal", "Gamepad_Rev_RTrigger_64" },
        LS = { "gamepad-switch-128x-stick-l3-normal" },
        RS = { "gamepad-switch-128x-stick-r3-normal" },
        DPAD_UP = { "gamepad-switch-128x-dpad-up-normal" },
        DPAD_DOWN = { "gamepad-switch-128x-dpad-down-normal" },
        DPAD_LEFT = { "gamepad-switch-128x-dpad-left-normal", "gamepad-switch-128x-dpad-left-default" },
        DPAD_RIGHT = { "gamepad-switch-128x-dpad-right-normal" },
        BACK = { "gamepad-switch-128x-minus-normal", "Gamepad_Rev_Minus_64" },
        START = { "gamepad-switch-128x-plus-normal", "Gamepad_Rev_Plus_64" },
        SHARE = { "gamepad-switch-128x-capture-normal", "Gamepad_Rev_Capture_64" },
        HOME = { "gamepad-switch-128x-home-normal", "Gamepad_Rev_Home_64" },
    },
}

local NAMES = {
    Shapes = { A = "Cross", B = "Circle", X = "Square", Y = "Triangle", LB = "L1", RB = "R1", LT = "L2", RT = "R2",
        LS = "L3", RS = "R3", BACK = "Touchpad", START = "Options", SHARE = "Create", HOME = "PS" },
    Letters = { A = "A", B = "B", X = "X", Y = "Y", LB = "LB", RB = "RB", LT = "LT", RT = "RT",
        LS = "LS", RS = "RS", BACK = "View", START = "Menu", SHARE = "Share", HOME = "Xbox" },
    Reverse = { A = "B", B = "A", X = "Y", Y = "X", LB = "L", RB = "R", LT = "ZL", RT = "ZR",
        LS = "L3", RS = "R3", BACK = "Minus", START = "Plus", SHARE = "Capture", HOME = "Home" },
}
local COMMON = {
    DPAD_UP = "D-pad Up", DPAD_DOWN = "D-pad Down", DPAD_LEFT = "D-pad Left", DPAD_RIGHT = "D-pad Right",
    PADDLE1 = "Paddle 1", PADDLE2 = "Paddle 2", PADDLE3 = "Paddle 3", PADDLE4 = "Paddle 4",
}

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- The style the pad reports (as the game's own prompts pick theirs)
function Pad.Detected()
    -- (the C API only: no method of the game's Lua is called)
    local style
    if C_GamePad and C_GamePad.GetDeviceMappedState then
        local ok, state = pcall(C_GamePad.GetDeviceMappedState, C_GamePad.GetActiveDeviceID and C_GamePad.GetActiveDeviceID() or nil)
        if ok and type(state) == "table" then style = state.labelStyle end
    end
    return ATLAS[style] and style or "Letters"
end

-- The style in use: the profile's choice, else the detected one
function Pad.Style()
    local p = PF.P and PF.P()
    local set = p and p.ui and p.ui.padStyle
    if ATLAS[set] then return set end
    return Pad.Detected()
end

-- "A", "Cross", "Paddle 1"...
function Pad.Name(key)
    local g = GLYPH_KEY[key] or key
    return NAMES[Pad.Style()][g] or COMMON[g] or g
end

function Pad.Atlas(key)
    local g = GLYPH_KEY[key] or key
    for _, name in ipairs(ATLAS[Pad.Style()][g] or {}) do
        if HasAtlas(name) then return name end
    end
end

-- The glyph as inline text (falls back to the name in brackets)
function Pad.Glyph(key, size)
    local atlas = Pad.Atlas(key)
    size = size or 16
    if atlas then return "|A:" .. atlas .. ":" .. size .. ":" .. size .. "|a" end
    return "[" .. Pad.Name(key) .. "]"
end

---------------------------------------------------------------------------
-- Specs
---------------------------------------------------------------------------
Pad.LAYERS = { "N", "LT", "RT", "LTRT" }
Pad.LAYER_LABEL = { N = "", LT = "LT", RT = "RT", LTRT = "LT+RT" }

function Pad.Spec(layer, key)
    if not layer or layer == "N" then return key end
    return layer .. ":" .. key
end

function Pad.Parse(spec)
    if type(spec) ~= "string" then return nil end
    local layer, key = spec:match("^(%u+):(.+)$")
    if layer then return layer, key end
    return "N", spec
end

-- "LT + Paddle 1" with glyphs
function Pad.SpecText(spec, size)
    local layer, key = Pad.Parse(spec)
    if not key then return "Not set" end
    local parts = {}
    if layer == "LT" or layer == "LTRT" then parts[#parts + 1] = Pad.Glyph("PADLTRIGGER", size) end
    if layer == "RT" or layer == "LTRT" then parts[#parts + 1] = Pad.Glyph("PADRTRIGGER", size) end
    parts[#parts + 1] = Pad.Glyph(key, size)
    return table.concat(parts, " + ")
end

function Pad.SpecName(spec)
    local layer, key = Pad.Parse(spec)
    if not key then return "Not set" end
    local parts = {}
    if layer == "LT" or layer == "LTRT" then parts[#parts + 1] = Pad.Name("PADLTRIGGER") end
    if layer == "RT" or layer == "LTRT" then parts[#parts + 1] = Pad.Name("PADRTRIGGER") end
    parts[#parts + 1] = Pad.Name(key)
    return table.concat(parts, " + ")
end

---------------------------------------------------------------------------
-- Indices for GetGamePadState() in secure snippets (1-based)
---------------------------------------------------------------------------
function Pad.Index(binding)
    if C_GamePad and C_GamePad.ButtonBindingToIndex then
        local ok, index = pcall(C_GamePad.ButtonBindingToIndex, binding)
        if ok and index then return index + 1 end
    end
end

function Pad.StickIndex(name)
    if C_GamePad and C_GamePad.StickConfigNameToIndex then
        local ok, index = pcall(C_GamePad.StickConfigNameToIndex, name)
        if ok and index and index >= 0 then return index + 1 end
    end
end

-- The live state (insecure: our own windows and visuals)
function Pad.State()
    if not (C_GamePad and C_GamePad.GetDeviceMappedState) then return nil end
    local ok, state = pcall(C_GamePad.GetDeviceMappedState, C_GamePad.GetActiveDeviceID and C_GamePad.GetActiveDeviceID() or nil)
    return ok and type(state) == "table" and state or nil
end

function Pad.Held(binding)
    if IsKeyDown then
        local ok, down = pcall(IsKeyDown, binding)
        if ok and down then return true end
    end
    local state, index = Pad.State(), Pad.Index(binding)
    return state and state.buttons and index and state.buttons[index] and true or false
end

-- The triggers held now, as a layer
function Pad.LayerNow()
    local lt, rt = Pad.Held("PADLTRIGGER"), Pad.Held("PADRTRIGGER")
    if lt and rt then return "LTRT" end
    if lt then return "LT" end
    if rt then return "RT" end
    return "N"
end

-- The right stick now: x, y (y up), or 0, 0
function Pad.Stick(name)
    local state = Pad.State()
    local index = Pad.StickIndex(name or "Right") or (name == "Left" and 1 or 2)
    local stick = state and state.sticks and state.sticks[index]
    if stick and stick.x and stick.y then return stick.x, stick.y end
    return 0, 0
end

function Pad.Connected()
    return C_GamePad and C_GamePad.GetActiveDeviceID and C_GamePad.GetActiveDeviceID() ~= nil or false
end

-- Re-draw what shows glyphs when the pad (or its style) changes
for _, event in ipairs({ "GAME_PAD_ACTIVE_CHANGED", "GAME_PAD_CONNECTED", "GAME_PAD_DISCONNECTED" }) do
    PF.On(event, function() PF.Fire("PF_PAD_STYLE") end)
end
