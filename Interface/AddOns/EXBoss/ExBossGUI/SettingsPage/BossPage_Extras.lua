---@diagnostic disable: undefined-global

local Tools = _G.ExwindTools
local Page = ExBoss.UI.Panel.BossPage
local EXUI = Tools.UI
local Extras = { MODULE_KEY = "ExBoss.BossPage.ExtrasEditor" }
Page.Extras = Extras
local context
local cardSession

function Extras:Hide()
    -- context 是写回身份；离开/切换时必须先作废，不能让新卡壳继续持有旧 draft。
    context = nil
    if cardSession and type(cardSession.Release) == "function" then
        cardSession:Release()
        cardSession = nil
    end
end

-- [卡片/Grid 迁移边界：encounter extra]
-- 允许：只让声明中的既有卡片/控件接入共享宿主并反馈高度。
-- 禁止：修改 scene/slot/encounterID/extraKey 身份、isCurrent guard、single-leaf persist、phase 或错误回滚。
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
    -- extra.layout 的稳定 key/type/callback 属遭遇声明合同；迁移只能解释其几何/卡片分组。
    Tools:RegisterModuleLayout(self.MODULE_KEY, extra.layout)
    -- Rendering and pooled widget release happen with no active write context.
    if type(extra.layout) == "table" and extra.layout.version == 1 and type(extra.layout.cards) == "table" then
        cardSession = Grid:MountCards(container, extra.layout, {
            pageId = self.MODULE_KEY,
            regionId = "encounter-extra",
            binding = binding,
            config = draft,
            moduleKey = self.MODULE_KEY,
        })
    else
        Grid:SetContainerCols(container, extra.cols or 202)
        Grid:SetContainerPadding(container, { left = 0, right = 10, top = 10, bottom = 0 })
        Grid:Render(container, extra.layout, draft, self.MODULE_KEY)
    end
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
