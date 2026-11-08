-- The pages of the PadForge window.
local _, PF = ...
local Config, W, Pad, B, A = PF.Config, PF.Widgets, PF.Pad, PF.Binds, PF.Actions
local DB, U = PF.DB, PF.Util

local function P() return PF.P() end
local function Header(text) return { kind = "header", text = text } end
local function Text(text) return { kind = "text", text = text } end
local function Window() return Config.window end

local function ModuleToggle(key)
    local def = PF.modules[key]
    return {
        kind = "toggle", label = def.title, tip = def.desc,
        get = function()
            if def.defaultOff then return P().modules[key] == true end
            return P().modules[key] ~= false
        end,
        set = function(v)
            P().modules[key] = v and true or false
            PF.EnableModules()
        end,
        warn = function()
            local _, why = PF.ModuleBlockedBy(def)
            return why and ("Off while " .. why .. " is loaded.") or nil
        end,
    }
end

local function NeedsModule(key, rows)
    if not PF.modules[key].running then
        table.insert(rows, 1, Text("|cffff7359This module is off (Start page).|r"))
    end
    return rows
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
Config.AddPage("start", "Start", function()
    local rows = {
        Header("Welcome"),
        Text("Your controller, your way. Everything here works in combat once set,"),
        Text("and leaves the game's own gamepad UI untouched."),
        { kind = "button", label = "Quick setup for your class", verb = "Open",
            tip = "A starting layout with the spells you already know.",
            run = function() Config.Show("setup") end },
        { kind = "button", label = "Free a face button (A / B / X / Y)", verb = "Open",
            tip = "Put a spell on a face button, fully or only while an enemy is targeted (Smart).",
            run = function() Config.Show("buttons") end },
        { kind = "button", label = "Set up your wheels", verb = "Open",
            tip = "R3 opens a radial menu: items, markers, chat, group targeting, your picks.",
            run = function() Config.Show("wheels") end },
        { kind = "button", label = "Share or load a setup", verb = "Open",
            tip = "Export your profile as a string, or import someone else's.",
            run = function() Config.Show("profiles") end },
        Header("Modules"),
    }
    for _, def in ipairs(PF.moduleOrder) do rows[#rows + 1] = ModuleToggle(def.key) end
    rows[#rows + 1] = Header("Look")
    rows[#rows + 1] = {
        kind = "choice", label = "Button glyphs", tip = "Which controller's buttons PadForge shows. Automatic follows the pad in hand.",
        choices = function()
            local out = {}
            for _, s in ipairs(Pad.STYLES) do out[#out + 1] = { s, Pad.STYLE_LABELS[s] .. (s == "auto" and (" (" .. Pad.STYLE_LABELS[Pad.Detected()] .. ")") or "") } end
            return out
        end,
        get = function() return P().ui.padStyle or "auto" end,
        set = function(v)
            P().ui.padStyle = v
            PF.Fire("PF_PAD_STYLE")
        end,
    }
    rows[#rows + 1] = {
        kind = "toggle", label = "Minimap button", tip = "Click it to open PadForge, drag it round the minimap to move it. Also /pf minimap.",
        get = function() return PF.MinimapButton.IsShown() end,
        set = function(v) PF.MinimapButton.SetShown(v) end,
    }
    rows[#rows + 1] = {
        kind = "range", label = "Window size", min = 0.7, max = 1.5, step = 0.05,
        tip = "For couch and TV play: make this window bigger.",
        fmt = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
        get = function() return P().ui.scale or 1 end,
        set = function(v)
            P().ui.scale = v
            Window():SetScale(v)
        end,
    }
    if PF.compatFound and #PF.compatFound > 0 then
        rows[#rows + 1] = Header("Other controller addons")
        for _, c in ipairs(PF.compatFound) do rows[#rows + 1] = Text("|cffffb74d" .. c.addon .. "|r: " .. c.text) end
    end
    return rows
end, 10)

---------------------------------------------------------------------------
-- Quick setup
---------------------------------------------------------------------------
local setupOpts = { wheels = true, spells = true, smartX = true }

Config.AddPage("setup", "Quick setup", function()
    local S = PF.Setup
    local known = S.Known()
    local main = S.MainAttack()
    local rows = {
        Text("A starting layout for your class. Only spells you already know are used."),
        Header("Your class spells, known now"),
    }
    if #known == 0 then
        rows[#rows + 1] = Text("|cff999999None of the suggested spells yet: come back after a few levels.|r")
    else
        for _, e in ipairs(known) do rows[#rows + 1] = { kind = "button", label = e.label, icon = e.icon, verb = "" } end
    end
    rows[#rows + 1] = Header("Set up")
    rows[#rows + 1] = { kind = "toggle", label = "The built-in wheels on R3",
        tip = "R3: Items.  LT: Markers.  RT: Chat.  LT+RT: Group.  RB: Mounts.",
        get = function() return setupOpts.wheels end, set = function(v) setupOpts.wheels = v end }
    rows[#rows + 1] = { kind = "toggle", label = "A Spells wheel with these (LB + R3)",
        tip = "New spells from this list join it by themselves as you learn them.",
        disabled = function() return #known == 0 end,
        get = function() return setupOpts.spells and #known > 0 end, set = function(v) setupOpts.spells = v end }
    rows[#rows + 1] = { kind = "toggle",
        label = main and ("Smart X: " .. main.label .. " while an enemy is targeted") or "Smart X (your main attack: not known yet)",
        tip = "X stays Interact (loot, talk) without an enemy targeted.",
        disabled = function() return main == nil end,
        get = function() return setupOpts.smartX and main ~= nil end, set = function(v) setupOpts.smartX = v end }
    rows[#rows + 1] = Header("")
    rows[#rows + 1] = { kind = "button", label = "|cffffb74dApply|r", verb = "Apply",
        tip = "Changes only what's switched on above. A snapshot is kept first.",
        run = function()
            DB.Snapshot("Before quick setup")
            S.Apply(setupOpts)
            PF.Print("Quick setup done. Change anything in the other pages.")
            Config.Show("start")
        end }
    rows[#rows + 1] = { kind = "button", label = "Skip", verb = "Skip",
        run = function() PF.P().setup.done = true Config.Show("start") end }
    return rows
end, 12)

---------------------------------------------------------------------------
-- Group targeting
---------------------------------------------------------------------------
Config.AddPage("group", "Group", function()
    local s = P().group
    return NeedsModule("group", {
        Text("WoW lets no addon pick a target by health in combat. PadForge makes picking fast instead:"),
        Header("Step through the group"),
        Text("Put \"Next group member\" / \"Previous group member\" on any button (Group tab of the list)."),
        Text("It skips the dead and the absent, in combat too; in a raid it goes through the raid."),
        { kind = "toggle", label = "Include yourself (party)", get = function() return s.includeSelf end,
            set = function(v) s.includeSelf = v PF.Group.Build() end },
        Header("The Group wheel"),
        Text("Each member's health shows under their slot; the one who needs it most is marked LOWEST."),
        { kind = "toggle", label = "Show health on the Group wheel", get = function() return s.health end,
            set = function(v) s.health = v end },
    })
end, 25)

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local Buttons = PF.Buttons

local function KeyTitle(key)
    local native = B.NativeAction(key)
    return Pad.Glyph(key, 18) .. "  " .. Pad.Name(key) .. (native and ("  |cff999999(" .. B.NativeName(native) .. ")|r") or "")
end

local function KeySummary(key)
    local e = Buttons.Entry(key)
    local status = Buttons.status[key]
    if status and status ~= "ready" then return "|cffff7359Can't|r" end
    if not Buttons.Active(key, e) then return "|cff999999Game's own|r" end
    local action = e.layers.N or e.layers.LT or e.layers.RT or e.layers.LTRT
    local mode = e.mode == "smart" and ("Smart: " .. Buttons.CONDITIONS[e.cond].label .. " - ") or ""
    return mode .. A.Label(action)
end

-- Keys a moved game action can go to: free extra keys and face keys
local function TargetKeys(except)
    local out = {}
    for _, k in ipairs(Buttons.Keys()) do if k ~= except then out[#out + 1] = k end end
    return out
end

local function RelocationRow(key)
    local native = B.NativeAction(key)
    if not native then return nil end
    return {
        kind = "press", label = "Move " .. B.NativeName(native) .. " to",
        tip = "Gives the game's own " .. B.NativeName(native) .. " another button (a paddle, a stick click...), so freeing " .. Pad.Name(key) .. " loses nothing.",
        keys = function() return TargetKeys(key) end, noLayer = true,
        get = function() return Buttons.Relocation(key) end,
        set = function(spec)
            local _, target = Pad.Parse(spec)
            Buttons.SetRelocation(key, target)
        end,
    }
end

local function KeyPage(key)
    local face = B.IS_FACE[key]
    return function()
        local rows = { Header(KeyTitle(key)) }
        local e = Buttons.Entry(key, true)
        if face then
            rows[#rows + 1] = Text("Plain press only. With " .. Pad.Glyph("PADLTRIGGER", 14) .. " / " .. Pad.Glyph("PADRTRIGGER", 14) .. " held it stays the crossbar's.")
        end
        rows[#rows + 1] = {
            kind = "choice", label = "Mode",
            tip = "Game's own: untouched.  My action: always yours.  Smart: yours while the condition holds, the game's the rest of the time (switches in combat too).",
            choices = function()
                local out = {}
                for _, m in ipairs(Buttons.MODES) do out[#out + 1] = { m, Buttons.MODE_LABELS[m] } end
                return out
            end,
            get = function() return e.mode end,
            set = function(v) Buttons.SetMode(key, v) end,
        }
        if e.mode == "smart" then
            rows[#rows + 1] = {
                kind = "choice", label = "Yours while",
                choices = function()
                    local out = {}
                    for _, c in ipairs(Buttons.CONDITION_ORDER) do out[#out + 1] = { c, Buttons.CONDITIONS[c].label } end
                    return out
                end,
                get = function() return e.cond end,
                set = function(v) Buttons.SetCondition(key, v) end,
            }
        end
        rows[#rows + 1] = Header("Action")
        for _, layer in ipairs(Buttons.LayersOf(key)) do
            rows[#rows + 1] = {
                kind = "action",
                label = layer == "N" and ("Press " .. Pad.Name(key)) or (Pad.LAYER_LABEL[layer] .. " + " .. Pad.Name(key)),
                title = Pad.SpecName(Pad.Spec(layer, key)),
                get = function() return e.layers[layer] end,
                set = function(action) Buttons.SetAction(key, layer, action) end,
                disabled = function() return e.mode == "game" end,
                tip = e.mode == "game" and "Pick a mode other than Game's own first." or "What this press runs. Spells, items, macros, quest item, markers, chat lines...",
            }
        end
        local loses = Buttons.Loses(key)
        local reloc = RelocationRow(key)
        if reloc then
            rows[#rows + 1] = Header("The game's own " .. B.NativeName(B.NativeAction(key)))
            reloc.warn = function() return loses and ("Freed: " .. loses .. " has no button now. Move it below.") or nil end
            rows[#rows + 1] = reloc
        end
        local status = Buttons.status[key]
        if status and status ~= "ready" then rows[#rows + 1] = Text("|cffff7359" .. status .. "|r") end
        local claim = B.ClaimOn(key)
        if Buttons.Active(key, e) and claim and claim.source ~= "buttons" then
            rows[#rows + 1] = Text("|cffff7359Taken by " .. claim.source .. " (" .. (claim.label or "") .. ").|r")
        end
        return rows
    end
end

Config.AddPage("buttons", "Buttons", function()
    local rows = { Header("Face buttons") }
    for _, key in ipairs(B.FACE) do
        rows[#rows + 1] = {
            kind = "button", label = KeyTitle(key), value = function() return KeySummary(key) end, verb = "Edit",
            warn = function() return Buttons.Loses(key) and ("Freed: " .. Buttons.Loses(key) .. " has no button.") or nil end,
            tip = "Free this button for a spell or an item, always or Smart (only while an enemy is targeted).",
            run = function() Config.Push(Pad.Name(key), KeyPage(key)) end,
            alt = { label = "Game's own", run = function() Buttons.SetMode(key, "game") end },
        }
    end
    rows[#rows + 1] = Header("More buttons")
    rows[#rows + 1] = Text("Paddles (Elite, Edge, Steam Deck), stick clicks, Share. Each takes 4 actions: plain, LT, RT, LT+RT.")
    for _, key in ipairs(B.EXTRA) do
        rows[#rows + 1] = {
            kind = "button", label = KeyTitle(key), value = function() return KeySummary(key) end, verb = "Edit",
            warn = function() return Buttons.Loses(key) and ("Takes over: " .. Buttons.Loses(key)) or nil end,
            run = function() Config.Push(Pad.Name(key), KeyPage(key)) end,
            alt = { label = "Game's own", run = function() Buttons.SetMode(key, "game") end },
        }
    end
    if #B.conflicts > 0 then
        rows[#rows + 1] = Header("Clashes")
        for _, c in ipairs(B.conflicts) do
            local what = c.loser and c.loser.label or "?"
            rows[#rows + 1] = Text("|cffff7359" .. Pad.Name(c.key) .. "|r: " .. what .. " not set: "
                .. (c.why and ("it's " .. c.why) or ("taken by " .. ((c.winner and c.winner.label) or "?"))))
        end
    end
    return NeedsModule("buttons", rows)
end, 20)

---------------------------------------------------------------------------
-- Wheels
---------------------------------------------------------------------------
local Wheels = PF.Wheels

local function WheelSec() return P().wheels end

local function ChordChoices()
    local out = { { "none", "Not on a button" } }
    for _, c in ipairs(Wheels.CHORDS) do out[#out + 1] = { c, Wheels.CHORD_LABELS[c] } end
    return out
end

local function PhrasesPage()
    local rows = { Text("Lines the Chat wheel says (to your group, else /say).") }
    local list = WheelSec().phrases
    for i, text in ipairs(list) do
        rows[#rows + 1] = {
            kind = "button", label = text, verb = "Edit",
            run = function()
                W.TextInput(Window(), "Edit phrase", text, function(v)
                    if v and v ~= "" then list[i] = v:sub(1, 120) else table.remove(list, i) end
                    Wheels.Changed()
                end, { max = 120, doneLabel = "Save" })
            end,
            alt = { label = "Remove", run = function() table.remove(list, i) Wheels.Changed() end },
        }
    end
    if #list < Wheels.MAX_SLOTS then
        rows[#rows + 1] = {
            kind = "button", label = "+ Add a phrase", verb = "Add",
            run = function()
                W.TextInput(Window(), "New phrase", "", function(v)
                    if v and v ~= "" then list[#list + 1] = v:sub(1, 120) Wheels.Changed() end
                end, { max = 120, doneLabel = "Add" })
            end,
        }
    end
    return rows
end

local function WheelPage(index)
    return function()
        local w = WheelSec().list[index]
        if not w then return { Text("This wheel is gone.") } end
        local rows = {
            { kind = "button", label = "Name", value = w.name, verb = "Rename",
                run = function()
                    W.TextInput(Window(), "Wheel name", w.name, function(v)
                        if v and v ~= "" then w.name = v:sub(1, 24) Wheels.Changed() end
                    end, { max = 24, doneLabel = "Save" })
                end },
            {
                kind = "choice", label = "Opens with", tip = "The wheel button (" .. Pad.Name(WheelSec().key) .. ") with these buttons held.",
                choices = ChordChoices,
                get = function() return Wheels.ChordOf(index) or "none" end,
                set = function(v)
                    local old = Wheels.ChordOf(index)
                    if old then Wheels.SetChord(old, nil) end
                    if v ~= "none" then Wheels.SetChord(v, index) end
                end,
            },
            Text("Fills itself from: |cffffffff" .. Wheels.SOURCES[w.source] .. "|r"),
            { kind = "button", label = "Show it", verb = "Show", tip = "Opens the wheel to look at it (B closes it).",
                run = function()
                    Config.Hide()
                    C_Timer.After(0.05, function() Wheels.Preview(index) end)
                end },
        }
        if w.source == "phrases" then
            rows[#rows + 1] = { kind = "button", label = "Edit the phrases", verb = "Open", run = function() Config.Push("Phrases", PhrasesPage) end }
        end
        rows[#rows + 1] = Header("Slots (" .. (w.source == "custom" and "yours" or "right now") .. ")")
        if w.source == "custom" then
            for slot = 1, math.min(#w.slots + 1, Wheels.MAX_SLOTS) do
                rows[#rows + 1] = {
                    kind = "action", label = "Slot " .. slot, title = w.name .. ": slot " .. slot,
                    get = function() return w.slots[slot] end,
                    set = function(action) Wheels.SetSlot(index, slot, action) end,
                }
            end
        else
            local contents = Wheels.Contents(w)
            if #contents == 0 then rows[#rows + 1] = Text("|cff999999Empty right now.|r") end
            for i, action in ipairs(contents) do
                local label, icon = A.Describe(action)
                rows[#rows + 1] = { kind = "button", label = i .. ". " .. label, icon = icon, verb = "" }
            end
        end
        rows[#rows + 1] = Header("")
        rows[#rows + 1] = { kind = "button", label = "|cffff7359Remove this wheel|r", verb = "Remove",
            run = function()
                W.Confirm(Window(), "Remove wheel", "Remove \"" .. w.name .. "\"?", function()
                    Wheels.Remove(index)
                    Config.Back()
                end, "Remove")
            end }
        return rows
    end
end

local function LookPage()
    local look = WheelSec().look
    local function changed() Wheels.ApplyLook() Wheels.ShowSample() end
    local function palette(withTheme)
        local out = withTheme and { { "theme", "From the theme" } } or {}
        for _, c in ipairs(Wheels.PALETTE) do
            out[#out + 1] = { c[1], string.format("|cff%02x%02x%02x%s|r", c[3] * 255, c[4] * 255, c[5] * 255, c[2]) }
        end
        return out
    end
    return {
        Header("Position"),
        { kind = "button", label = "Move the wheel", verb = "Move",
            tip = "Drag it with the mouse, or nudge it with the D-pad. A (or a right-click) when done, Y back to the default place (right of your character).",
            value = function() return look.x .. ", " .. look.y end,
            run = Wheels.StartMove, alt = { label = "Default place", run = function() look.x, look.y = Wheels.LOOK_DEFAULTS.x, Wheels.LOOK_DEFAULTS.y changed() end } },
        Header("Colours"),
        { kind = "choice", label = "Theme",
            choices = function()
                local out = {}
                for _, t in ipairs(Wheels.THEMES) do out[#out + 1] = { t[1], t[2] } end
                return out
            end,
            get = function() return look.theme end,
            set = function(v)
                look.theme = v
                for _, t in ipairs(Wheels.THEMES) do if t[1] == v and t.opacity then look.opacity = t.opacity end end
                changed()
            end },
        { kind = "choice", label = "Background", choices = function() return palette(true) end,
            get = function() return look.bg end, set = function(v) look.bg = v changed() end },
        { kind = "choice", label = "Highlight", tip = "The ring around the slot you point at, and the wheel's edge.",
            choices = function() return palette(true) end,
            get = function() return look.glow end, set = function(v) look.glow = v changed() end },
        { kind = "range", label = "Background opacity", min = 0.1, max = 1, step = 0.05,
            fmt = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
            get = function() return look.opacity end, set = function(v) look.opacity = v changed() end },
        Header("Size"),
        { kind = "range", label = "Overall size", min = 0.6, max = 1.6, step = 0.05,
            fmt = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
            get = function() return WheelSec().scale or 1 end, set = function(v) WheelSec().scale = v changed() end },
        { kind = "range", label = "Ring radius", min = 80, max = 220, step = 5,
            get = function() return look.radius end, set = function(v) look.radius = v changed() end },
        { kind = "range", label = "Icon size", min = 28, max = 72, step = 2,
            get = function() return look.icon end, set = function(v) look.icon = v changed() end },
        Header("Show"),
        { kind = "toggle", label = "Wheel name", get = function() return look.title end, set = function(v) look.title = v changed() end },
        { kind = "toggle", label = "Name of the slot pointed at", get = function() return look.labels end, set = function(v) look.labels = v changed() end },
        { kind = "toggle", label = "Button hints", get = function() return look.hint end, set = function(v) look.hint = v changed() end },
        Header(""),
        { kind = "button", label = "Back to the default look", verb = "Reset",
            run = function()
                for k, v in pairs(Wheels.LOOK_DEFAULTS) do look[k] = v end
                WheelSec().scale = 1
                changed()
            end },
    }
end

local function AddWheelPage()
    local rows = { Text("A wheel that fills itself, or a custom one you fill.") }
    for _, source in ipairs(Wheels.SOURCE_ORDER) do
        rows[#rows + 1] = { kind = "button", label = Wheels.SOURCES[source], verb = "Add",
            run = function()
                local index = Wheels.Add(source, source == "custom" and "My wheel" or nil)
                if index then
                    Config.Back()
                    Config.Push(WheelSec().list[index].name, WheelPage(index))
                end
            end }
    end
    return rows
end

Config.AddPage("wheels", "Wheels", function()
    local s = WheelSec()
    local rows = {
        Header("How wheels work"),
        Text("Press " .. Pad.Glyph(s.key, 14) .. " (holding LT, RT, both, LB or RB for other wheels), point with " .. Pad.Glyph("PADRSTICK", 14) .. ", press " .. Pad.Glyph("PAD1", 14) .. "."),
        Text("Or hold " .. Pad.Glyph(s.key, 14) .. ", aim, and let it go."),
        {
            kind = "choice", label = "Wheel button",
            choices = function()
                local out = {}
                for _, k in ipairs(Wheels.WHEEL_KEYS) do out[#out + 1] = { k, Pad.Name(k) } end
                return out
            end,
            get = function() return s.key end,
            set = function(v) s.key = v Wheels.Changed() end,
            tip = "R3 is the game's ping by default; a paddle is great for hold-aim-release.",
        },
        { kind = "button", label = "Look & position", verb = "Open",
            tip = "Move the wheel (drag & drop), colours, theme, sizes.",
            run = function() Config.Push("Look & position", LookPage) end },
        { kind = "button", label = "Put the built-in wheels on " .. Pad.Name(s.key), verb = "Set",
            tip = "Alone: Items.  LT: Markers.  RT: Chat.  LT+RT: Group.  RB: Mounts.  (R3 alone is the game's ping: it becomes a wheel.)",
            value = function() return next(s.chords) and "" or "|cffffb74dno wheel on a button yet|r" end,
            run = Wheels.UseDefaultLayout },
        Header("Your wheels"),
    }
    for i, w in ipairs(s.list) do
        local chord = Wheels.ChordOf(i)
        rows[#rows + 1] = {
            kind = "button", label = w.name, verb = "Edit",
            value = chord and (Wheels.CHORD_LABELS[chord]) or "|cff999999not on a button|r",
            tip = Wheels.SOURCES[w.source],
            run = function() Config.Push(w.name, WheelPage(i)) end,
        }
    end
    if #s.list < Wheels.MAX_WHEELS then
        rows[#rows + 1] = { kind = "button", label = "+ Add a wheel", verb = "Add", run = function() Config.Push("Add a wheel", AddWheelPage) end }
    end
    return NeedsModule("wheels", rows)
end, 30)

---------------------------------------------------------------------------
-- Popups
---------------------------------------------------------------------------
Config.AddPage("prompts", "Popups", function()
    local s = P().prompts
    local rows = {
        Text("While one of these is up (and no game window has the pad), answer it straight away."),
        Header("Answer"),
    }
    for _, kind in ipairs(PF.Prompts.KINDS) do
        rows[#rows + 1] = { kind = "toggle", label = kind.label,
            get = function() return s.on[kind.id] end, set = function(v) s.on[kind.id] = v and true or false end }
    end
    local faceChoices = function(opts)
        local out = {}
        for _, k in ipairs(opts) do out[#out + 1] = { k, Pad.Glyph(k, 16) .. " " .. Pad.Name(k) } end
        return out
    end
    rows[#rows + 1] = Header("Buttons")
    rows[#rows + 1] = { kind = "choice", label = "Yes", choices = function() return faceChoices({ "PAD1", "PAD3", "PAD4" }) end,
        get = function() return s.yes end, set = function(v) if v ~= s.no then s.yes = v end end }
    rows[#rows + 1] = { kind = "choice", label = "No", choices = function() return faceChoices({ "PAD2", "PAD3", "PAD4" }) end,
        get = function() return s.no end, set = function(v) if v ~= s.yes then s.no = v end end }
    rows[#rows + 1] = { kind = "range", label = "Wait before answering", min = 0, max = 2, step = 0.1,
        tip = "A press this soon after a popup appears doesn't answer it (no accidental yes while jumping). Release spirit always waits at least 1.2 s.",
        fmt = function(v) return string.format("%.1f s", v) end,
        get = function() return s.grace end, set = function(v) s.grace = v end }
    rows[#rows + 1] = { kind = "toggle", label = "Show the hint", get = function() return s.hint end, set = function(v) s.hint = v end }
    return NeedsModule("prompts", rows)
end, 40)

---------------------------------------------------------------------------
-- Quest item
---------------------------------------------------------------------------
local function QuestPress()
    for key, e in pairs(P().buttons.keys) do
        for layer, action in pairs(e.layers) do
            if action == "questitem" and e.mode ~= "game" then return Pad.Spec(layer, key) end
        end
    end
end

Config.AddPage("questitem", "Quest item", function()
    local s = P().questitem
    local QI = PF.QuestItem
    local cur = QI.Current()
    local rows = {
        Text("One button uses the right quest item: the newest one you got, quest starters first."),
        { kind = "press", label = "Quest item button", tip = "Any free button or paddle (with LT/RT for a layer).",
            keys = function() return Buttons.Keys() end,
            get = QuestPress,
            set = function(spec)
                local old = QuestPress()
                if old then
                    local l, k = Pad.Parse(old)
                    Buttons.SetAction(k, l, nil)
                end
                if spec then
                    local l, k = Pad.Parse(spec)
                    if B.IS_FACE[k] then l = "N" end
                    Buttons.SetAction(k, l, "questitem")
                end
            end },
        Header("Now"),
        { kind = "button", label = cur and ((A.ItemInfo(cur)) or ("Item " .. cur)) or "|cff999999No quest item in your bags|r",
            icon = cur and select(2, A.ItemInfo(cur)) or nil, verb = "Skip",
            tip = "Skip this item: the next one is used instead.",
            run = function() if cur then QI.Skip(cur) end end },
        { kind = "button", label = "Bring skipped items back", verb = "Reset", run = QI.ClearSkips,
            value = function() return U.Count(s.skip) > 0 and (U.Count(s.skip) .. " skipped") or "" end },
        Header("Icon"),
        { kind = "toggle", label = "Show the quest item icon", get = function() return s.showIcon end,
            set = function(v) s.showIcon = v QI.RefreshIcon() end },
        { kind = "range", label = "Left / right", min = -900, max = 900, step = 10,
            get = function() return s.x end, set = function(v) s.x = v QI.RefreshIcon() end },
        { kind = "range", label = "Down / up", min = -500, max = 500, step = 10,
            get = function() return s.y end, set = function(v) s.y = v QI.RefreshIcon() end },
    }
    return NeedsModule("questitem", rows)
end, 50)

---------------------------------------------------------------------------
-- Hide elements
---------------------------------------------------------------------------
local Interface = PF.Interface

local function FrameToggle(name, label)
    return { kind = "toggle", label = name .. (label and ("  |cff999999" .. label .. "|r") or ""),
        get = function() return Interface.IsHidden(name) end,
        set = function(v) Interface.SetHidden(name, v) end }
end

local function CenterPage()
    local rows = { Text("Named elements covering the middle of the screen, smallest first.") }
    local list = Interface.AtCenter()
    if #list == 0 then rows[#rows + 1] = Text("|cff999999None found. If it only shows in combat, close this, fight, and run /pf center.|r") end
    for _, e in ipairs(list) do rows[#rows + 1] = FrameToggle(e.name) end
    return rows
end

Config.AddPage("interface", "Hide", function()
    local rows = {
        Text("Hide what the gamepad UI won't let you turn off. Nothing of the game is changed: it's faded by PadForge."),
        { kind = "button", label = "Find elements in the middle of the screen", verb = "Find",
            tip = "Where the forced swing timer sits. Best done while it shows.", run = function() Config.Push("Middle of the screen", CenterPage) end },
        { kind = "button", label = "Pick one with the mouse", verb = "Start", tip = "Point at it with the mouse (or touchpad), press A.",
            run = Interface.StartPicker },
        Header("Found by name"),
    }
    local found = Interface.Discover()
    if #found == 0 then rows[#rows + 1] = Text("|cff999999No swing timer or Issue Reporter by name on this client.|r") end
    local listed = {}
    for _, e in ipairs(found) do
        rows[#rows + 1] = FrameToggle(e.name, e.label)
        listed[e.name] = true
    end
    local others = {}
    for name in pairs(P().interface.hidden) do if not listed[name] then others[#others + 1] = name end end
    if #others > 0 then
        table.sort(others)
        rows[#rows + 1] = Header("Hidden by you")
        for _, name in ipairs(others) do rows[#rows + 1] = FrameToggle(name) end
    end
    return NeedsModule("interface", rows)
end, 60)

---------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------
local Movement = PF.Movement

Config.AddPage("movement", "Movement", function()
    local rows = { Text("The game's gamepad settings, set directly. " .. Pad.Glyph("PAD4", 14) .. " puts one back to the game's default.") }
    if Movement.Differs() > 0 then
        rows[#rows + 1] = { kind = "button", label = "|cffffb74dThis profile has " .. Movement.Differs() .. " setting(s) the game doesn't|r", verb = "Apply",
            tip = "Settings are only written when you ask (never by themselves).", run = Movement.Apply }
    end
    local avail = Movement.Available()
    if #avail == 0 then rows[#rows + 1] = Text("|cff999999This client lists none of the known settings.|r") end
    for _, def in ipairs(avail) do
        local row = { label = def.label, tip = def.tip, clear = function() Movement.SetValue(def.name, nil) end }
        if def.kind == "range" then
            row.kind, row.min, row.max, row.step = "range", def.min, def.max, def.step
            row.get = function() return tonumber(Movement.Value(def.name)) or def.min end
            row.set = function(v) Movement.SetValue(def.name, v) end
        elseif def.kind == "bool" then
            row.kind = "toggle"
            row.get = function() return Movement.Value(def.name) == "1" end
            row.set = function(v) Movement.SetValue(def.name, v and "1" or "0") end
        else
            row.kind = "choice"
            row.choices = def.choices
            row.get = function() return Movement.Value(def.name) end
            row.set = function(v) Movement.SetValue(def.name, v) end
        end
        row.label = function() return def.label .. (P().movement.cvars[def.name] and "  |cff4fc3f7*|r" or "") end
        rows[#rows + 1] = row
    end
    local others = Movement.Others()
    if #others > 0 then
        rows[#rows + 1] = Header("Other gamepad settings (read only)")
        for _, o in ipairs(others) do
            rows[#rows + 1] = { kind = "button", label = o.name, value = function() return Movement.Value(o.name) or "" end,
                tip = o.tip, verb = "" }
        end
    end
    rows[#rows + 1] = Header("")
    rows[#rows + 1] = { kind = "button", label = "Put them all back to the game's defaults", verb = "Reset",
        run = function() W.Confirm(Window(), "Movement", "Every setting here back to the game's default?", Movement.ResetAll, "Reset") end }
    return NeedsModule("movement", rows)
end, 70)

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------
local function ProfileChoices()
    local out = {}
    for _, name in ipairs(DB.Names()) do out[#out + 1] = { name, name } end
    return out
end

local exportPick = {}

local function ExportPage()
    local rows = { Text("Choose what goes in the string.") }
    for _, section in ipairs(DB.Sections()) do
        if exportPick[section] == nil then exportPick[section] = section ~= "ui" end
        rows[#rows + 1] = { kind = "toggle", label = DB.SECTION_LABELS[section] or section,
            get = function() return exportPick[section] end, set = function(v) exportPick[section] = v end }
    end
    rows[#rows + 1] = { kind = "button", label = "Make the string", verb = "Make",
        run = function()
            local text = DB.Export(nil, exportPick)
            W.TextInput(Window(), "Export: " .. DB.ActiveName(), text, nil,
                { multiline = true, readOnly = true, select = true, body = "Copy it with Ctrl+C. Paste it anywhere: Discord, Wago, a forum." })
        end }
    return rows
end

local function ImportPreview(info)
    local lines = { "From: |cffffffff" .. info.name .. "|r" .. (info.class and (" (" .. info.class .. ")") or "")
        .. (info.addon and ("  PadForge " .. info.addon) or ""),
        "Holds: " .. table.concat((function()
            local t = {}
            for _, s in ipairs(info.sections) do t[#t + 1] = DB.SECTION_LABELS[s] or s end
            return t
        end)(), ", "),
        #info.changes .. " setting(s) differ from your current profile." }
    return table.concat(lines, "\n")
end

local function Import()
    W.TextInput(Window(), "Import", "", function(text)
        local info, why = DB.ReadImport(text)
        if not info then
            W.Confirm(Window(), "Import", "|cffff7359" .. why .. "|r", nil, "OK")
            return
        end
        W.Confirm(Window(), "Import as a new profile?", ImportPreview(info) .. "\n\n|cff999999Yes: a new profile \"" .. info.name
            .. "\" (made active).  Your current profile isn't touched.|r", function()
                local name = DB.ApplyImport(info, "new")
                PF.Print("Imported as profile \"" .. name .. "\".")
            end, "Import")
    end, { multiline = true, body = "Paste a PadForge string (Ctrl+V).", doneLabel = "Read" })
end

local function SnapshotsPage()
    local rows = { Text("Copies kept before deleting, resetting or importing over a profile.") }
    if #PF.db.snapshots == 0 then rows[#rows + 1] = Text("|cff999999None yet.|r") end
    for i, snap in ipairs(PF.db.snapshots) do
        rows[#rows + 1] = { kind = "button", label = snap.label .. "  |cff999999" .. snap.name .. "|r",
            value = date("%d %b %H:%M", snap.time), verb = "Restore",
            run = function()
                W.Confirm(Window(), "Restore", "Put \"" .. snap.name .. "\" back as it was on " .. date("%d %b %H:%M", snap.time) .. "?",
                    function() DB.Restore(i) end, "Restore")
            end }
    end
    return rows
end

Config.AddPage("profiles", "Profiles", function()
    local rows = {
        { kind = "choice", label = "Profile", tip = "This character's profile. Profiles are shared by all your characters.",
            choices = ProfileChoices, get = DB.ActiveName, set = function(v) DB.SetActive(v) end },
    }
    local group = DB.SpecGroup()
    local groups = GetNumTalentGroups and GetNumTalentGroups() or 1
    if group and groups and groups > 1 then
        for g = 1, groups do
            rows[#rows + 1] = { kind = "choice", label = "Spec " .. g .. (g == group and " (active)" or ""),
                tip = "Switch profile on its own when you change spec.",
                choices = function()
                    local out = { { "none", "Same as the character" } }
                    for _, c in ipairs(ProfileChoices()) do out[#out + 1] = c end
                    return out
                end,
                get = function() return PF.char.spec[g] or "none" end,
                set = function(v) DB.SetSpecProfile(g, v ~= "none" and v or nil) end }
        end
    end
    rows[#rows + 1] = Header("Switch by place")
    rows[#rows + 1] = Text("Now in " .. DB.CONTEXT_LABELS[DB.Context()] .. ". A place without its own profile uses the one above.")
    for _, ctx in ipairs(DB.CONTEXTS) do
        rows[#rows + 1] = { kind = "choice", label = "In " .. DB.CONTEXT_LABELS[ctx],
            tip = "Switches by itself as you enter (and back as you leave).",
            choices = function()
                local out = { { "none", "Same as usual" } }
                for _, c in ipairs(ProfileChoices()) do out[#out + 1] = c end
                return out
            end,
            get = function() return PF.char.context[ctx] or "none" end,
            set = function(v) DB.SetContextProfile(ctx, v ~= "none" and v or nil) end }
    end
    rows[#rows + 1] = Header("This profile")
    rows[#rows + 1] = { kind = "button", label = "New profile (a copy of this one)", verb = "Copy",
        alt = { label = "Blank", run = function() DB.SetActive(DB.New("Profile")) end },
        run = function() DB.SetActive(DB.New(DB.ActiveName(), DB.ActiveName())) end }
    rows[#rows + 1] = { kind = "button", label = "Rename", verb = "Rename",
        disabled = function() return DB.ActiveName() == DB.DEFAULT end,
        run = function()
            W.TextInput(Window(), "Rename profile", DB.ActiveName(), function(v)
                if v and v ~= "" then DB.Rename(DB.ActiveName(), v:sub(1, 40)) end
            end, { max = 40, doneLabel = "Save" })
        end }
    rows[#rows + 1] = { kind = "button", label = "Reset to defaults", verb = "Reset",
        run = function() W.Confirm(Window(), "Reset", "Reset \"" .. DB.ActiveName() .. "\"? (A snapshot is kept.)", function() DB.Reset() end, "Reset") end }
    rows[#rows + 1] = { kind = "button", label = "|cffff7359Delete|r", verb = "Delete",
        disabled = function() return DB.ActiveName() == DB.DEFAULT end,
        run = function() W.Confirm(Window(), "Delete", "Delete \"" .. DB.ActiveName() .. "\"? (A snapshot is kept.)", function() DB.Delete(DB.ActiveName()) end, "Delete") end }
    rows[#rows + 1] = Header("Share")
    rows[#rows + 1] = { kind = "button", label = "Export", verb = "Choose", tip = "Make a string of this profile (or parts of it) to share.",
        alt = { label = "Everything", run = function()
            W.TextInput(Window(), "Export: " .. DB.ActiveName(), DB.Export(), nil, { multiline = true, readOnly = true, select = true,
                body = "Copy it with Ctrl+C." })
        end },
        run = function() Config.Push("Export", ExportPage) end }
    rows[#rows + 1] = { kind = "button", label = "Import", verb = "Paste", tip = "Load a PadForge string as a new profile. Nothing in a string can run code.", run = Import }
    rows[#rows + 1] = { kind = "button", label = "Snapshots", verb = "Open", value = function() return #PF.db.snapshots .. "" end,
        run = function() Config.Push("Snapshots", SnapshotsPage) end }
    return rows
end, 80)

---------------------------------------------------------------------------
-- Help
---------------------------------------------------------------------------
Config.AddPage("help", "Help", function()
    return {
        Header("In this window"),
        Text(Pad.Glyph("PADDUP", 14) .. Pad.Glyph("PADDDOWN", 14) .. " move   " .. Pad.Glyph("PADDLEFT", 14) .. Pad.Glyph("PADDRIGHT", 14)
            .. " change   " .. Pad.Glyph("PAD1", 14) .. " select   " .. Pad.Glyph("PAD4", 14) .. " clear   " .. Pad.Glyph("PAD2", 14) .. " back"),
        Text("The mouse works too."),
        Header("Opening PadForge"),
        Text("The minimap button, /pf, a key in Key Bindings > PadForge, or \"Open PadForge\" on any button (Buttons page, Special)."),
        Header("Commands"),
        Text("/pf pick - pick an element to hide     /pf center - list what's at the screen's middle"),
        Text("/pf questitem - list quest items     /pf profile <name> - switch profile"),
        Header("Credits"),
        Text("Taint-safe techniques learned from Improved Forever and Easy Controller - Forever (MIT)."),
    }
end, 90)

PF.AddCommand("export", function() Config.Show("profiles") end, "open the export / import page")
