--[[-----------------------------------------------------------------------------
Widgets.lua
Author: Aegis Team (formerly BlacklistWarden)
Notes:
 - Fixes "attempt to call method 'GetSelectedTab' (a nil value)" by tracking
   the last-selected tab via SetUserData/GetUserData instead of using a method
   that may not exist in older AceGUI versions.
 - Maintains full UI and behavior. No functional changes beyond the fix.
-----------------------------------------------------------------------------]]--

local addonName = ...
local ADDON = LibStub("AceAddon-3.0"):GetAddon("Aegis", true) or LibStub("AceAddon-3.0"):GetAddon("BlacklistWarden")
local AceGUI = LibStub("AceGUI-3.0")

if not AceGUI then
    function _G.Aegis_OpenUI()
        if ADDON and ADDON.Print then ADDON:Print("AceGUI-3.0 is required for the UI. Please ensure it is embedded/loaded.") end
    end
    return
end

local ROW_HEIGHT = 22
local ui = nil

-- -------------------------------------------------------
-- Helpers
-- -------------------------------------------------------
local function toSortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do table.insert(keys, k) end
    table.sort(keys, function(a,b) return a:lower() < b:lower() end)
    return keys
end

-- 24h time
local function fmtDateTime(ts) return ts and date("%Y-%m-%d %H:%M", ts) or "" end

local function splitNameRealm(full)
    if not full then return "", "" end
    local name, realm = strsplit("-", full)
    return name or "", realm or ""
end

local function header(container, titles, widths)
    local hdr = AceGUI:Create("SimpleGroup")
    hdr:SetFullWidth(true)
    hdr:SetLayout("Flow")
    for i, title in ipairs(titles) do
        local lab = AceGUI:Create("Label")
        lab:SetText("|cffF2F2FF" .. title .. "|r")
        lab:SetWidth(widths[i])
        hdr:AddChild(lab)
    end
    container:AddChild(hdr)
end

local function dd(values, selected, onChange, width)
    local d = AceGUI:Create("Dropdown")
    d:SetList(values)
    d:SetValue(selected)
    d:SetCallback("OnValueChanged", function(_, _, key) onChange(key) end)
    d:SetWidth(width or 140)
    return d
end

local function valuesFromArray(arr)
    local t = {}
    for _, v in ipairs(arr or {}) do t[v] = v end
    return t
end

-- -------------------------------------------------------
-- Add Forms (Top controls)
-- -------------------------------------------------------
local function buildTopControls(container, scope)
    local wrap = AceGUI:Create("InlineGroup")
    wrap:SetTitle("Add " .. scope:gsub("^%l", string.upper):sub(1, -2))
    wrap:SetFullWidth(true)
    wrap:SetLayout("Flow")

    local lists = ADDON.db.profile.settings.lists or { types = { "N/A" }, categories = { "N/A" } }
    local defaults = ADDON.db.profile.settings.defaults or { type = "N/A", category = "N/A" }

    local valuesTypes = valuesFromArray(lists.types)
    local valuesCats  = valuesFromArray(lists.categories)

    if scope == "players" then
        local ebName = AceGUI:Create("EditBox"); ebName:SetLabel("Name (Name-Realm)"); ebName:SetWidth(220); wrap:AddChild(ebName)
        local ddType = dd(valuesTypes, defaults.type or "N/A", function() end, 140); ddType:SetLabel("Type"); wrap:AddChild(ddType)
        local ddCat  = dd(valuesCats,  defaults.category or "N/A", function() end, 140); ddCat:SetLabel("Category"); wrap:AddChild(ddCat)
        local ebReason = AceGUI:Create("EditBox"); ebReason:SetLabel("Reason"); ebReason:SetWidth(260); wrap:AddChild(ebReason)
        local btn = AceGUI:Create("Button"); btn:SetText("Add"); btn:SetWidth(100)
        btn:SetCallback("OnClick", function()
            local name = ebName:GetText()
            if name and name ~= "" then
                ADDON:AddPlayer(name, ebReason:GetText(), { type = ddType:GetValue(), category = ddCat:GetValue() })
                -- Fire both for compatibility with old/new event names
                container:Fire("Aegis_Refresh")
            end
        end)
        wrap:AddChild(btn)

    elseif scope == "guilds" then
        local ebGuild = AceGUI:Create("EditBox"); ebGuild:SetLabel('Guild Name (quote if spaced)'); ebGuild:SetWidth(230); wrap:AddChild(ebGuild)
        local ebRealm = AceGUI:Create("EditBox"); ebRealm:SetLabel("Realm (optional)"); ebRealm:SetWidth(150); wrap:AddChild(ebRealm)
        local ddType = dd(valuesTypes, defaults.type or "N/A", function() end, 140); ddType:SetLabel("Type"); wrap:AddChild(ddType)
        local ddCat  = dd(valuesCats,  defaults.category or "N/A", function() end, 140); ddCat:SetLabel("Category"); wrap:AddChild(ddCat)
        local ebReason = AceGUI:Create("EditBox"); ebReason:SetLabel("Reason"); ebReason:SetWidth(220); wrap:AddChild(ebReason)
        local btn = AceGUI:Create("Button"); btn:SetText("Add/Update"); btn:SetWidth(120)
        btn:SetCallback("OnClick", function()
            local g = ebGuild:GetText()
            if g and g ~= "" then
                local realm = ebRealm:GetText(); if realm == "" then realm = nil end
                ADDON:AddGuild(g, realm, ebReason:GetText(), { type = ddType:GetValue(), category = ddCat:GetValue() })
                container:Fire("Aegis_Refresh")
            end
        end)
        wrap:AddChild(btn)

    else -- realms
        local ebRealm = AceGUI:Create("EditBox"); ebRealm:SetLabel("Realm Name"); ebRealm:SetWidth(220); wrap:AddChild(ebRealm)
        local ddType = dd(valuesTypes, defaults.type or "N/A", function() end, 140); ddType:SetLabel("Type"); wrap:AddChild(ddType)
        local ddCat  = dd(valuesCats,  defaults.category or "N/A", function() end, 140); ddCat:SetLabel("Category"); wrap:AddChild(ddCat)
        local ebReason = AceGUI:Create("EditBox"); ebReason:SetLabel("Reason"); ebReason:SetWidth(260); wrap:AddChild(ebReason)
        local btn = AceGUI:Create("Button"); btn:SetText("Add"); btn:SetWidth(100)
        btn:SetCallback("OnClick", function()
            local r = ebRealm:GetText()
            if r and r ~= "" then
                ADDON:AddRealm(r, ebReason:GetText(), { type = ddType:GetValue(), category = ddCat:GetValue() })
                container:Fire("Aegis_Refresh")
            end
        end)
        wrap:AddChild(btn)
    end

    container:AddChild(wrap)
end

-- -------------------------------------------------------
-- Tables
-- -------------------------------------------------------
local COLS   = { "Name", "Realm", "Type", "Category", "Date/Time", "Reason" }
local WIDTHS = { 160,    140,     110,    110,         130,        300 }

local function buildTable(container, scope)
    container:ReleaseChildren()
    buildTopControls(container, scope)
    header(container, COLS, WIDTHS)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("Flow")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    container:AddChild(scroll)

    if scope == "players" then
        local keys = toSortedKeys(ADDON.db.profile.players)
        if #keys == 0 then
            local lbl = AceGUI:Create("Label"); lbl:SetText("No players blacklisted."); lbl:SetFullWidth(true)
            scroll:AddChild(lbl); return
        end
        for _, key in ipairs(keys) do
            local v = ADDON.db.profile.players[key]
            local n, r = splitNameRealm(key)
            local dateStr = (v.addedAtStr and v.addedAtStr ~= "") and v.addedAtStr or fmtDateTime(v.addedAtTS or v.addedAt)
            local cols = { n ~= "" and n or "-", r ~= "" and r or "-", v.type or "N/A", v.category or "N/A", dateStr or "", v.reason or "" }
            local row = AceGUI:Create("SimpleGroup"); row:SetLayout("Flow"); row:SetFullWidth(true)
            for i=1,#cols do local lab=AceGUI:Create("Label"); lab:SetText(cols[i]); lab:SetWidth(WIDTHS[i]); row:AddChild(lab) end
            local btn = AceGUI:Create("Button"); btn:SetText("X"); btn:SetWidth(45)
            btn:SetCallback("OnClick", function() ADDON:RemovePlayer(key); container:Fire("Aegis_Refresh"); end)
            row:AddChild(btn); scroll:AddChild(row)
        end

    elseif scope == "guilds" then
        local keys = toSortedKeys(ADDON.db.profile.guilds)
        if #keys == 0 then
            local lbl = AceGUI:Create("Label"); lbl:SetText("No guilds blacklisted."); lbl:SetFullWidth(true)
            scroll:AddChild(lbl); return
        end
        for _, key in ipairs(keys) do
            local v = ADDON.db.profile.guilds[key]
            local gName, r = key:match("^(.+)%-(.+)$")
            local dateStr = (v.addedAtStr and v.addedAtStr ~= "") and v.addedAtStr or fmtDateTime(v.addedAtTS or v.addedAt)
            local cols = { gName or key, r or "-", v.type or "N/A", v.category or "N/A", dateStr or "", v.reason or "" }
            local row = AceGUI:Create("SimpleGroup"); row:SetLayout("Flow"); row:SetFullWidth(true)
            for i=1,#cols do local lab=AceGUI:Create("Label"); lab:SetText(cols[i]); lab:SetWidth(WIDTHS[i]); row:AddChild(lab) end
            local btn = AceGUI:Create("Button"); btn:SetText("X"); btn:SetWidth(45)
            btn:SetCallback("OnClick", function() ADDON:RemoveGuild(gName or key, r); container:Fire("Aegis_Refresh"); end)
            row:AddChild(btn); scroll:AddChild(row)
        end

    else -- realms
        local keys = toSortedKeys(ADDON.db.profile.realms)
        if #keys == 0 then
            local lbl = AceGUI:Create("Label"); lbl:SetText("No realms blacklisted."); lbl:SetFullWidth(true)
            scroll:AddChild(lbl); return
        end
        for _, realm in ipairs(keys) do
            local v = ADDON.db.profile.realms[realm]
            local dateStr = (v.addedAtStr and v.addedAtStr ~= "") and v.addedAtStr or fmtDateTime(v.addedAtTS or v.addedAt)
            local cols = { "-", realm, v.type or "N/A", v.category or "N/A", dateStr or "", v.reason or "" }
            local row = AceGUI:Create("SimpleGroup"); row:SetLayout("Flow"); row:SetFullWidth(true)
            for i=1,#cols do local lab=AceGUI:Create("Label"); lab:SetText(cols[i]); lab:SetWidth(WIDTHS[i]); row:AddChild(lab) end
            local btn = AceGUI:Create("Button"); btn:SetText("X"); btn:SetWidth(45)
            btn:SetCallback("OnClick", function() ADDON:RemoveRealm(realm); container:Fire("Aegis_Refresh"); end)
            row:AddChild(btn); scroll:AddChild(row)
        end
    end
end

-- -------------------------------------------------------
-- Settings Tab
-- -------------------------------------------------------
local function refreshSettings(container)
    container:ReleaseChildren()

    local grp = AceGUI:Create("InlineGroup"); grp:SetTitle("Visuals"); grp:SetFullWidth(true); grp:SetLayout("Flow")

    local cbEnable = AceGUI:Create("CheckBox"); cbEnable:SetLabel("Enable LFG highlighting")
    cbEnable:SetValue(ADDON.db.profile.settings.enableLFGHighlight)
    cbEnable:SetCallback("OnValueChanged", function(_,_,val) ADDON.db.profile.settings.enableLFGHighlight = not not val; ADDON:RefreshLFGHighlights() end)
    grp:AddChild(cbEnable)

    local cbTT = AceGUI:Create("CheckBox"); cbTT:SetLabel("Show blacklist reason on tooltip")
    cbTT:SetValue(ADDON.db.profile.settings.showTooltips)
    cbTT:SetCallback("OnValueChanged", function(_,_,val) ADDON.db.profile.settings.showTooltips = not not val end)
    grp:AddChild(cbTT)

    local note = AceGUI:Create("Label"); note:SetFullWidth(true)
    note:SetText("|cffaaaaaaLFG highlight color is fixed to red.|r")
    grp:AddChild(note)

    container:AddChild(grp)

    -- Lists editor
    local lst = AceGUI:Create("InlineGroup"); lst:SetTitle("Lists (extensible)"); lst:SetFullWidth(true); lst:SetLayout("Flow"); container:AddChild(lst)

    local function buildListEditor(label, key)
        local box = AceGUI:Create("InlineGroup"); box:SetTitle(label); box:SetLayout("Flow"); box:SetFullWidth(true)
        local eb = AceGUI:Create("MultiLineEditBox"); eb:SetLabel("Values (one per line)"); eb:SetNumLines(6); eb:SetFullWidth(true)
        eb:SetText(table.concat(ADDON.db.profile.settings.lists[key] or {}, "\n")); box:AddChild(eb)
        local btn = AceGUI:Create("Button"); btn:SetText("Save"); btn:SetWidth(100)
        btn:SetCallback("OnClick", function()
            local text = eb:GetText() or ""; local list = {}
            for line in text:gmatch("[^\r\n]+") do table.insert(list, (line:gsub("^%s+",""):gsub('%s+$',''))) end
            ADDON.db.profile.settings.lists[key] = list
            if ADDON.Print then ADDON:Print(("Updated %s list (%d values)."):format(label, #list)) end
        end)
        box:AddChild(btn); return box
    end
    lst:AddChild(buildListEditor("Types", "types"))
    lst:AddChild(buildListEditor("Categories", "categories"))

    -- Defaults
    local def = ADDON.db.profile.settings.defaults or { type = "N/A", category = "N/A" }
    local defGrp = AceGUI:Create("InlineGroup"); defGrp:SetTitle("Defaults (used when adding from context menu)"); defGrp:SetFullWidth(true); defGrp:SetLayout("Flow")
    local valsT = valuesFromArray(ADDON.db.profile.settings.lists.types)
    local valsC = valuesFromArray(ADDON.db.profile.settings.lists.categories)
    local ddT = AceGUI:Create("Dropdown"); ddT:SetLabel("Default Type"); ddT:SetList(valsT); ddT:SetValue(def.type or "N/A"); ddT:SetWidth(200); defGrp:AddChild(ddT)
    local ddC = AceGUI:Create("Dropdown"); ddC:SetLabel("Default Category"); ddC:SetList(valsC); ddC:SetValue(def.category or "N/A"); ddC:SetWidth(200); defGrp:AddChild(ddC)
    local save = AceGUI:Create("Button"); save:SetText("Save Defaults"); save:SetWidth(140)
    save:SetCallback("OnClick", function()
        ADDON.db.profile.settings.defaults = ADDON.db.profile.settings.defaults or {}
        ADDON.db.profile.settings.defaults.type = ddT:GetValue()
        ADDON.db.profile.settings.defaults.category = ddC:GetValue()
        if ADDON.Print then ADDON:Print("Saved default Type/Category.") end
    end)
    defGrp:AddChild(save); container:AddChild(defGrp)
end

-- -------------------------------------------------------
-- Tab Group
-- -------------------------------------------------------
local function buildTabs(container)
    local tabs = AceGUI:Create("TabGroup")
    tabs:SetFullWidth(true); tabs:SetFullHeight(true)
    tabs:SetTabs({
        { text = "Players", value = "players" },
        { text = "Guilds",  value = "guilds"  },
        { text = "Realms",  value = "realms"  },
        { text = "Settings",value = "settings"},
    })

    local function selectTab(val)
        if val == "players" then buildTable(tabs, "players")
        elseif val == "guilds" then buildTable(tabs, "guilds")
        elseif val == "realms" then buildTable(tabs, "realms")
        elseif val == "settings" then refreshSettings(tabs)
        end
    end

    tabs:SetCallback("OnGroupSelected", function(widget, _, val)
        widget:SetUserData("last_selected", val)
        selectTab(val)
    end)

    -- Refresh callbacks: rely on stored last_selected (never call GetSelectedTab)
    local function doRefresh()
        local val = tabs:GetUserData("last_selected") or "players"
        selectTab(val)
    end
    tabs:SetCallback("Aegis_Refresh", doRefresh)

    tabs:SetUserData("last_selected", "players")
    tabs:SelectTab("players")
    container:AddChild(tabs)
end

-- Public entry points (both names for safety during transition)
function _G.Aegis_OpenUI()
    if ui then ui:Show(); return end
    ui = AceGUI:Create("Frame")
    ui:SetTitle("Aegis"); ui:SetStatusText("Players • Guilds • Realms")
    ui:SetLayout("Fill"); ui:SetWidth(1200); ui:SetHeight(750)
    if ui.frame and ui.frame.SetResizeBounds then ui.frame:SetResizeBounds(700, 440)
    elseif ui.frame and ui.frame.SetMinResize then ui.frame:SetMinResize(700, 440) end
    buildTabs(ui)
end
