--[[-----------------------------------------------------------------------------
Aegis - Bin.lua
Logic-only temporary roster "Bin" for the current group session.
No event registration; Core.lua drives the lifecycle.
-----------------------------------------------------------------------------]]--

local addonName = ...
local AGS = LibStub("AceAddon-3.0"):GetAddon("Aegis", true)

---@class AegisBin
local Bin = {}
AGS.Bin = Bin
_G.AegisBin = Bin -- optional global for loose coupling

-- Session state (reset on StartSession)
Bin._entries = nil         -- array of { full, name, realm, guild, tsAdded }
Bin._index   = nil         -- map full -> entry (for O(1) dedupe)
Bin._removed = nil         -- set full -> true (do-not-readd this session)
Bin._ui      = nil         -- UI handle (set by UI_Bin)

-- -----------------------------
-- Helpers
-- -----------------------------
local function NowTS() return time() end
local function NormalizeFull(name, realm)
  if not name or name == "" then return nil end
  if realm and realm ~= "" then return name .. "-" .. realm end
  local pr = GetNormalizedRealmName() or GetRealmName()
  return name .. "-" .. (pr or "")
end

local function IterateRoster(addFunc)
  local n = GetNumGroupMembers() or 0
  if n <= 0 then return end
  local raid = IsInRaid()
  local unitPrefix = raid and "raid" or "party"
  local total = raid and n or (n - 1)
  for i = 1, total do
    local unit = unitPrefix .. i
    if UnitExists(unit) then
      local name, realm = UnitFullName(unit)
      if name then
        local full = NormalizeFull(name, realm)
        if full and not UnitIsUnit(unit, "player") then
          local guild = GetGuildInfo(unit)
          addFunc(name, realm or "", guild or "", full)
        end
      end
    end
  end
end

-- -----------------------------
-- Public API
-- -----------------------------
function Bin:StartSession()
  self._entries = {}
  self._index   = {}
  self._removed = {}
  -- UI may choose to refresh on demand; no auto-open here
end

function Bin:EndSession()
  -- Keep entries so the UI can display them when auto-opened after group leaves.
  -- Do NOT clear removed set yet (prevents accidental re-add if group bounces).
end

function Bin:IngestRosterSnapshot()
  if not self._entries then return end
  IterateRoster(function(name, realm, guild, full)
    if not self._removed[full] and not self._index[full] then
      local e = {
        full   = full,
        name   = name,
        realm  = realm ~= "" and realm or (GetNormalizedRealmName() or GetRealmName() or ""),
        guild  = (guild and guild ~= "") and guild or "-",
        tsAdded= NowTS(),
      }
      table.insert(self._entries, e)
      self._index[full] = e
    end
  end)
  if self._ui and self._ui.Refresh then self._ui:Refresh() end
end

function Bin:RemoveFromSession(full)
  if not full or not self._entries then return end
  self._removed[full] = true
  if self._index[full] then
    -- delete from array
    for i, e in ipairs(self._entries) do
      if e.full == full then
        table.remove(self._entries, i)
        break
      end
    end
    self._index[full] = nil
  end
  if self._ui and self._ui.Refresh then self._ui:Refresh() end
end

function Bin:GetEntries() return self._entries or {} end

-- UI hookup
function Bin:_AttachUI(uiObj) self._ui = uiObj end

-- Open window (delegates to UI module)
function Bin:OpenFrame()
  if _G.AegisBin_Open then _G.AegisBin_Open()
  elseif AGS and AGS.Print then AGS:Print("Bin UI not loaded.") end
end
