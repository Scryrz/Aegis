--[[-----------------------------------------------------------------------------
Aegis - UI_Bin.lua
AceGUI window for the Bin (temporary roster).
-----------------------------------------------------------------------------]]--

local addonName = ...
local AGS = LibStub("AceAddon-3.0"):GetAddon("Aegis", true)
local AceGUI = LibStub("AceGUI-3.0")

if not AceGUI then
  function _G.AegisBin_Open()
    if AGS and AGS.Print then AGS:Print("AceGUI-3.0 is required for the Bin UI.") end
  end
  return
end

local Bin = AGS and AGS.Bin or _G.AegisBin
local ui = nil

-- Column spec
local COLS   = { "Name", "Realm", "Guild", "Added", "Actions" }
local WIDTHS = { 160,     140,     220,     140,     140 }

local HEADER_COLOR_PREFIX = "|cffffd200"
local HEADER_COLOR_SUFFIX = "|r"

local function fmtDateTime(ts) return ts and date("%Y-%m-%d %H:%M", ts) or "" end

local function buildHeader(container)
  local hdr = AceGUI:Create("SimpleGroup")
  hdr:SetFullWidth(true)
  hdr:SetLayout("Flow")
  for i, title in ipairs(COLS) do
    local lab = AceGUI:Create("Label")
    lab:SetText(HEADER_COLOR_PREFIX .. title .. HEADER_COLOR_SUFFIX)
    lab:SetWidth(WIDTHS[i])
    hdr:AddChild(lab)
  end
  container:AddChild(hdr)
end

local function buildRows(container)
  local entries = Bin:GetEntries()
  local scroll = AceGUI:Create("ScrollFrame")
  scroll:SetLayout("Flow")
  scroll:SetFullWidth(true)
  scroll:SetFullHeight(true)
  container:AddChild(scroll)

  if #entries == 0 then
    local lbl = AceGUI:Create("Label")
    lbl:SetText("No players recorded this session.")
    lbl:SetFullWidth(true)
    scroll:AddChild(lbl)
    return
  end

  for _, e in ipairs(entries) do
    local row = AceGUI:Create("SimpleGroup"); row:SetLayout("Flow"); row:SetFullWidth(true)

    local cells = {
      e.name or "-",
      e.realm or "-",
      e.guild or "-",
      fmtDateTime(e.tsAdded),
    }
    for i=1,#cells do
      local lab = AceGUI:Create("Label")
      lab:SetText(cells[i])
      lab:SetWidth(WIDTHS[i])
      row:AddChild(lab)
    end

    -- Actions cell
    local cell = AceGUI:Create("SimpleGroup"); cell:SetLayout("Flow"); cell:SetWidth(WIDTHS[#WIDTHS])
    local btnAdd = AceGUI:Create("Button"); btnAdd:SetText("+"); btnAdd:SetWidth(50)
    btnAdd:SetCallback("OnClick", function()
      local full = e.full
      local def = AGS.db.profile.settings.defaults or { type = "N/A", category = "N/A" }
      AGS:Aegis_AddPlayer(full, "Added from Bin", { type = def.type, category = def.category })
    end)
    cell:AddChild(btnAdd)

    local btnRem = AceGUI:Create("Button"); btnRem:SetText("-"); btnRem:SetWidth(50)
    btnRem:SetCallback("OnClick", function()
      Bin:RemoveFromSession(e.full)
    end)
    cell:AddChild(btnRem)

    row:AddChild(cell)
    scroll:AddChild(row)
  end
end

local UIObj = {}
function UIObj:Refresh()
  if not ui then return end
  ui:ReleaseChildren()
  buildHeader(ui)
  buildRows(ui)
end

-- Public entry
function _G.AegisBin_Open()
  if ui then
    ui:Show()
    UIObj:Refresh()
    return
  end
  ui = AceGUI:Create("Frame")
  ui:SetTitle("Aegis - Bin")
  ui:SetLayout("Fill")
  ui:SetWidth(900)
  ui:SetHeight(600)
  if ui.frame and ui.frame.SetResizeBounds then ui.frame:SetResizeBounds(600, 360)
  elseif ui.frame and ui.frame.SetMinResize then ui.frame:SetMinResize(600, 360) end

  -- content container
  local content = AceGUI:Create("SimpleGroup")
  content:SetFullWidth(true)
  content:SetFullHeight(true)
  content:SetLayout("List")
  ui:AddChild(content)

  -- attach UI object to content for refreshes
  UIObj.container = content
  function UIObj:Refresh()
    content:ReleaseChildren()
    buildHeader(content)
    buildRows(content)
  end

  -- initial fill
  UIObj:Refresh()

  -- link UI back to Bin so Bin can ping Refresh()
  if Bin and Bin._AttachUI then Bin:_AttachUI(UIObj) end
end
