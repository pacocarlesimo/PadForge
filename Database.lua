-- Saved data: profiles (account-wide, chosen per character and optionally
-- per talent spec), a versioned schema with migrations (settings are never
-- wiped by an update), snapshots taken before anything destructive, and
-- export / import of whole profiles or parts of them.
--
-- PadForgeDB = {
--   schema = n,
--   profiles = { [name] = profile },
--   chars = { ["Name-Realm"] = { profile = name, spec = { [group] = name },
--             context = { dungeon = name, raid = name, pvp = name } } },
--   snapshots = { { time, label, name, data } },   -- newest first
--   global = { compatSeen = {}, welcomed = bool },
-- }
local _, PF = ...
local U = PF.Util

local DB = {}
PF.DB = DB

DB.SCHEMA = 6
DB.DEFAULT = "Default"
local MAX_SNAPSHOTS = 12

-- Each module adds its own defaults (DB.RegisterDefaults("wheels", {...}))
-- and may clean what an import brings (validate(sectionTable) -> table)
local defaults = { modules = {}, ui = { padStyle = "auto", scale = 1 } }
local validators = {}

function DB.RegisterDefaults(section, values, validate)
    defaults[section] = values
    validators[section] = validate
end

function DB.Defaults()
    return U.Copy(defaults)
end

-- The sections a profile has, in a stable order (for export choices)
function DB.Sections()
    return U.SortedKeys(defaults)
end

DB.SECTION_LABELS = {
    buttons = "Buttons & relocations",
    wheels = "Wheels",
    prompts = "Popup answers",
    interface = "Hidden elements",
    movement = "Movement & camera",
    questitem = "Quest item",
    modules = "Modules on/off",
    ui = "Look",
}

---------------------------------------------------------------------------
-- Migrations: MIGRATIONS[n] turns schema n-1 into n. Never remove one.
---------------------------------------------------------------------------
local MIGRATIONS = {
    -- 2: the auto keyboard / pad switch (beta3-5) was taken out
    [2] = function(db)
        for _, profile in pairs(db.profiles or {}) do
            profile.autoswitch = nil
            if profile.modules then profile.modules.autoswitch = nil end
        end
        if db.global then db.global.lastSwitch = nil end
    end,
    -- 3: macros written in PadForge (beta9) taken out; game macros only
    [3] = function(db)
        for _, profile in pairs(db.profiles or {}) do
            profile.macros = nil
            for _, e in pairs(profile.buttons and profile.buttons.keys or {}) do
                for layer, action in pairs(e.layers or {}) do
                    if type(action) == "string" and action:find("^cmd:") then e.layers[layer] = nil end
                end
            end
            for _, w in ipairs(profile.wheels and profile.wheels.list or {}) do
                for i = #(w.slots or {}), 1, -1 do
                    if type(w.slots[i]) == "string" and w.slots[i]:find("^cmd:") then table.remove(w.slots, i) end
                end
            end
        end
    end,
    -- 4: the wheel's default place moved right of the character and more
    -- see-through (only where the old defaults were never changed)
    [4] = function(db)
        for _, profile in pairs(db.profiles or {}) do
            local look = profile.wheels and profile.wheels.look
            if type(look) == "table" then
                if look.x == 0 and look.y == 40 then look.x, look.y = 480, -60 end
                if look.opacity == 0.72 then look.opacity = 0.45 end
            end
        end
    end,
    -- 5: a Mounts wheel joins the built-in ones (where there's room)
    [5] = function(db)
        for _, profile in pairs(db.profiles or {}) do
            local list = profile.wheels and profile.wheels.list
            if type(list) == "table" and #list < 8 then
                local has = false
                for _, w in ipairs(list) do if type(w) == "table" and w.source == "mounts" then has = true end end
                if not has then list[#list + 1] = { name = "Mounts", source = "mounts" } end
            end
        end
    end,
    -- 6: vibration and the log file are gone
    [6] = function(db)
        db.log = nil
        for _, profile in pairs(db.profiles or {}) do
            profile.vibration = nil
            if type(profile.modules) == "table" then profile.modules.vibration = nil end
            local cv = profile.movement and profile.movement.cvars
            if type(cv) == "table" then cv.GamePadVibrationStrength = nil end
        end
    end,
}

local function Migrate(db)
    db.schema = db.schema or DB.SCHEMA
    while db.schema < DB.SCHEMA do
        local step = MIGRATIONS[db.schema + 1]
        if step then
            local ok, err = pcall(step, db)
            if not ok then PF.Report("migration " .. (db.schema + 1), err) end
        end
        db.schema = db.schema + 1
    end
end
DB.Migrate = Migrate

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end
DB.CharKey = CharKey

local function Clean(profile)
    U.Defaults(profile, defaults)
    for section, validate in pairs(validators) do
        if validate and type(profile[section]) == "table" then
            local ok, cleaned = pcall(validate, profile[section])
            if ok and type(cleaned) == "table" then profile[section] = cleaned end
        end
    end
    return profile
end

function DB.Init()
    if PF.db then return end
    PadForgeDB = type(PadForgeDB) == "table" and PadForgeDB or {}
    PadForgeCharDB = type(PadForgeCharDB) == "table" and PadForgeCharDB or {}
    local db = PadForgeDB
    Migrate(db)
    db.profiles = db.profiles or {}
    db.chars = db.chars or {}
    db.snapshots = db.snapshots or {}
    db.global = db.global or {}
    db.global.compatSeen = db.global.compatSeen or {}
    if not db.profiles[DB.DEFAULT] then db.profiles[DB.DEFAULT] = {} end
    for _, profile in pairs(db.profiles) do Clean(profile) end
    PF.db = db
    PF.charDB = PadForgeCharDB
    local key = CharKey()
    db.chars[key] = db.chars[key] or { profile = DB.DEFAULT, spec = {} }
    PF.char = db.chars[key]
    PF.char.spec = PF.char.spec or {}
    PF.char.context = type(PF.char.context) == "table" and PF.char.context or {}
    if not db.profiles[PF.char.profile] then PF.char.profile = DB.DEFAULT end
end

---------------------------------------------------------------------------
-- The active profile
---------------------------------------------------------------------------
local function SpecGroup()
    if GetActiveTalentGroup then
        local ok, group = pcall(GetActiveTalentGroup)
        if ok then return group end
    end
    return nil
end
DB.SpecGroup = SpecGroup

-- Where the player is: "world", "dungeon", "raid" or "pvp"
DB.CONTEXTS = { "dungeon", "raid", "pvp" }
DB.CONTEXT_LABELS = { world = "the world", dungeon = "a dungeon", raid = "a raid", pvp = "a battleground or arena" }
function DB.Context()
    if not IsInInstance then return "world" end
    local _, kind = IsInInstance()
    if kind == "party" then return "dungeon" end
    if kind == "raid" then return "raid" end
    if kind == "pvp" or kind == "arena" then return "pvp" end
    return "world"
end

-- Which setting picks the profile now: "context", "spec" or "char"
local function Source()
    local ctx = DB.Context()
    local byPlace = PF.char.context[ctx]
    if byPlace and PF.db.profiles[byPlace] then return "context", ctx end
    local group = SpecGroup()
    if group and PF.char.spec[group] and PF.db.profiles[PF.char.spec[group]] then return "spec", group end
    return "char"
end
DB.Source = Source

function DB.ActiveName()
    if not PF.db then return DB.DEFAULT end
    local src, key = Source()
    if src == "context" then return PF.char.context[key] end
    local group = SpecGroup()
    local bySpec = group and PF.char.spec[group]
    if bySpec and PF.db.profiles[bySpec] then return bySpec end
    return PF.char.profile
end

function PF.P()
    if not PF.db then return nil end
    return PF.db.profiles[DB.ActiveName()] or PF.db.profiles[DB.DEFAULT]
end

local function Changed()
    PF.Fire("PF_PROFILE_CHANGED", DB.ActiveName())
end
DB.Changed = Changed

function DB.Exists(name)
    return PF.db.profiles[name] ~= nil
end

function DB.Names()
    return U.SortedKeys(PF.db.profiles)
end

-- The character's profile (and the current spec's, when one is set for it)
-- (whatever picks the profile now is changed: the place's, the spec's,
-- or the character's)
function DB.SetActive(name)
    if not DB.Exists(name) then return false end
    local src, key = Source()
    if src == "context" then
        PF.char.context[key] = name
    elseif src == "spec" then
        PF.char.spec[key] = name
    else
        PF.char.profile = name
    end
    Changed()
    return true
end

-- A place's own profile (nil: the usual one)
function DB.SetContextProfile(ctx, name)
    PF.char.context[ctx] = (name and DB.Exists(name)) and name or nil
    Changed()
end

-- A spec's own profile (nil: the character's)
function DB.SetSpecProfile(group, name)
    if not group then return end
    PF.char.spec[group] = (name and DB.Exists(name)) and name or nil
    Changed()
end

function DB.UniqueName(base)
    base = (base or "Profile"):gsub("^%s+", ""):gsub("%s+$", "")
    if base == "" then base = "Profile" end
    if not DB.Exists(base) then return base end
    local n = 2
    while DB.Exists(base .. " " .. n) do n = n + 1 end
    return base .. " " .. n
end

-- A new profile, copied from another (nil: from the defaults)
function DB.New(name, copyFrom)
    name = DB.UniqueName(name)
    local source = copyFrom and PF.db.profiles[copyFrom]
    PF.db.profiles[name] = Clean(source and U.Copy(source) or {})
    return name
end

function DB.Rename(old, new)
    if not DB.Exists(old) or old == DB.DEFAULT then return nil end
    new = DB.UniqueName(new)
    PF.db.profiles[new], PF.db.profiles[old] = PF.db.profiles[old], nil
    for _, c in pairs(PF.db.chars) do
        if c.profile == old then c.profile = new end
        for g, n in pairs(c.spec or {}) do if n == old then c.spec[g] = new end end
        for k, n in pairs(c.context or {}) do if n == old then c.context[k] = new end end
    end
    Changed()
    return new
end

function DB.Delete(name)
    if not DB.Exists(name) or name == DB.DEFAULT then return false end
    DB.Snapshot("Before deleting " .. name, name)
    PF.db.profiles[name] = nil
    for _, c in pairs(PF.db.chars) do
        if c.profile == name then c.profile = DB.DEFAULT end
        for g, n in pairs(c.spec or {}) do if n == name then c.spec[g] = nil end end
        for k, n in pairs(c.context or {}) do if n == name then c.context[k] = nil end end
    end
    Changed()
    return true
end

-- Back to the defaults (a snapshot first)
function DB.Reset(name, section)
    name = name or DB.ActiveName()
    local profile = PF.db.profiles[name]
    if not profile then return end
    DB.Snapshot("Before reset" .. (section and (" of " .. section) or ""), name)
    if section then
        profile[section] = U.Copy(defaults[section])
    else
        PF.db.profiles[name] = Clean({})
    end
    Changed()
end

---------------------------------------------------------------------------
-- Snapshots: copies of one profile, newest first
---------------------------------------------------------------------------
function DB.Snapshot(label, name)
    name = name or DB.ActiveName()
    local profile = PF.db.profiles[name]
    if not profile then return end
    table.insert(PF.db.snapshots, 1, { time = time(), label = label or "Snapshot", name = name, data = U.Copy(profile) })
    while #PF.db.snapshots > MAX_SNAPSHOTS do table.remove(PF.db.snapshots) end
end

-- Puts a snapshot back as its profile (re-created if it was deleted)
function DB.Restore(index)
    local snap = PF.db.snapshots[index]
    if not snap then return false end
    if DB.Exists(snap.name) then DB.Snapshot("Before restoring", snap.name) end
    PF.db.profiles[snap.name] = Clean(U.Copy(snap.data))
    Changed()
    return true
end

---------------------------------------------------------------------------
-- Export / import
---------------------------------------------------------------------------
local FORMAT = 1

-- sections: { buttons = true, ... } or nil for all
function DB.Export(name, sections)
    name = name or DB.ActiveName()
    local profile = PF.db.profiles[name]
    if not profile then return nil end
    local data = {}
    for section, value in pairs(profile) do
        if not sections or sections[section] then data[section] = U.Copy(value) end
    end
    local _, class = UnitClass("player")
    return U.Encode({ format = FORMAT, kind = "profile", name = name, addon = PF.version, class = class, data = data })
end

-- Reads a string: { name, class, sections = {list}, data, changes = {paths vs
-- the active profile} } or nil and why
function DB.ReadImport(text)
    local payload, why = U.Decode(text)
    if not payload then return nil, why end
    if payload.kind ~= "profile" or type(payload.data) ~= "table" then return nil, "This string doesn't hold a profile." end
    if type(payload.format) ~= "number" or payload.format > FORMAT then
        return nil, "This string is from a newer PadForge. Update the addon first."
    end
    local data = {}
    for section, value in pairs(payload.data) do
        -- (only sections this version knows: the rest is dropped, never run)
        if defaults[section] ~= nil and type(value) == "table" then data[section] = value end
    end
    local sections = U.SortedKeys(data)
    if #sections == 0 then return nil, "Nothing in this string that this version can use." end
    local current = PF.P()
    local before, after = {}, {}
    for _, section in ipairs(sections) do
        before[section] = current[section]
        local cleaned = U.Copy(data[section])
        U.Defaults(cleaned, defaults[section])
        if validators[section] then
            local ok, out = pcall(validators[section], cleaned)
            if ok and type(out) == "table" then cleaned = out end
        end
        data[section] = cleaned
        after[section] = cleaned
    end
    return {
        name = type(payload.name) == "string" and payload.name:sub(1, 40) or "Imported",
        class = payload.class, addon = payload.addon, sections = sections, data = data,
        changes = U.Diff(before, after, 500),
    }
end

-- mode "new": a new profile (from the defaults, the string's sections over
-- it) made active; "merge": the string's sections over the active profile
function DB.ApplyImport(info, mode)
    if mode == "merge" then
        local name = DB.ActiveName()
        DB.Snapshot("Before import", name)
        local profile = PF.db.profiles[name]
        for section, value in pairs(info.data) do profile[section] = U.Copy(value) end
        Changed()
        return name
    end
    local name = DB.New(info.name)
    local profile = PF.db.profiles[name]
    for section, value in pairs(info.data) do profile[section] = U.Copy(value) end
    DB.SetActive(name)
    return name
end

PF.On("ACTIVE_TALENT_GROUP_CHANGED", function()
    if PF.db then Changed() end
end)

-- Entering a dungeon, a raid, a battleground: its profile, when one is set
local lastActive
local function PlaceChanged()
    if not PF.db then return end
    local now = DB.ActiveName()
    if lastActive and now ~= lastActive then
        PF.Print("Profile: " .. now .. " (in " .. DB.CONTEXT_LABELS[DB.Context()] .. ")")
        Changed()
    end
    lastActive = now
end
PF.On("PLAYER_ENTERING_WORLD", PlaceChanged)
PF.On("ZONE_CHANGED_NEW_AREA", PlaceChanged)
PF.On("PF_PROFILE_CHANGED", function() lastActive = DB.ActiveName() end)

---------------------------------------------------------------------------
-- Slash
---------------------------------------------------------------------------
PF.AddCommand("profile", function(rest)
    if rest == "" then
        PF.Print("Profile: " .. DB.ActiveName() .. " (of " .. table.concat(DB.Names(), ", ") .. ")")
        return
    end
    if PF.InCombat() then return PF.Print("Not in combat.") end
    if DB.SetActive(rest) then PF.Print("Profile: " .. rest) else PF.Print("No profile named " .. rest) end
end, "[name]: show or switch the profile")
