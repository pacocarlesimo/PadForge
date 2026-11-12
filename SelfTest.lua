-- /pf selftest: checks, on the real client, the things PadForge takes for
-- granted about it and that no test outside the game can prove (what the
-- C side answers, which frames exist under which names). Read only: C
-- API calls and field reads, nothing of the game's is called or changed.
-- The report is printed and kept in PadForgeDB.selftest (written to disk
-- on /reload or logout), so it can be sent along with a bug report.
local _, PF = ...
local Pad, B = PF.Pad, PF.Binds

local T = {}
PF.SelfTest = T

local function Try(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

-- Each: name, function -> ok (true / false / nil for "can't tell"), detail
T.CHECKS = {
    { "Client", function()
        local version, build, _, toc = GetBuildInfo()
        return toc ~= nil, tostring(version) .. " (" .. tostring(build) .. "), interface " .. tostring(toc)
    end },
    { "Controller", function()
        local state = Pad.State()
        if not state then return nil, "no controller active: plug one in and run this again" end
        return true, tostring(state.name) .. ", labels " .. tostring(state.labelStyle)
    end },
    { "Trigger and shoulder indices", function()
        local out, ok = {}, true
        for _, key in ipairs({ "PADLTRIGGER", "PADRTRIGGER", "PADLSHOULDER", "PADRSHOULDER" }) do
            local index = Pad.Index(key)
            ok = ok and index ~= nil
            out[#out + 1] = key .. "=" .. tostring(index)
        end
        return ok, table.concat(out, " ")
    end },
    { "Sticks by name", function()
        local names = {}
        if C_GamePad and C_GamePad.StickIndexToConfigName then
            for index = 0, 7 do
                local name = Try(C_GamePad.StickIndexToConfigName, index)
                if name then names[#names + 1] = index .. ":" .. tostring(name) end
            end
        end
        local right = Pad.StickIndex("Right")
        return right ~= nil, "right stick at " .. tostring(right) .. " of [" .. table.concat(names, " ") .. "]"
    end },
    { "Focus manager readable", function()
        local manager = GamepadMode and GamepadMode.FrameControlsManager
        if type(manager) ~= "table" then return false, "GamepadMode.FrameControlsManager is not there" end
        return type(manager.isUIFocused) == "boolean", "isUIFocused is a " .. type(manager.isUIFocused)
            .. ", focusedFrame a " .. type(manager.focusedFrame)
    end },
    { "Face buttons on the crossbar", function()
        local out, ok = {}, true
        for _, key in ipairs(B.FACE) do
            local n = B.CrossbarIndex(key)
            ok = ok and n ~= nil
            out[#out + 1] = key .. "=" .. tostring(n)
        end
        return ok, table.concat(out, " ")
    end },
    { "Crossbar buttons reachable by name", function()
        local missing, sample = {}, nil
        for _, layer in ipairs({ "N", "LT", "RT", "LTRT" }) do
            for n = 1, 8 do
                local name = B.CrossbarButtonName(layer, n)
                if not name then missing[#missing + 1] = layer .. n else sample = sample or name end
            end
        end
        return #missing == 0, #missing == 0 and ("e.g. " .. tostring(sample)) or ("missing: " .. table.concat(missing, " "))
    end },
    { "Popup buttons reachable by name", function()
        local popup = _G.StaticPopup1
        if not popup then return false, "no StaticPopup1" end
        local button = (popup.ButtonContainer and popup.ButtonContainer.Button1) or popup.button1 or _G.StaticPopup1Button1
        local name = button and button.GetName and button:GetName()
        return name ~= nil, tostring(name)
    end },
    { "Ready check buttons", function()
        return _G.ReadyCheckFrameYesButton ~= nil and _G.ReadyCheckFrameNoButton ~= nil, _G.ReadyCheckFrame and "found" or "no ReadyCheckFrame"
    end },
    { "Cast on key down", function()
        return true, B.KeyDown() and "on the press" or "on the release"
    end },
    { "PadForge's own state", function()
        local claims, conflicts = 0, #B.conflicts
        for _ in pairs(B.applied) do claims = claims + 1 end
        return #PF.errors == 0, claims .. " presses bound, " .. conflicts .. " clashes, " .. #PF.errors .. " errors"
            .. (PF.errors[1] and (": " .. PF.errors[1]) or "")
    end },
}

function T.Run()
    local report = { time = time(), version = PF.version, lines = {} }
    local bad = 0
    for _, check in ipairs(T.CHECKS) do
        local ran, ok, detail = pcall(check[2])
        if not ran then ok, detail = false, "error: " .. tostring(ok) end
        if ok == false then bad = bad + 1 end
        report.lines[#report.lines + 1] = (ok == true and "OK   " or ok == false and "FAIL " or "?    ") .. check[1] .. ": " .. tostring(detail)
    end
    report.failed = bad
    if PF.db then PF.db.selftest = report end
    return report
end

PF.AddCommand("selftest", function()
    local report = T.Run()
    PF.Print("Self test, " .. (report.failed == 0 and "all good" or (report.failed .. " problem(s)")) .. ":")
    for _, line in ipairs(report.lines) do
        local colour = line:find("^OK") and "|cff80ff80" or line:find("^FAIL") and "|cffff7359" or "|cffffd070"
        DEFAULT_CHAT_FRAME:AddMessage("  " .. colour .. line .. "|r")
    end
    PF.Print("Kept in the saved settings (written on /reload or logout), to send with a bug report.")
end, "check what PadForge relies on in this client")
