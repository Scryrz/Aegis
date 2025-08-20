--[[-----------------------------------------------------------------------------
Aegis - UI_Bin.lua
Details Framework recreation modeled after DetailsKeystoneInfoFrame.

Fixes:
 - removes extra margin around the scroll area
 - hides all lines when there's no data (only mark lines InUse when entry exists)
Update:
 - removed Guild column from header, rows, and refresh logic
 - headers span the frame interior; Actions column flush with scrollbar
-----------------------------------------------------------------------------]]--

local addonName = ...
local AGS = LibStub("AceAddon-3.0"):GetAddon("Aegis", true)
local Bin = AGS and AGS.Bin or _G.AegisBin

-- Prefer embedded DetailsFramework; fallback to LibDFramework-1.0 if present
local DF = _G.DetailsFramework or (LibStub and LibStub("LibDFramework-1.0", true))
if not DF then
  function _G.AegisBin_Open()
    if AGS and AGS.Print then AGS:Print("DetailsFramework not available; Bin UI cannot open.") end
  end
  return
end

-- =============================================================================
-- Layout / visuals (match DetailsKeystoneInfoFrame proportions)
-- =============================================================================
local FRAME_NAME           = "AegisDFBinFrame"
local FRAME_W, FRAME_H     = 650, 499 -- Details-size window
local HEADER_Y             = -25
local LINE_HEIGHT          = 21
local LINE_AMOUNT          = 24

-- Scrollbox sizing copied from the Details sample so the bar sits at the inner edge
local SCROLL_W             = FRAME_W - 10
local SCROLL_H             = FRAME_H - 50

-- Column widths must add up to SCROLL_W to avoid any gap before the scrollbar
local NAME_W               = 200
local REALM_W              = 160
local ADDED_W              = 150
local ACTIONS_W            = (SCROLL_W - (NAME_W + REALM_W + ADDED_W)) + 1 -- fills to scrollbar

local ROW_BG               = {0, 0, 0, 0.28}
local ROW_BG_ENTER         = {0.18, 0.18, 0.18, 0.40}

local HEADER_COLS = {
  {text = "Name",    width = NAME_W,    name = "name",    canSort = true, dataType = "string", order = "DESC", offset = 0},
  {text = "Realm",   width = REALM_W,   name = "realm",   canSort = true, dataType = "string", order = "DESC", offset = 0},
  -- make "Added" the default selected column with DESC order (like Details does for a default)
  {text = "Added",   width = ADDED_W,   name = "tsAdded", canSort = true, dataType = "string", selected = true, order = "DESC", offset = 0},
  {text = "Actions", width = ACTIONS_W, name = "actions", canSort = false, offset = 0},
}

local HEADER_OPTIONS = {
  padding = 1,
  header_backdrop_color = {.30, .30, .30, .80},
  header_backdrop_color_selected = {.90, .90, 0, 1},
  use_line_separators = false,
  line_separator_color = {.1, .1, .1, .5},
  line_separator_width = 1,
  line_separator_height = FRAME_H - 30,
  line_separator_gap_align = true,
  header_click_callback = headerOnClickCallback,
}

-- =============================================================================
-- Helpers
-- =============================================================================
local function fmtDateTime(ts) return ts and date("%Y-%m-%d %H:%M", ts) or "" end

-- default sort points to "Added" (column 3)
local currentSort = { col = 3, order = -1 } -- desc

-- sort using the same pattern Details uses:
-- the header click only triggers a refresh; the refresh reads Header:GetSelectedColumn()
local function sortData(entries)
  -- default if header isn't instantiated yet
  local colIndex, orderStr = 3, "DESC"
  if _G[FRAME_NAME] and _G[FRAME_NAME].Header and _G[FRAME_NAME].Header.GetSelectedColumn then
    local c, o = _G[FRAME_NAME].Header:GetSelectedColumn()
    if type(c) == "number" then colIndex = c end
    if type(o) == "string"  then orderStr = o end
  end

  -- map header column to our entry keys
  local key
  if colIndex == 1 then
    key = "name"
  elseif colIndex == 2 then
    key = "realm"
  else
    key = "tsAdded"
  end

  local desc = (orderStr == "DESC")

  local function sval(v) return (v and tostring(v):lower()) or "" end

  table.sort(entries, function(a, b)
    if not a and not b then return false end
    if not a then return false end
    if not b then return true end

    if key == "tsAdded" then
      local av = tonumber(a.tsAdded or 0) or 0
      local bv = tonumber(b.tsAdded or 0) or 0
      return desc and (av > bv) or (av < bv)
    else
      local av = sval(a[key])
      local bv = sval(b[key])
      if av == bv then
        -- stable-ish by name
        local an = sval(a.name)
        local bn = sval(b.name)
        return desc and (an > bn) or (an < bn)
      end
      return desc and (av > bv) or (av < bv)
    end
  end)
end

local function getData()
  local src = (Bin and Bin.GetEntries and Bin:GetEntries()) or {}
  local t = {}
  for i = 1, #src do t[i] = src[i] end
  if #t > 1 then sortData(t) end
  return t
end

-- =============================================================================
-- UI object
-- =============================================================================
local UI = { frame = nil, header = nil, scroll = nil }

function UI:Refresh()
  if not self.scroll then return end

  -- copy current bin entries (unsorted)
  local src = (Bin and Bin.GetEntries and Bin:GetEntries()) or {}
  local entries = {}
  for i = 1, #src do
    entries[i] = src[i]
  end

  -- Details-style: read column + textual order ("ASC"|"DESC") from the header on refresh
  local colIndex, order = 3, "DESC" -- default: Added (DESC) like our initial selection
  if self.header and self.header.GetSelectedColumn then
    local c, o = self.header:GetSelectedColumn()
    if type(c) == "number" then colIndex = c end
    if type(o) == "string"  then order = o end
  end

  -- map selected column to our table keys (Name, Realm, Added)
  local key
  if colIndex == 1 then
    key = "name"
  elseif colIndex == 2 then
    key = "realm"
  else
    key = "tsAdded"
  end

  -- comparator: use > for DESC and < for ASC (identical behavior to the sample)
  if key == "tsAdded" then
    if order == "DESC" then
      table.sort(entries, function(a, b)
        local av = tonumber(a and a.tsAdded or 0) or 0
        local bv = tonumber(b and b.tsAdded or 0) or 0
        return av > bv
      end)
    else
      table.sort(entries, function(a, b)
        local av = tonumber(a and a.tsAdded or 0) or 0
        local bv = tonumber(b and b.tsAdded or 0) or 0
        return av < bv
      end)
    end
  else
    local function sval(v) return (v and tostring(v)) or "" end
    if order == "DESC" then
      table.sort(entries, function(a, b)
        local av = sval(a and a[key])
        local bv = sval(b and b[key])
        if av == bv then
          -- small tiebreaker by name, mirrors Details' stable feel
          return sval(a and a.name) > sval(b and b.name)
        end
        return av > bv
      end)
    else
      table.sort(entries, function(a, b)
        local av = sval(a and a[key])
        local bv = sval(b and b[key])
        if av == bv then
          return sval(a and a.name) < sval(b and b.name)
        end
        return av < bv
      end)
    end
  end

  self.scroll:SetData(entries)
  self.scroll:Refresh()
end

-- =============================================================================
-- Scroll line factory & refresher (only mark lines InUse when data exists)
-- =============================================================================
local function createLine(scroll, index)
  local line = CreateFrame("button", scroll:GetName() .. "Line" .. index, scroll, "BackdropTemplate")
  line:SetSize(scroll:GetWidth() - 2, LINE_HEIGHT)
  -- 1px spacing between rows
  line:SetPoint("TOPLEFT", scroll, "TOPLEFT", 1, -((index - 1) * (LINE_HEIGHT + 1)) - 1)

  line:SetBackdrop({bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tile = true, tileSize = 64})
  line:SetBackdropColor(unpack(ROW_BG))

  DF:Mixin(line, DF.HeaderFunctions)
  line:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(ROW_BG_ENTER)) end)
  line:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(ROW_BG)) end)

  -- white row text
  local nameText  = DF:CreateLabel(line, "", nil, "white")
  local realmText = DF:CreateLabel(line, "", nil, "white")
  local addedText = DF:CreateLabel(line, "", nil, "white")

  local function actionsProvider(dd)
    local items, full = {}, dd.__full
    if not full then return items end

    local function addToBlacklist()
      local def = (AGS.db and AGS.db.profile and AGS.db.profile.settings and AGS.db.profile.settings.defaults)
                  or { type = "N/A", category = "N/A" }
      AGS.Aegis_AddPlayer(full, "Added from Bin", { type = def.type, category = def.category })
      if Bin and Bin.RemoveFromSession then Bin:RemoveFromSession(full) end
      if UI and UI.Refresh then UI:Refresh() end
    end

    local function removeFromBin()
      if Bin and Bin.RemoveFromSession then Bin:RemoveFromSession(full) end
      if UI and UI.Refresh then UI:Refresh() end
    end

    items[1] = {label = "Add to Blacklist", value = "add", onclick = addToBlacklist}
    items[2] = {label = "Remove from Bin",  value = "remove", onclick = removeFromBin}
    return items
  end

  -- set dropdown width to exactly the Actions column width to eliminate the gap
  local actionsDD = DF:CreateDropDown(
    line, actionsProvider, 1, 115, 20, --ACTIONS_W, 20 instead of 100, 20
    "$parentActionsDropdown" .. index, nil, DF:GetTemplate("dropdown", "OPTIONS_DROPDOWN_TEMPLATE")
  )

  -- header-aligned layout
  line:AddFrameToHeaderAlignment(nameText)
  line:AddFrameToHeaderAlignment(realmText)
  line:AddFrameToHeaderAlignment(addedText)
  line:AddFrameToHeaderAlignment(actionsDD)
  line:AlignWithHeader(_G[FRAME_NAME].Header, "left")

  -- store refs for refresh
  line.NameText        = nameText
  line.RealmText       = realmText
  line.AddedText       = addedText
  line.ActionsDropdown = actionsDD

  return line
end

-- Only fetch a line when an entry exists (no empty rows)
local function refreshLines(scroll, data, offset, totalLines)
  for i = 1, totalLines do
    local index = i + offset
    local entry = data[index]

    if entry then
      local line = scroll:GetLine(i) -- marks InUse
      line.NameText.text  = entry.name or "-"
      line.RealmText.text = entry.realm or "-"
      line.AddedText.text = fmtDateTime(entry.tsAdded)
      line.ActionsDropdown.__full = entry.full
      line.ActionsDropdown:Refresh()

      -- NEW: reset dropdown selection to null on each refresh
      line.ActionsDropdown:SetValue(nil)
      if line.ActionsDropdown.NoOptionSelected then
        line.ActionsDropdown:NoOptionSelected()
      end
    end

    -- when no entry: don't fetch the line; DF keeps it hidden
  end
end

-- =============================================================================
-- Public entry (global)
-- =============================================================================
function _G.AegisBin_Open()
  -- Reuse the existing frame & header on reopen; do not rebuild (Details pattern)
  if UI.frame then
    UI.frame:Show()
    UI:Refresh()
    return
  end

  -- One-time build path (create frame, header, scroll, lines)
  local f = DF:CreateSimplePanel(UIParent, FRAME_W, FRAME_H, "Aegis - Bin", FRAME_NAME)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

  -- Details-style: header click just refreshes; sorting is read from GetSelectedColumn()
  local function headerOnClickCallback(headerFrame, columnHeader)
    UI:Refresh()
  end

  local headerOpts = {}
  for k, v in pairs(HEADER_OPTIONS) do headerOpts[k] = v end
  headerOpts.header_click_callback = headerOnClickCallback

  -- Header background stretches to the frame edges,
  -- but column widths add up to SCROLL_W so the last column sits flush with the scrollbar.
  local header = DF:CreateHeader(f, HEADER_COLS, headerOpts, FRAME_NAME .. "Header")
  header:SetPoint("TOPLEFT",  f, "TOPLEFT",  2,  HEADER_Y)
  header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2,  HEADER_Y)
  f.Header = header

  -- ScrollBox: use Details sample sizing and offsets so the bar hugs the inner edge
  local scroll = DF:CreateScrollBox(f, "$parentScroll", refreshLines, {}, SCROLL_W, SCROLL_H, LINE_AMOUNT, LINE_HEIGHT)
  DF:ReskinSlider(scroll)
  if scroll.ScrollBar and scroll.ScrollBar.AdjustPointsOffset then
    scroll.ScrollBar:AdjustPointsOffset(-23, -1)
  end

  -- enable mouse wheel (CLAMPED to content)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local stepLines = 3
    local currentOffset = tonumber(self:GetOffsetFaux()) or 0
    local total = (self.data and #self.data) or 0
    local visible = self.LineAmount or 0
    local maxOffset = 0
    if total > 0 and visible > 0 then
      maxOffset = math.max(0, total - visible)
    end

    local newOffset = currentOffset + (delta < 0 and stepLines or -stepLines)
    if newOffset < 0 then newOffset = 0 end
    if newOffset > maxOffset then newOffset = maxOffset end

    -- Faux scroll expects pixel amount; multiply by line height
    self:OnVerticalScrollFaux(newOffset * self.LineHeight, self.LineHeight, self.Refresh)
  end)

  -- anchor to header exactly as in the sample
  scroll:SetPoint("topleft",  f.Header, "bottomleft",  -1, -1)
  scroll:SetPoint("topright", f.Header, "bottomright",  0, -1)

  f.ScrollBox = scroll

  -- compute visible lines to match the scrollbox height (accounts for 1px row gap)
  local visible = math.max(1, math.floor((scroll:GetHeight()) / (LINE_HEIGHT + 1)))
  scroll.LineAmount = visible

  -- create visible lines before first refresh
  for i = 1, scroll.LineAmount do
    scroll:CreateLine(createLine)
  end

  UI.frame, UI.header, UI.scroll = f, header, scroll

  if Bin and Bin._AttachUI then Bin:_AttachUI(UI) end

  UI:Refresh()
end
