---@diagnostic disable: undefined-global

local Tools = _G.ExwindTools
local Page = ExBoss.UI.Panel.BossPage
local EXUI = Tools.UI
local Extras = { MODULE_KEY = "ExBoss.BossPage.ExtrasEditor" }
Page.Extras = Extras
local context
local cardSession
local mountedContainer

function Extras:Hide()
    -- context 是写回身份；离开/切换时必须先作废，不能让新卡壳继续持有旧 draft。
    context = nil
    if cardSession and type(cardSession.Release) == "function" then
        cardSession:Release()
        if mountedContainer and mountedContainer._exV2Session == cardSession then
            mountedContainer._exV2Session = nil
            mountedContainer._exV2Owner = nil
        end
        cardSession = nil
    end
    mountedContainer = nil
end

-- V2 只持有 extra 的显示会话；身份检查与单字段持久化仍由既有 owner 负责。
function Extras:Render(container, scene, slot, encounterID, extraKey, isCurrent)
    self:Hide()
    local cfg = ExBoss.BossConfig
    local api = _G.EXBossData
    local extra = ExBoss.BossEncounters:GetExtra(encounterID, extraKey)
    if not (extra and cfg:GetRuntimeConfig(scene, slot)) then return false end
    local draft = cfg:GetExtraConfig(scene, encounterID, extraKey)
    local binding = {
        scene = scene, slot = slot, encounterID = encounterID, extraKey = extraKey,
        draft = draft, saved = cfg:GetExtraConfig(scene, encounterID, extraKey),
        identity = api.GetCurrentConfiguration(scene), isCurrent = isCurrent,
    }
    local owner = {
        binding = { moduleKey = self.MODULE_KEY, config = draft },
        onHeightChanged = function(height)
            if context == binding then container:SetHeight(math.max(1, height)) end
        end,
    }
    -- Mounting and pooled widget release happen with no active write context.
    cardSession = EXUI:MountSettingsDeclarationV2(container, extra.layout, owner)
    if not cardSession then return false end
    mountedContainer = container
    container._exV2Owner = owner
    container._exV2Session = cardSession
    context = binding
    container:SetHeight(math.max(1, cardSession:GetHeight()))
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
            -- 提交失败后重新取得 extra 身份，只恢复当前区域，不重建 Boss 页面。
            Extras:Render(mountedContainer, current.scene, current.slot,
                current.encounterID, current.extraKey, current.isCurrent)
            if ExBoss.Print and ExBoss.Print.Say then ExBoss.Print.Say(tostring(reason)) end
        end
    end,
})
