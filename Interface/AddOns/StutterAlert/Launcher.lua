local _, ns = ...
local L  = ns.L
local DB = ns.DB

-- The minimap button and the addon compartment entry, through LibDBIcon. Both do what
-- the anchor button does: left-click toggles the report, right-click opens the menu.
local NAME = "StutterAlert" -- also the compartment text; LibDBIcon's hover finds the entry by it
local Broker = LibStub("LibDataBroker-1.1", true)
local Icon = LibStub("LibDBIcon-1.0", true)

local Launcher = {}
ns.Launcher = Launcher

local launcher = Broker and Broker:NewDataObject(NAME, {
    type = "launcher",
    text = L.ADDON_TITLE,
    icon = "Interface\\AddOns\\StutterAlert\\Media\\saicon",
    OnClick = function(_, button)
        if button == "RightButton" then
            -- A frame later: the compartment closes every open menu once its click returns.
            C_Timer.After(0, function() ns.Overlay:OpenMenu(UIParent) end)
        else
            ns.Overlay:ToggleExport()
        end
    end,
    OnTooltipShow = function(tooltip)
        ns.Overlay:FillTooltip(tooltip, true)
    end,
})

-- Retail only today; the Classic clients have no compartment.
function Launcher:HasCompartment()
    return Icon ~= nil and Icon:IsButtonCompartmentAvailable()
end

-- LibDBIcon keeps its own hide and compartment flags in DB.data.minimap; the settings drive them.
function Launcher:Update()
    if not (Icon and launcher) then return end
    local db, s = DB.data.minimap, DB.settings
    db.hide = not s.minimapButton
    if not Icon:IsRegistered(NAME) then
        db.showInCompartment = s.compartment or nil
        Icon:Register(NAME, launcher, db)
    end
    if db.hide then Icon:Hide(NAME) else Icon:Show(NAME) end
    if s.compartment then Icon:AddButtonToCompartment(NAME) else Icon:RemoveButtonFromCompartment(NAME) end
end
