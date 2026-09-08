-- =========================================================
-- IconTemplate：只组合现有 IconCollection / PanelPreview /
-- AnchorController / EditMode。模块只提供 DB、业务 record 与页面声明。
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools or not ExwindTools.UI then return end

local EXUI = ExwindTools.UI
local IconTemplate = ExwindTools.IconTemplate or {}
ExwindTools.IconTemplate = IconTemplate

local Template = {}
Template.__index = Template

local function Copy(source)
    local result = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        result[key] = value
    end
    return result
end

local function ItemID(record, index)
    return record and (record.itemID or record.id) or ("sample:" .. tostring(index))
end

function Template:GetDB()
    local db = self.definition.getDB()
    if type(self.definition.ensureDefaults) == "function" then
        return self.definition.ensureDefaults(db, self)
    end
    return db
end

function Template:GetLayout(mode)
    local layout = self.definition.layout
    if type(layout) == "function" then
        return layout(self:GetDB(), mode, self) or {}
    end
    if type(layout) == "table" then return layout end
    return self:GetDB().layout or {}
end

function Template:BuildPresentation(record, mode, now)
    return self.definition.buildPresentation(record, mode, self, now) or {}
end

function Template:ApplyRecords(collection, records, mode, now)
    local items = {}
    for index, record in ipairs(records or {}) do
        local item = collection:AcquireItem(ItemID(record, index))
        collection:ApplyItem(item, self:BuildPresentation(record, mode, now))
        items[#items + 1] = item
    end
    collection:SetItems(items, self:GetLayout(mode))
    return items
end

function Template:GetSampleRecords(mode)
    local samples = self.definition.samples
    if type(samples) == "function" then
        return samples(self:GetDB(), mode, self) or {}
    end
    return samples or {}
end

function Template:EnsureAnchorController()
    if self.anchorController then return self.anchorController end

    local anchor = self.definition.anchor
    if type(anchor) == "function" then
        self.anchorController = anchor(self)
    else
        local options = Copy(anchor)
        options.moduleKey = options.moduleKey or self.moduleKey
        options.getDB = options.getDB or function() return self:GetDB() end
        self.anchorController = ExwindTools:CreateAnchorController(options)
    end
    return self.anchorController
end

function Template:EnsureAnchor()
    return self:EnsureAnchorController():Ensure()
end

function Template:EnsureRuntime()
    if not self.runtimeCollection then
        self.runtimeCollection = EXUI:CreateIconCollection(self:EnsureAnchor(), "runtime", self.moduleKey, self.definition.runtimeOptions)
    end
    return self.runtimeCollection
end

function Template:ApplyRuntimeRecord(record, now)
    local collection = self:EnsureRuntime()
    local item = collection:AcquireItem(ItemID(record, 1))
    collection:ApplyItem(item, self:BuildPresentation(record, "runtime", now))
    return item
end

function Template:SetRuntimeRecords(records, now)
    return self:ApplyRecords(self:EnsureRuntime(), records, "runtime", now)
end

function Template:ReleaseRuntimeRecord(itemID)
    if self.runtimeCollection then self.runtimeCollection:ReleaseItem(itemID) end
end

function Template:ReleaseRuntime()
    if self.runtimeCollection then
        self.runtimeCollection:Release()
        self.runtimeCollection = nil
    end
end

function Template:RenderWorld(host)
    if type(self.definition.onWorldRendering) == "function" then
        self.definition.onWorldRendering(self, host)
    end
    if self.worldCollection then self.worldCollection:Release() end
    self.worldCollection = EXUI:CreateIconCollection(host, "world", self.moduleKey, self.definition.worldOptions)
    self:ApplyRecords(self.worldCollection, self:GetSampleRecords("world"), "world")
    if type(self.definition.onWorldRendered) == "function" then
        self.definition.onWorldRendered(self, self.worldCollection)
    end
end

function Template:RefreshWorld()
    if self.worldCollection then
        self:ApplyRecords(self.worldCollection, self:GetSampleRecords("world"), "world")
    end
    return self.worldCollection
end

function Template:ReleaseWorld()
    if self.worldCollection then
        self.worldCollection:Release()
        self.worldCollection = nil
    end
    if type(self.definition.onWorldReleased) == "function" then
        self.definition.onWorldReleased(self)
    end
end

function Template:GetWorldBounds()
    return self.worldCollection and self.worldCollection:GetWorldBounds() or nil
end

function Template:ShowPanelPreview(dock)
    if self.panelPreview and self.panelDock ~= dock then self:ReleasePanelPreview() end
    if not self.panelPreview then
        self.panelDock = dock
        self.panelPreview = EXUI:CreateIconPanelPreview(dock, self.moduleKey, {
            onIntent = function(intent)
                if type(self.definition.onPanelIntent) == "function" then
                    return self.definition.onPanelIntent(intent, self)
                end
            end,
        })
    end
    return self:RefreshPanelPreview()
end

function Template:RefreshPanelPreview()
    if not self.panelPreview then return end
    local entries = {}
    for index, record in ipairs(self:GetSampleRecords("panel")) do
        entries[#entries + 1] = {
            itemID = ItemID(record, index),
            presentation = self:BuildPresentation(record, "panel"),
        }
    end
    self.panelPreview:Render(entries, self:GetLayout("panel"))
    return self.panelPreview
end

function Template:ReapplyCurrentItems(mutatePresentation)
    local function Reapply(collection)
        if collection and type(collection.ReapplyCurrentItems) == "function" then
            collection:ReapplyCurrentItems(mutatePresentation)
        end
    end
    Reapply(self.runtimeCollection)
    Reapply(self.worldCollection)
    if self.panelPreview and type(self.panelPreview.ReapplyCurrentItems) == "function" then
        self.panelPreview:ReapplyCurrentItems(mutatePresentation)
    end
end

function Template:ReleasePanelPreview()
    if self.panelPreview then self.panelPreview:Release() end
    self.panelPreview = nil
    self.panelDock = nil
end

function Template:Release()
    self:ReleaseRuntime()
    self:ReleaseWorld()
    self:ReleasePanelPreview()
end

local function RegisterEditableModule(template)
    local declaration = Copy(template.definition.editable)
    if next(declaration) == nil then return end

    declaration.getAnchor = function()
        return template:EnsureAnchor()
    end
    declaration.RenderWorld = function(host)
        return template:RenderWorld(host)
    end
    declaration.ReleaseWorld = function()
        return template:ReleaseWorld()
    end
    declaration.GetWorldBounds = function()
        return template:GetWorldBounds()
    end
    EXUI:RegisterEditableModule(declaration)
end

function IconTemplate.Register(definition)
    definition = definition or {}
    local template = setmetatable({
        definition = definition,
        moduleKey = definition.MODULE_KEY,
    }, Template)

    template:GetDB()
    RegisterEditableModule(template)
    return template
end

-- 模块唯一入口：注册声明后取得模板实例；不创建任何新的显示系统。
function ExwindTools:RegisterIconTemplate(definition)
    return IconTemplate.Register(definition)
end
