-- 泛用中央 TimerBar 宿主：只持有既有 StandardTimerBarCollection 的三宿主生命周期。
-- 模块必须自行声明 DB、GUI 几何、TimerBar schema 和纯 presentation；不传业务函数。
local ExwindTools = _G.ExwindTools
if type(ExwindTools) ~= "table" or type(ExwindTools.UI) ~= "table" then error("ExwindCentralTimerBarRender requires initialized EXUI", 0) end
local EXUI = ExwindTools.UI
if EXUI.CentralTimerBarRenderInitialized then error("ExwindCentralTimerBarRender already initialized", 0) end
EXUI.CentralTimerBarRenderInitialized = true

local specs = {}
local controllers = EXUI.CentralModuleControllers
if type(controllers) ~= "table" then error("ExwindCentralTimerBarRender requires central module registry", 0) end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}; if seen[value] then error("central timerbar data cannot be cyclic", 3) end
    local result = {}; seen[value] = true
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    seen[value] = nil; return result
end
local function requireString(value, name, level)
    if type(value) ~= "string" or value:match("^%s*$") then error(name .. " must be non-empty string", level or 3) end
    return value
end
local function validatePure(value, name, seen)
    if type(value) == "function" then error(name .. " cannot contain functions", 3) end
    if type(value) ~= "table" then return end
    seen = seen or {}; if seen[value] then error(name .. " cannot be cyclic", 3) end
    seen[value] = true; for key, child in pairs(value) do validatePure(key, name, seen); validatePure(child, name, seen) end; seen[value] = nil
end
local function getPath(root, path)
    if path == "$root" then return root end
    local value = root; for key in path:gmatch("[^.]+") do if type(value) ~= "table" then return nil end; value = value[key] end; return value
end
local function writePath(root, path, value)
    local parent, final = root, nil
    for key in path:gmatch("[^.]+") do if final then parent = parent[final] end; final = key end
    if type(parent) == "table" and final then parent[final] = copy(value) end
end
local function validateGUI(gui)
    local ok, issue = EXUI:ValidateSettingsDeclarationV2(gui)
    if not ok then error("MODULE_SPEC.gui " .. issue.path .. ": " .. issue.message, 3) end
end
local function validateSpec(spec)
    if type(spec) ~= "table" then error("RegisterTimerBarModule requires MODULE_SPEC", 3) end
    validatePure(spec, "MODULE_SPEC"); requireString(spec.moduleKey, "MODULE_SPEC.moduleKey", 3)
    if spec.kind ~= "timerbar" then error("MODULE_SPEC.kind must be timerbar", 3) end
    if specs[spec.moduleKey] or controllers[spec.moduleKey] then error("duplicate central module: " .. spec.moduleKey, 3) end
    if spec.catalog ~= nil then error("MODULE_SPEC.catalog is forbidden; define metadata in ExwindTools.ModuleList", 3) end
    validateGUI(spec.gui, spec.moduleKey)
    if type(spec.anchor) ~= "table" then error("MODULE_SPEC.anchor is required", 3) end
    requireString(spec.anchor.dbPath, "MODULE_SPEC.anchor.dbPath", 3); requireString(spec.anchor.xKey, "MODULE_SPEC.anchor.xKey", 3); requireString(spec.anchor.yKey, "MODULE_SPEC.anchor.yKey", 3)
    if type(spec.timerBar) ~= "table" or type(spec.timerBar.schema) ~= "table" then
        error("MODULE_SPEC.timerBar.schema is required; plain TimerBarCollection is removed", 3)
    end
end
local function splitRefreshContract(spec)
    local refresh = spec.RefreshActiveSurfaces
    if refresh ~= nil and type(refresh) ~= "function" then
        error("MODULE_SPEC.RefreshActiveSurfaces must be a function when supplied", 3)
    end
    local settingsOwner = spec.SettingsOwner
    if settingsOwner ~= nil and type(settingsOwner) ~= "function" then
        error("MODULE_SPEC.SettingsOwner must be a function when supplied", 3)
    end
    local declaration = {}
    for key, value in pairs(spec) do
        if key ~= "RefreshActiveSurfaces" and key ~= "SettingsOwner" then declaration[key] = value end
    end
    return declaration, refresh, settingsOwner
end
-- MODULE_SPEC.SettingsOwner(controller) 可返回 V2 页面需要的 sources/controls/components/actions/
-- predicates/texts/options/AttachSession；与工厂提供的 binding 及 anchor/icon 选项合并，不得覆盖。
local function MergeSettingsOwner(owner, extension)
    if extension == nil then return owner end
    if type(extension) ~= "table" then error("MODULE_SPEC.SettingsOwner must return a table", 3) end
    for key, value in pairs(extension) do
        if key == "binding" then
            error("MODULE_SPEC.SettingsOwner cannot replace binding", 3)
        elseif key == "options" then
            for name, opts in pairs(value) do
                if owner.options[name] ~= nil then
                    error("MODULE_SPEC.SettingsOwner cannot replace options." .. tostring(name), 3)
                end
                owner.options[name] = opts
            end
        else
            owner[key] = value
        end
    end
    return owner
end
local function validateEntries(entries, api)
    if type(entries) ~= "table" then error(api .. " requires entry array", 3) end
    for index, entry in ipairs(entries) do
        if type(entry) ~= "table" or type(entry.itemID) ~= "string" or entry.itemID == "" or type(entry.presentation) ~= "table" then error(api .. " entry " .. index .. " requires itemID and presentation", 3) end
        validatePure(entry.presentation, api .. " presentation")
    end
end

local Controller = {}; Controller.__index = Controller
function Controller:GetConfig() return self.db end
-- V2 设置页 owner：绑定本模块存档；optionsRef="anchor" 取得锚点字段与选框回调。
function Controller:CreateSettingsOwner()
    local anchor = self.spec.anchor
    local owner = {
        binding = { moduleKey = self.moduleKey, config = self.db },
        options = {
            anchor = {
                bindRoot = anchor.bindRoot == true,
                offsetXKey = anchor.xKey,
                offsetYKey = anchor.yKey,
                defaultOffsetX = anchor.defaultX or 0,
                defaultOffsetY = anchor.defaultY or 0,
                attachEnabledKey = anchor.attachEnabledKey,
                attachTargetKey = anchor.attachTargetKey,
                onPickFrame = function() return self.anchor:StartFramePicker() end,
            },
        },
    }
    return MergeSettingsOwner(owner, self.moduleSettingsOwner and self.moduleSettingsOwner(self))
end

function Controller:BuildSettingsDeclaration()
    return copy(self.spec.gui)
end
function Controller:Apply(collection, entries, layout)
    local items = {}; for _, entry in ipairs(entries) do local item = collection:AcquireItem(entry.itemID); collection:ApplyItem(item, entry.presentation); items[#items + 1] = item end; collection:SetItems(items, layout); return collection
end
function Controller:CreateCollection(host, mode)
    return EXUI:CreateStandardTimerBarCollection(host, mode, self.moduleKey, { schema = self.spec.timerBar.schema })
end
function Controller:ClearRuntime()
    if self.runtimeCollection then self.runtimeCollection:Release(); self.runtimeCollection = nil end
    if self.anchor.frame then self.anchor.frame:Hide() end
end
function Controller:SetRuntime(entries, layout)
    validateEntries(entries, "SetRuntime"); self.runtimeEntries, self.runtimeLayout = entries, layout or { direction = "DOWN", spacing = 0, maxVisible = 1 }
    if self.editing then return end; if #entries == 0 then return self:ClearRuntime() end
    local host = self.anchor:Ensure(); self.anchor:ApplyPosition(); self.runtimeCollection = self.runtimeCollection or self:CreateCollection(host, "runtime")
    self:Apply(self.runtimeCollection, self.runtimeEntries, self.runtimeLayout); local w,h=self.runtimeCollection:GetBounds(); host:SetSize(math.max(1,w or 1),math.max(1,h or 1)); host:Show()
end
function Controller:Clear() return self:SetRuntime({}, { direction = "DOWN", spacing = 0, maxVisible = 1 }) end
function Controller:SetPreview(entries, layout)
    validateEntries(entries, "SetPreview"); self.previewEntries, self.previewLayout = entries, layout or { direction = "DOWN", spacing = 0, maxVisible = 1 }
    if self.panel then self:RenderPanel() end; if self.worldCollection then self:RenderWorld(self.anchor:Ensure()) end
end
function Controller:RefreshPresentationInteractions()
    for _, entries in ipairs({ self.previewEntries, self.runtimeEntries }) do
        for _, entry in ipairs(entries or {}) do
            if type(entry.presentation) == "table" then
                entry.presentation.interaction = EXUI:BuildStandardPreviewInteraction("TimerBar", self.db, self.spec.preview.elements)
                -- plain TimerBar 可由模块用 DB 组合临时 style；这里只把已写回唯一
                -- DB 的局部文字坐标投影到该临时输出，不创建或复制任何配置表。
                local styles = entry.presentation.style and entry.presentation.style.text
                local roles = { spellName = { db = "font_spell", style = "label" }, targetName = { db = "font_target", style = "target" }, time = { db = "font_timer", style = "time" } }
                for _, declaration in pairs(self.spec.preview.elements or {}) do
                    local role = roles[declaration.textRole]
                    local target = role and styles and styles[role.style]
                    local source = role and self.db[role.db]
                    if type(target) == "table" and type(source) == "table" then target.x, target.y = source.x, source.y end
                end
            end
        end
    end
end
function Controller:RenderPanel() if self.panel then self.panel:Render(self.previewEntries or {}, self.previewLayout) end end
function Controller:MountPanel(dock)
    if self.panel then self.panel:Release() end; self.panel = EXUI:CreateTimerBarPanelPreview(dock, self.moduleKey, { schema = self.spec.timerBar.schema })
    local timerBarPath = self.spec.timerBar.schema.timerBarKey
    EXUI:BindStandardPreviewInteractions(self.panel, { moduleKey = self.moduleKey, binding = self.binding, requiredPositionGuiKeys = self.spec.preview and self.spec.preview.positionGuiKeys or {}, elements = self.spec.preview and self.spec.preview.elements or {}, resize = { widthPath = timerBarPath .. ".width", heightPath = timerBarPath .. ".height", minWidth = 50, maxWidth = 800, minHeight = 8, maxHeight = 120 } }); self:RenderPanel()
end
function Controller:ReleasePanel() if self.panel then self.panel:Release(); self.panel = nil end end
-- 字段名、文字槽位与样式均由 ModuleDB 的 presentation 自己决定。中央只重套
-- 已存在的三处 Region，绝不按 path 推断模块语义。
function Controller:RefreshActiveSurfaces(changedPath, phase)
    -- 个别标准 TimerBar 的 Item Apply 本身会重置原生条的视觉状态；它们可
    -- 明确拒绝 changing，仅在 committed 做一次既有表面重套。
    -- AnchorGroup 的手动输入和选择器共用这份 DB；统一由中央重套实际锚点。
    self.anchor:ApplyPosition()
    if self.moduleRefreshActiveSurfaces
        and self.moduleRefreshActiveSurfaces(self, changedPath, phase) == false then
        return
    end
    self:RefreshPresentationInteractions()
    local function resolve(entries, id)
        for _, entry in ipairs(entries or {}) do if entry.itemID == id then return copy(entry.presentation) end end
    end
    local function reapply(surface, entries)
        if surface and type(surface.ReapplyCurrentItems) == "function" then surface:ReapplyCurrentItems(function(presentation, item)
            local nextPresentation = resolve(entries, item and item.id)
            if nextPresentation then for key in pairs(presentation) do presentation[key] = nil end; for key, value in pairs(nextPresentation) do presentation[key] = value end end
        end) end
    end
    reapply(self.panel, self.previewEntries)
    if phase ~= "changing" then
        reapply(self.worldCollection, self.previewEntries)
        reapply(self.runtimeCollection, self.runtimeEntries)
    end
end
function Controller:RenderWorld(host)
    if self.runtimeCollection then self.runtimeCollection:Release(); self.runtimeCollection = nil end; if self.worldCollection then self.worldCollection:Release(); self.worldCollection = nil end
    self.worldCollection = self:CreateCollection(host, "world"); self:Apply(self.worldCollection, self.previewEntries or {}, self.previewLayout); local w,h=self.worldCollection:GetBounds(); host:SetSize(math.max(1,w or 1),math.max(1,h or 1)); host:Show()
end
function Controller:ReleaseWorld() if self.worldCollection then self.worldCollection:Release(); self.worldCollection = nil end end
function Controller:GetWorldBounds() return self.worldCollection and self.worldCollection:GetWorldBounds() or nil end
function Controller:OnWorldPreviewStateChanged(editing) self.editing = editing == true; if not self.editing and self.runtimeEntries then self:SetRuntime(self.runtimeEntries,self.runtimeLayout) end end
function Controller:RefreshVisuals(options)
    options = type(options) == "table" and options or {}; self:RefreshPresentationInteractions()
    if self.panel and options.rebuildPanelPreview ~= false then self:RenderPanel() end
    if self.worldCollection then self:RenderWorld(self.anchor:Ensure()) end
    if self.runtimeEntries then self:SetRuntime(self.runtimeEntries,self.runtimeLayout) end
end

function EXUI:RegisterTimerBarModule(spec)
    local declaration, refresh, settingsOwner = splitRefreshContract(spec)
    validateSpec(declaration); local registered = copy(declaration); specs[registered.moduleKey] = registered
    local moduleMeta = ExwindTools:GetModuleMeta(registered.moduleKey)
    if not moduleMeta then error("MODULE_SPEC.moduleKey is missing from ExwindTools.ModuleList: " .. registered.moduleKey, 2) end
    local db = ExwindTools:GetModuleDB(registered.moduleKey); local controller = setmetatable({ moduleKey = registered.moduleKey, spec = registered, db = db, previewEntries = {}, moduleRefreshActiveSurfaces = refresh, moduleSettingsOwner = settingsOwner }, Controller)
    local anchorDB = getPath(db, registered.anchor.dbPath); if type(anchorDB) ~= "table" then error("MODULE_SPEC.anchor.dbPath does not resolve to table", 2) end
    local timerBarDB = db[registered.timerBar.schema.timerBarKey]
    if type(timerBarDB) ~= "table" or type(timerBarDB.width) ~= "number" or type(timerBarDB.height) ~= "number" then
        error("MODULE_SPEC timerbar family requires numeric width/height", 2)
    end
    controller.anchor = ExwindTools:CreateAnchorController({ moduleKey = registered.moduleKey, frameName = "ExwindCentral_" .. registered.moduleKey:gsub("[^%w]", "_"), title = moduleMeta.Name, getDB = function() return anchorDB end, offsetXKey = registered.anchor.xKey, offsetYKey = registered.anchor.yKey, defaultOffsetX = registered.anchor.defaultX or 0, defaultOffsetY = registered.anchor.defaultY or 0, attachEnabledKey = registered.anchor.attachEnabledKey, attachTargetKey = registered.anchor.attachTargetKey, initialWidth = registered.anchor.initialWidth or 1, initialHeight = registered.anchor.initialHeight or 1, clampedToScreen = registered.anchor.clampedToScreen == true })
    controller.binding = EXUI:RegisterStandardConfigBinding({ moduleKey = registered.moduleKey, getConfig = function() return controller.db end })
    EXUI:RegisterModuleSettingsPageV2(registered.moduleKey, registered.gui,
        function() return controller:CreateSettingsOwner() end)
    EXUI:RegisterEditableModule({ addon = "ExwindTools", key = registered.moduleKey, name = moduleMeta.Name, orientation = "HORIZONTAL", settingsPage = registered.moduleKey, getAnchor = function() return controller.anchor:Ensure() end, RenderWorld = function(host) controller:RenderWorld(host) end, ReleaseWorld = function() controller:ReleaseWorld() end, GetWorldBounds = function() return controller:GetWorldBounds() end, OnWorldPreviewStateChanged = function(editing) controller:OnWorldPreviewStateChanged(editing) end })
    controllers[registered.moduleKey] = controller
    EXUI:RegisterModuleValueController(registered.moduleKey, controller)
    return controller
end
