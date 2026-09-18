---@diagnostic disable: undefined-global

local Tools = _G.ExwindTools
local Page = ExBoss.UI.Panel.BossPage
local EXUI = Tools.UI
local Extras = { MODULE_KEY = "ExBoss.BossPage.ExtrasEditor" }
Page.Extras = Extras
local context

function Extras:Hide()
    context = nil
end

function Extras:Render(container, scene, slot, encounterID, extraKey, isCurrent)
    self:Hide()
    local Grid = _G.ExwindGrid
    local cfg = ExBoss.BossConfig
    local api = _G.EXBossData
    local extra = ExBoss.BossEncounters:GetExtra(encounterID, extraKey)
    if not (Grid and extra and cfg:GetRuntimeConfig(scene, slot)) then return false end
    local draft = cfg:GetExtraConfig(scene, encounterID, extraKey)
    local binding = {
        scene = scene, slot = slot, encounterID = encounterID, extraKey = extraKey,
        draft = draft, saved = cfg:GetExtraConfig(scene, encounterID, extraKey),
        identity = api.GetCurrentConfiguration(scene), isCurrent = isCurrent,
    }
    Grid:SetContainerCols(container, extra.cols or 202)
    Grid:SetContainerPadding(container, { left = 0, right = 10, top = 10, bottom = 0 })
    Tools:RegisterModuleLayout(self.MODULE_KEY, extra.layout)
    -- Rendering and pooled widget release happen with no active write context.
    Grid:Render(container, extra.layout, draft, self.MODULE_KEY)
    context = binding
    return true
end

EXUI:RegisterModuleValueController(Extras.MODULE_KEY, {
    RefreshActiveSurfaces = function(_, changedPath, phase)
        local current = context
        if not (current and Page._visible and current.isCurrent()) then return end
        if phase == "changing" then return end
        local key = changedPath
        if current.saved[key] == nil or current.saved[key] == current.draft[key] then return end
        local ok, reason = ExBoss.BossConfig:SetExtraValue(current.scene, current.slot,
            current.encounterID, current.extraKey, key, current.draft[key], current.identity)
        if ok then
            current.saved[key] = current.draft[key]
        else
            current.draft[key] = current.saved[key]
            context = nil
            Page:RefreshSpellUI()
            if ExBoss.Print and ExBoss.Print.Say then ExBoss.Print.Say(tostring(reason)) end
        end
    end,
})
