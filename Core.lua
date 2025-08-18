--[[-----------------------------------------------------------------------------
Aegis - Core.lua
-----------------------------------------------------------------------------]]--

local addonName = ...
---@class AGS : AceAddon, AceConsole, AceEvent
local AGS = LibStub("AceAddon-3.0"):NewAddon("Aegis", "AceConsole-3.0", "AceEvent-3.0")
local AceDB  = LibStub("AceDB-3.0")

-- =============================================================================
-- Defaults / DB
-- =============================================================================
local DEFAULT_TYPES = { "Mythic+", "Raid", "PvP", "World", "Other", "N/A" }
local DEFAULT_CATS  = { "Bad", "Toxic", "Leaver", "Other", "N/A" }

-- fixed red highlight for LFG overlays
local HIGHLIGHT_COLOR = { r = 1, g = 0, b = 0, a = 0.25 }

local defaults = {
  profile = {
    players = {},   -- ["Name-Realm"] = { reason, type, category, addedBy, addedAtTS, addedAtStr }
    guilds  = {},   -- ["Guild-Realm"] = { reason, type, category, addedBy, addedAtTS, addedAtStr, members = { ["Name-Realm"]=true } }
    realms  = {},   -- ["Realm"] = { reason, type, category, addedBy, addedAtTS, addedAtStr }
    settings = {
      enableLFGHighlight = true,
      highlightColor = { r = 1, g = 0, b = 0, a = 0.25 }, -- kept for backwards-compat only
      showTooltips = true,
      lists = { types = DEFAULT_TYPES, categories = DEFAULT_CATS },
      defaults = { type = "N/A", category = "N/A" },
    },
  }
}

-- UI entry point (Widgets.lua calls this)
function AGS:OpenUI()
  if _G.Aegis_OpenUI then _G.Aegis_OpenUI(self)
  else self:Print("AceGUI-3.0 UI not loaded. Ensure Widgets.lua loads after Core.lua in the TOC.") end
end

-- =============================================================================
-- Utils
-- =============================================================================
local function GetPlayerRealm()
  local realm = GetNormalizedRealmName()
  if not realm then
    local _, r = UnitFullName("player")
    realm = r or GetRealmName()
  end
  return realm
end

function AGS:NormalizePlayerName(name)
  if not name or name == "" then return nil end
  if name:find("-", 1, true) then return name end
  return string.format("%s-%s", name, GetPlayerRealm())
end

function AGS:NormalizeRealm(realm) return realm or "" end
function AGS:SplitNameRealm(full) if not full then return nil, nil end local n, r = strsplit("-", full); return n, r end
function AGS:GuildKey(guildName, realm) realm = realm or GetPlayerRealm(); return guildName .. "-" .. realm end

local function now() return time() end
local function fmt(ts) return date("%Y-%m-%d %H:%M", ts or time()) end -- 24h format

-- fire a lightweight message that UIs can listen to
local function NotifyDBChanged(self, scope, op, key)
  if self.SendMessage then
    self:SendMessage("Aegis_DB_UPDATED", { scope = scope, op = op, key = key })
  end
end

-- =============================================================================
-- Query / Mutate
-- =============================================================================
function AGS:IsPlayerBlacklisted(name, opts)
  if not name then return nil end
  local db = self.db.profile
  local e = db.players[name]
  if e then return e, "player" end

  local _, nmRealm = self:SplitNameRealm(name)
  local realm = (opts and opts.realm) or nmRealm
  if realm and db.realms[realm] then return db.realms[realm], "realm" end

  local guildName = opts and opts.guildName
  if guildName then
    local gkey = self:GuildKey(guildName, realm)
    if db.guilds[gkey] then return db.guilds[gkey], "guild" end
  else
    for _, g in pairs(db.guilds) do
      if g.members and g.members[name] then return g, "guild" end
    end
  end
  return nil
end

local function applyDefaultsForMeta(self, entry)
  local def = self.db.profile.settings.defaults or { type="N/A", category="N/A" }
  if entry.type == nil then entry.type = def.type end
  if entry.category == nil then entry.category = def.category end
end

local function initTimestampFields(entry, existing)
  if existing and existing.addedAtTS then
    entry.addedAtTS  = existing.addedAtTS
    entry.addedAtStr = existing.addedAtStr or fmt(existing.addedAtTS)
  else
    entry.addedAtTS  = now()
    entry.addedAtStr = fmt(entry.addedAtTS)
  end
end

function AGS:AddPlayer(name, reason, meta)
  local normalized = self:NormalizePlayerName(name); if not normalized then return end
  local prev = self.db.profile.players[normalized]
  local e = {
    reason   = reason or (prev and prev.reason) or "No reason given",
    addedBy  = prev and prev.addedBy or UnitName("player"),
    type     = meta and meta.type or (prev and prev.type),
    category = meta and meta.category or (prev and prev.category),
  }
  initTimestampFields(e, prev)
  applyDefaultsForMeta(self, e)
  self.db.profile.players[normalized] = e
  self:Print(("Player %s added to blacklist."):format(normalized))
  NotifyDBChanged(self, "players", "add", normalized)
  self:RefreshLFGHighlights()
end

function AGS:RemovePlayer(name)
  local normalized = self:NormalizePlayerName(name); if not normalized then return end
  self.db.profile.players[normalized] = nil
  self:Print(("Player %s removed from blacklist."):format(normalized))
  NotifyDBChanged(self, "players", "remove", normalized)
  self:RefreshLFGHighlights()
end

function AGS:AddRealm(realmName, reason, meta)
  local realm = self:NormalizeRealm(realmName); if realm == "" then return end
  local prev = self.db.profile.realms[realm]
  local e = {
    reason   = reason or (prev and prev.reason) or "No reason given",
    addedBy  = prev and prev.addedBy or UnitName("player"),
    type     = meta and meta.type or (prev and prev.type),
    category = meta and meta.category or (prev and prev.category),
  }
  initTimestampFields(e, prev)
  applyDefaultsForMeta(self, e)
  self.db.profile.realms[realm] = e
  self:Print(("Realm %s added to blacklist."):format(realm))
  NotifyDBChanged(self, "realms", "add", realm)
  self:RefreshLFGHighlights()
end

function AGS:RemoveRealm(realmName)
  local realm = self:NormalizeRealm(realmName); if realm == "" then return end
  self.db.profile.realms[realm] = nil
  self:Print(("Realm %s removed from blacklist."):format(realm))
  NotifyDBChanged(self, "realms", "remove", realm)
  self:RefreshLFGHighlights()
end

function AGS:AddGuild(guildName, realmName, reason, meta)
  if not guildName or guildName == "" then return end
  local gkey = self:GuildKey(guildName, realmName)
  local prev = self.db.profile.guilds[gkey]
  self.db.profile.guilds[gkey] = self.db.profile.guilds[gkey] or { members = {} }
  local g = self.db.profile.guilds[gkey]
  g.reason   = reason or g.reason or "No reason given"
  g.addedBy  = g.addedBy or UnitName("player")
  g.type     = (meta and meta.type) or g.type
  g.category = (meta and meta.category) or g.category
  initTimestampFields(g, prev)
  applyDefaultsForMeta(self, g)
  self:Print(("Guild %s added/updated in blacklist."):format(gkey))
  NotifyDBChanged(self, "guilds", "add", gkey)
  self:RefreshLFGHighlights()
end

function AGS:RemoveGuild(guildName, realmName)
  local gkey = self:GuildKey(guildName, realmName)
  self.db.profile.guilds[gkey] = nil
  self:Print(("Guild %s removed from blacklist."):format(gkey))
  NotifyDBChanged(self, "guilds", "remove", gkey)
  self:RefreshLFGHighlights()
end

function AGS:AddMemberToBlacklistedGuild(guildName, realmName, playerNameNormalized)
  local gkey = self:GuildKey(guildName, realmName)
  local g = self.db.profile.guilds[gkey]; if not g then return end
  g.members = g.members or {}
  g.members[playerNameNormalized] = true
end

-- =============================================================================
-- Bin session reference/state (set in OnInitialize)
-- =============================================================================
local Bin -- resolved to AGS.Bin or _G.AegisBin
local BIN_STATE = { inGroup = nil } -- nil=unknown, true=grouped, false=solo

-- =============================================================================
-- Group scan (+ Bin session fanout)
-- =============================================================================
function AGS:ScanGroupMembers()
  -- Existing behavior: track blacklisted guild members we’re grouped with
  local num = GetNumGroupMembers()
  if num and num > 0 then
    local raid = IsInRaid()
    local unitPrefix = raid and "raid" or "party"
    local total = raid and num or (num - 1)
    for i = 1, total do
      local unit = unitPrefix .. i
      if UnitExists(unit) then
        local name, realm = UnitFullName(unit)
        if name then
          local full = realm and realm ~= "" and (name.."-"..realm) or self:NormalizePlayerName(name)
          local guildName = GetGuildInfo(unit)
          local _, r = self:SplitNameRealm(full)
          if guildName and r then
            local gkey = self:GuildKey(guildName, r)
            if self.db.profile.guilds[gkey] then
              self:AddMemberToBlacklistedGuild(guildName, r, full)
            end
          end
        end
      end
    end
  end

  -- =========================
  -- Bin session lifecycle
  -- =========================
  local grouped = (IsInGroup() or IsInRaid()) and (GetNumGroupMembers() or 0) > 0

  if BIN_STATE.inGroup == nil then
    -- first tick after login/reload
    BIN_STATE.inGroup = grouped
    if grouped and Bin and Bin.StartSession then
      Bin:StartSession()
      if Bin.IngestRosterSnapshot then Bin:IngestRosterSnapshot() end
    end
    return
  end

  if BIN_STATE.inGroup and not grouped then
    -- grouped -> solo: end session and auto-open
    BIN_STATE.inGroup = false
    if Bin and Bin.EndSession then Bin:EndSession() end
    if Bin and Bin.OpenFrame then Bin:OpenFrame() end
    return
  end

  if (not BIN_STATE.inGroup) and grouped then
    -- solo -> grouped: start and seed
    BIN_STATE.inGroup = true
    if Bin and Bin.StartSession then Bin:StartSession() end
    if Bin and Bin.IngestRosterSnapshot then Bin:IngestRosterSnapshot() end
    return
  end

  if grouped then
    -- still grouped: append newcomers (Bin handles dedupe/removed)
    if Bin and Bin.IngestRosterSnapshot then Bin:IngestRosterSnapshot() end
  end
end

-- =============================================================================
-- Lifecycle
-- =============================================================================
function AGS:OnInitialize()
  self.db = AceDB:New("AegisDB", defaults, true)

  local s = self.db.profile.settings
  s.lists = s.lists or {}
  s.lists.types      = (s.lists.types and #s.lists.types > 0) and s.lists.types or DEFAULT_TYPES
  s.lists.categories = (s.lists.categories and #s.lists.categories > 0) and s.lists.categories or DEFAULT_CATS
  s.defaults = s.defaults or { type = "N/A", category = "N/A" }

  self:RegisterChatCommand("aegis", "HandleSlash")

  -- LFG highlight refresh events
  self:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED", "RefreshLFGHighlights")
  self:RegisterEvent("LFG_LIST_APPLICANT_UPDATED", "RefreshLFGHighlights")
  self:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED", "RefreshLFGHighlights")
  self:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED", "RefreshLFGHighlights")

  -- Group roster
  self:RegisterEvent("GROUP_ROSTER_UPDATE", "ScanGroupMembers")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "ScanGroupMembers")

  -- Tooltips + Context menu + LFG name prefix hook
  self:InstallTooltipModule()
  self:InstallContextMenu()
  self:InstallLFGNamePrefixer()

  -- Resolve Bin module if present
  Bin = (self.Bin or _G.AegisBin)

  self:Print("Aegis initialized. Use /aegis for commands.")
end

function AGS:OnEnable() self:RefreshLFGHighlights() end

-- =============================================================================
-- Slash
-- =============================================================================
function AGS:HandleSlash(input)
  input = input and (input:gsub('^%s+',''):gsub('%s+$','')) or ""
  if input == "" or input == "help" then
    self:Print("Commands:")
    self:Print("/aegis ui")
    self:Print("/aegis bin")
    self:Print('/aegis add player Name-Realm [reason]')
    self:Print('/aegis add guild "Guild Name" [Realm] [reason]')
    self:Print('/aegis add realm RealmName [reason]')
    self:Print('/aegis remove player|guild|realm <key>')
    self:Print('/aegis list [players|guilds|realms]')
    return
  end
  if input == "ui" then self:OpenUI(); return end
  if input == "bin" then
    local BinRef = (self.Bin or _G.AegisBin)
    if BinRef and BinRef.OpenFrame then BinRef:OpenFrame() else self:Print("Bin UI not available.") end
    return
  end
  self:Print("Unknown command. Try /aegis help")
end

-- =============================================================================
-- LFG highlighting overlays + name prefixing
-- =============================================================================
local function getOverlay(frame)
  if not frame then return end
  if not frame.AegisOverlay then
    local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    t:SetAllPoints(true)
    frame.AegisOverlay = t
  end
  return frame.AegisOverlay
end

function AGS:SetOverlay(frame, enabled)
  local t = getOverlay(frame); if not t then return end
  if enabled then
    t:SetColorTexture(HIGHLIGHT_COLOR.r, HIGHLIGHT_COLOR.g, HIGHLIGHT_COLOR.b, HIGHLIGHT_COLOR.a)
    t:Show()
  else
    t:Hide()
  end
end

-- Helper: true if the search result’s leader/realm is blacklisted
local function IsResultBlacklisted(self, resultID)
  if not resultID then return false end
  local info = C_LFGList.GetSearchResultInfo(resultID)
  if not info or not info.leaderName then return false end
  local norm = self:NormalizePlayerName(info.leaderName)
  local entry = self:IsPlayerBlacklisted(norm)
  if not entry then
    local _, realm = self:SplitNameRealm(norm)
    if realm and self.db and self.db.profile.realms[realm] then
      entry = true
    end
  end
  return not not entry
end

-- Install a resilient hook that prefixes the visible group name text
function AGS:InstallLFGNamePrefixer()
  if self.__LFGNameHooked then return end
  self.__LFGNameHooked = true

  local PREFIX_PATTERN = "^|cffff2020BLACKLISTED|r%s*%-?%s*"
  local function stripPrefix(s) return (s or ""):gsub(PREFIX_PATTERN, "") end

  hooksecurefunc("LFGListSearchEntry_Update", function(entry)
    if not entry or not entry.Name or not entry.Name.GetText then return end

    local resultID
    if entry.GetData then
      local d = entry:GetData()
      resultID = d and d.resultID
    end
    resultID = resultID or entry.resultID
    if not resultID then return end

    local isBL = IsResultBlacklisted(AGS, resultID)

    local current = entry.Name:GetText() or ""
    local base = stripPrefix(current)

    if isBL then
      if current ~= ("|cffff2020BLACKLISTED|r - "..base) then
        entry.Name:SetText("|cffff2020BLACKLISTED|r - "..base)
      end
    else
      if base ~= current then
        entry.Name:SetText(base)
      end
    end
  end)
end

function AGS:RefreshLFGHighlights()
  if not self.db or not self.db.profile.settings.enableLFGHighlight then return end

  -- Applicants
  local viewer = LFGListFrame and LFGListFrame.ApplicationViewer
  if viewer and viewer.ScrollBox and viewer.ScrollBox.ForEachFrame then
    viewer.ScrollBox:ForEachFrame(function(row)
      local applicantID = row.applicantID
      if (not applicantID) and row.GetElementData then
        local d = row:GetElementData()
        if d then applicantID = d.applicantID end
      end
      local isBL = false
      if applicantID then
        local info = C_LFGList.GetApplicantInfo(applicantID)
        if info then
          for i = 1, info.numMembers do
            local name = C_LFGList.GetApplicantMemberInfo(applicantID, i)
            if name then
              local norm = self:NormalizePlayerName(name)
              local entry = self:IsPlayerBlacklisted(norm)
              if not entry then
                local _, realm = self:SplitNameRealm(norm)
                if realm then entry = self.db.profile.realms[realm] end
              end
              if entry then isBL = true break end
            end
          end
        end
      end
      self:SetOverlay(row, isBL)
      -- prefix is for search results only
    end)
  end

  -- Search results (leaders + realm) - overlay only; name text handled by hook
  local results = LFGListFrame and LFGListFrame.SearchPanel and LFGListFrame.SearchPanel.ResultsFrame
  if results and results.ScrollBox and results.ScrollBox.ForEachFrame then
    results.ScrollBox:ForEachFrame(function(row)
      local resultID = row.resultID
      if (not resultID) and row.GetElementData then
        local d = row:GetElementData()
        if d then resultID = d.resultID end
      end
      local isBL = IsResultBlacklisted(self, resultID)
      self:SetOverlay(row, isBL)
    end)
  end
end

-- =============================================================================
-- Tooltip Module (single injector + per-tooltip dedupe)
-- =============================================================================
do
  local function AddTooltipLines(tt, entry, sourceLabel)
    tt:AddLine(" ")
    tt:AddLine("|cffFFC000Aegis - |rBlacklisted", 1, 0, 0, false)
    if entry.type or entry.category then
      tt:AddLine(("|cffFFC000Tags:|r %s / %s"):format(entry.type or "N/A", entry.category or "N/A"), 1, 1, 1, false)
    end
    if entry.reason and entry.reason ~= "" then
      tt:AddLine("|cffFFC000Reason: |r" .. entry.reason, 1, 1, 1, false)
    end
    if entry.addedAtStr then
      tt:AddLine("|cffFFC000Added: |r" .. entry.addedAtStr, 1, 1, 1, false)
    end
    if sourceLabel and sourceLabel ~= "" then
      tt:AddLine(sourceLabel, 1, 1, 1, false)
    end
    tt:AddLine(" ")
  end

  local function AnnotateTooltip(tt, fullName, opts)
    if not tt or not fullName or fullName == "" then return end
    if not AGS.db or not AGS.db.profile.settings.showTooltips then return end
    if tt.__Aegis_Annotated == fullName then return end

    local guildName = opts and opts.guildName
    local _, realm = AGS:SplitNameRealm(fullName)

    local entry, source = AGS:IsPlayerBlacklisted(fullName, { guildName = guildName, realm = realm })
    if not entry and realm and AGS.db.profile.realms[realm] then
      entry = AGS.db.profile.realms[realm]; source = "realm"
    end
    if not entry then return end

    AddTooltipLines(tt, entry, source and ("|cffaaaaaa("..source..")|r") or nil)
    tt.__Aegis_Annotated = fullName
    tt:Show()
  end

  local function TryAnnotate_Unit(tt)
    if tt ~= GameTooltip then return end
    local _, unit = tt:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end
    local name, realm = UnitFullName(unit); if not name then return end
    local full = realm and realm ~= "" and (name.."-"..realm) or AGS:NormalizePlayerName(name)
    local guildName = GetGuildInfo(unit)
    AnnotateTooltip(tt, full, { guildName = guildName, realm = realm })
  end

  local function TryAnnotate_PlayerLink(tt, link)
    if not link or link == "" then return end
    local kind, left = link:match("^(%w+):(.+)$"); if kind ~= "player" then return end
    local pname = left and left:match("^([^:]+)"); if not pname then return end
    local full = AGS:NormalizePlayerName(pname)
    AnnotateTooltip(tt, full)
  end

  local function TryAnnotate_LFGSearch(tt, resultID)
    if not resultID then return end
    local r = C_LFGList.GetSearchResultInfo(resultID)
    if not r or not r.leaderName then return end
    local full = AGS:NormalizePlayerName(r.leaderName)
    AnnotateTooltip(tt, full)
  end

  local function TryAnnotate_LFGApplicant(btn)
    if not btn then return end
    local parent = btn:GetParent()
    local applicantID = parent and parent.applicantID
    local memberIdx   = btn.memberIdx
    if not applicantID or not memberIdx then return end
    local fullName = C_LFGList.GetApplicantMemberInfo(applicantID, memberIdx)
    if not fullName or fullName == "" then return end
    local full = AGS:NormalizePlayerName(fullName)
    AnnotateTooltip(GameTooltip, full)
  end

  function AGS:InstallTooltipModule()
    if GameTooltip and not GameTooltip.__Aegis_ResetHooked then
      GameTooltip.__Aegis_ResetHooked = true
      GameTooltip:HookScript("OnTooltipCleared", function(tt) tt.__Aegis_Annotated = nil end)
      hooksecurefunc(GameTooltip, "SetOwner", function(tt) tt.__Aegis_Annotated = nil end)
      GameTooltip:HookScript("OnHide", function(tt) tt.__Aegis_Annotated = nil end)
    end

    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
      TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, TryAnnotate_Unit)
    else
      hooksecurefunc(GameTooltip, "SetUnit", TryAnnotate_Unit)
    end

    hooksecurefunc(GameTooltip, "SetHyperlink", TryAnnotate_PlayerLink)

    hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", function(tt, resultID)
      if tt ~= GameTooltip then return end
      TryAnnotate_LFGSearch(tt, resultID)
    end)

    if type(LFGListApplicantMember_OnEnter) == "function" then
      hooksecurefunc("LFGListApplicantMember_OnEnter", function(btn)
        TryAnnotate_LFGApplicant(btn)
        GameTooltip:Show()
      end)
    end
  end
end

-- =============================================================================
-- Context Menu Integration (Menu API)
-- =============================================================================
local MENU_TAGS = {
  ["MENU_UNIT_PLAYER"]                   = true,
  ["MENU_UNIT_ENEMY_PLAYER"]             = true,
  ["MENU_UNIT_PARTY"]                    = true,
  ["MENU_UNIT_RAID_PLAYER"]              = true,
  ["MENU_UNIT_FRIEND"]                   = true,
  ["MENU_UNIT_COMMUNITIES_GUILD_MEMBER"] = true,
  ["MENU_UNIT_COMMUNITIES_MEMBER"]       = true,
  ["MENU_LFG_FRAME_SEARCH_ENTRY"]        = true,
  ["MENU_LFG_FRAME_MEMBER_APPLY"]        = true,
  ["MENU_CHAT_ROSTER_PLAYER"]            = true,
}

-- Try to extract name/realm/guild from the menu owner/context/LFG widgets.
local function ResolveContextForMenu(owner, context)
  local name, realm, guildName

  -- LFG search result entry (leader)
  if owner and owner.resultID then
    local info = C_LFGList.GetSearchResultInfo(owner.resultID)
    if info and info.leaderName then
      local n, r = info.leaderName:match("^(.-)%-(.*)$")
      name  = n or info.leaderName
      realm = r or (GetNormalizedRealmName() or GetRealmName())
    end
  -- LFG applicant member (row button with memberIdx)
  elseif owner and owner.memberIdx and owner:GetParent() and owner:GetParent().applicantID then
    local full = C_LFGList.GetApplicantMemberInfo(owner:GetParent().applicantID, owner.memberIdx)
    if full then
      local n, r = full:match("^(.-)%-(.*)$")
      name  = n or full
      realm = r or (GetNormalizedRealmName() or GetRealmName())
    end
  end

  -- Generic context (chat roster, unit menus)
  if not name and context and context.name and strsub(context.name,1,1) ~= "|" then
    name  = context.name
    realm = context.server or (GetNormalizedRealmName() or GetRealmName())
    if context.unit and UnitExists(context.unit) then
      guildName = GetGuildInfo(context.unit)
    end
  end

  -- Fallback: try owner.unit if available (unitframe menus)
  if not guildName and owner and owner.unit and UnitExists(owner.unit) then
    guildName = GetGuildInfo(owner.unit)
  end

  return name, realm, guildName
end

function AGS:InstallContextMenu()
  if not (Menu and Menu.ModifyMenu) then return end

  local function Handler(owner, root, context)
    local name, realm, guildName = ResolveContextForMenu(owner, context)
    if not name or name == "" then return end
    realm = realm or (GetNormalizedRealmName() or GetRealmName())
    local full = name .. "-" .. realm

    -- independent status checks
    local playerListed = self.db.profile.players[full] ~= nil
    local realmListed  = (realm and self.db.profile.realms[realm]) ~= nil
    local guildListed  = false
    local gkey
    if guildName and guildName ~= "" then
      gkey = self:GuildKey(guildName, realm)
      guildListed = self.db.profile.guilds[gkey] ~= nil
    end

    root:CreateDivider()
    root:CreateTitle("Aegis")

    -- Player row
    if playerListed then
      root:CreateButton("|cff00ff00Remove|r Player", function()
        self:RemovePlayer(full)
      end)
    else
      root:CreateButton("|cffff0000Add|r Player", function()
        local def = self.db.profile.settings.defaults or { type="N/A", category="N/A" }
        self:AddPlayer(full, "Added via context menu", { type = def.type, category = def.category })
      end)
    end

    -- Guild row (only if resolvable)
    if guildName and guildName ~= "" then
      if guildListed then
        root:CreateButton("|cff00ff00Remove|r Guild", function()
          self:RemoveGuild(guildName, realm)
        end)
      else
        root:CreateButton("|cffff0000Add|r Guild", function()
          local def = self.db.profile.settings.defaults or { type="N/A", category="N/A" }
          self:AddGuild(guildName, realm, "Added via context menu", { type = def.type, category = def.category })
        end)
      end
    end

    -- Realm row (realm is always known here)
    if realm and realm ~= "" then
      if realmListed then
        root:CreateButton("|cff00ff00Remove|r Realm", function()
          self:RemoveRealm(realm)
        end)
      else
        root:CreateButton("|cffff0000Add|r Realm", function()
          local def = self.db.profile.settings.defaults or { type="N/A", category="N/A" }
          self:AddRealm(realm, "Added via context menu", { type = def.type, category = def.category })
        end)
      end
    end
  end

  for tag in pairs(MENU_TAGS) do
    Menu.ModifyMenu(tag, Handler)
  end
end

-- =============================================================================
-- Public API (for Widgets.lua and external usage)
-- =============================================================================
function AGS.Aegis_AddPlayer(name, reason, meta) AGS:AddPlayer(name, reason, meta) end
function AGS.Aegis_RemovePlayer(name) AGS:RemovePlayer(name) end
function AGS.Aegis_AddGuild(guildName, realmName, reason, meta) AGS:AddGuild(guildName, realmName, reason, meta) end
function AGS.Aegis_RemoveGuild(guildName, realmName) AGS:RemoveGuild(guildName, realmName) end
function AGS.Aegis_AddRealm(realmName, reason, meta) AGS:AddRealm(realmName, reason, meta) end
function AGS.Aegis_RemoveRealm(realmName) AGS:RemoveRealm(realmName) end
function AGS.Aegis_IsPlayerBlacklisted(name, opts) return AGS:IsPlayerBlacklisted(AGS:NormalizePlayerName(name), opts) end
function AGS.Aegis_OpenUI() AGS:OpenUI() end
