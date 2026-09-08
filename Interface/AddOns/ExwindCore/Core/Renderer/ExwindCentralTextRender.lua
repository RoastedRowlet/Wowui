-- Generic central Text module owner.  It owns only the three display hosts
-- (runtime/world/panel); a module owns DB declaration and business payload.
-- No module callback, profile, or module-name branch is permitted here.
local ExwindTools = _G.ExwindTools
if type(ExwindTools) ~= "table" or type(ExwindTools.UI) ~= "table" then error("ExwindCentralTextRender requires initialized EXUI", 0) end
local EXUI = ExwindTools.UI
if EXUI.CentralTextRenderInitialized then error("ExwindCentralTextRender already initialized", 0) end
EXUI.CentralTextRenderInitialized = true

local specs = {}
local controllers = EXUI.CentralModuleControllers
if type(controllers) ~= "table" then error("ExwindCentralTextRender requires central module registry", 0) end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then error("central text declaration cannot be cyclic", 3) end
    local result = {}; seen[value] = true
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    seen[value] = nil
    return result
end
local function requireString(value, name, level)
    if type(value) ~= "string" or value:match("^%s*$") then error(name .. " must be non-empty string", level or 3) end
    return value
end
local function validatePure(value, name, seen)
    local valueType = type(value)
    if valueType == "function" or valueType == "userdata" or valueType == "thread" then error(name .. " must contain declaration data only", 3) end
    if valueType ~= "table" then return end
    seen = seen or {}
    if seen[value] then error(name .. " cannot be cyclic", 3) end
    seen[value] = true
    for key, child in pairs(value) do validatePure(key, name, seen); validatePure(child, name, seen) end
    seen[value] = nil
end
local function geometry(item, name)
    for _, key in ipairs({ "x", "y", "w", "h" }) do
        if type(item[key]) ~= "number" then error(name .. " requires numeric " .. key, 3) end
    end
    if item.w <= 0 or item.h <= 0 then error(name .. " requires positive w/h", 3) end
end
local function getPath(root, path)
    if path == "$root" then return root end
    local value = root
    for key in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[key]
    end
    return value
end
local function validateSpec(spec)
    if type(spec) ~= "table" then error("RegisterTextModule requires MODULE_SPEC", 3) end
    validatePure(spec, "MODULE_SPEC")
    requireString(spec.moduleKey, "MODULE_SPEC.moduleKey", 3)
    if spec.kind ~= "text" then error("MODULE_SPEC.kind must be text", 3) end
    if specs[spec.moduleKey] or controllers[spec.moduleKey] then error("duplicate central module: " .. spec.moduleKey, 3) end
    if spec.catalog ~= nil then error("MODULE_SPEC.catalog is forbidden; define metadata in ExwindTools.ModuleList", 3) end
    if type(spec.gui) ~= "table" or type(spec.gui.static) ~= "table" or type(spec.gui.fields) ~= "table" then error("MODULE_SPEC.gui.static/gui.fields are required", 3) end
    if type(spec.anchor) ~= "table" then error("MODULE_SPEC.anchor is required", 3) end
    requireString(spec.anchor.dbPath, "MODULE_SPEC.anchor.dbPath", 3)
    requireString(spec.anchor.xKey, "MODULE_SPEC.anchor.xKey", 3)
    requireString(spec.anchor.yKey, "MODULE_SPEC.anchor.yKey", 3)
    for _, item in ipairs(spec.gui.static) do geometry(item, "MODULE_SPEC.gui.static") end
    for _, item in ipairs(spec.gui.fields) do
        requireString(item.key, "MODULE_SPEC.gui.fields key", 3)
        requireString(item.type, "MODULE_SPEC.gui.fields type", 3)
        geometry(item, "MODULE_SPEC.gui.fields")
    end
end
local function splitRefreshContract(spec)
    local refresh = spec.RefreshActiveSurfaces
    if refresh ~= nil and type(refresh) ~= "function" then
        error("MODULE_SPEC.RefreshActiveSurfaces must be a function when supplied", 3)
    end
    local declaration = {}
    for key, value in pairs(spec) do
        if key ~= "RefreshActiveSurfaces" then declaration[key] = value end
    end
    return declaration, refresh
end
local function validateEntries(entries, api)
    if type(entries) ~= "table" then error(api .. " requires entry array", 3) end
    for index, entry in ipairs(entries) do
        if type(entry) ~= "table" or type(entry.itemID) ~= "string" or entry.itemID == "" or type(entry.presentation) ~= "table" then
            error(api .. " entry " .. index .. " requires itemID and presentation", 3)
        end
        -- Runtime text/duration values may be opaque native values.  The module
        -- declaration is pure; the TextCollection is the only consumer here.
        for key, value in pairs(entry.presentation) do
            if key ~= "durationObject" and key ~= "secretDuration" and type(value) == "function" then
                error(api .. " presentation cannot contain functions", 3)
            end
        end
    end
end

local Controller = {}; Controller.__index = Controller
function Controller:GetConfig() return self.db end
function Controller:BuildGridLayout()
    local layout = {}
    for _, source in ipairs(self.spec.gui.static) do layout[#layout + 1] = copy(source) end
    for _, source in ipairs(self.spec.gui.fields) do
        local item = copy(source)
        if item.type == "anchorgroup" then
            item.opts = {
                bindRoot = self.spec.anchor.bindRoot == true,
                offsetXKey = self.spec.anchor.xKey, offsetYKey = self.spec.anchor.yKey,
                defaultOffsetX = self.spec.anchor.defaultX or 0, defaultOffsetY = self.spec.anchor.defaultY or 0,
                attachEnabledKey = self.spec.anchor.attachEnabledKey, attachTargetKey = self.spec.anchor.attachTargetKey,
                onPickFrame = function() return self.anchor:StartFramePicker() end,
            }
        elseif item.options then
            item.opts = copy(item.options); item.options = nil
        end
        layout[#layout + 1] = item
    end
    return layout
end
function Controller:Apply(collection, entries, layout)
    local items = {}
    for _, entry in ipairs(entries) do
        local item = collection:AcquireItem(entry.itemID)
        collection:ApplyItem(item, entry.presentation)
        items[#items + 1] = item
    end
    collection:SetItems(items, layout)
    return collection
end
function Controller:CreateCollection(host, mode)
    return EXUI:CreateTextCollection(host, mode, self.moduleKey)
end
function Controller:ClearRuntime()
    if self.runtimeCollection then self.runtimeCollection:Release(); self.runtimeCollection = nil end
    if self.anchor.frame then self.anchor.frame:Hide() end
end
function Controller:SetRuntime(entries, layout)
    validateEntries(entries, "SetRuntime")
    self.runtimeEntries, self.runtimeLayout = entries, layout or { direction = "UP", spacing = 0, maxVisible = 1 }
    if self.editing then return end
    if #entries == 0 then return self:ClearRuntime() end
    local host = self.anchor:Ensure(); self.anchor:ApplyPosition()
    self.runtimeCollection = self.runtimeCollection or self:CreateCollection(host, "runtime")
    self:Apply(self.runtimeCollection, self.runtimeEntries, self.runtimeLayout)
    local w, h = self.runtimeCollection:GetBounds(); host:SetSize(math.max(1, w or 1), math.max(1, h or 1)); host:Show()
end
function Controller:PlayRuntimeAlphaSequence(itemID, phases, clearOnFinished)
    requireString(itemID, "PlayRuntimeAlphaSequence itemID", 3)
    if type(phases) ~= "table" then error("PlayRuntimeAlphaSequence requires phases table", 3) end
    for _, phase in ipairs(phases) do
        if type(phase) ~= "table" or type(phase.from) ~= "number" or type(phase.to) ~= "number" or type(phase.duration) ~= "number" then
            error("PlayRuntimeAlphaSequence phases require numeric from/to/duration", 3)
        end
    end
    if not self.runtimeCollection then return false end
    return self.runtimeCollection:PlayItemAlphaSequence(itemID, phases, clearOnFinished == true and function()
        self:Clear()
    end or nil)
end
function Controller:Clear() return self:SetRuntime({}, { direction = "UP", spacing = 0, maxVisible = 1 }) end
function Controller:SetPreview(entries, layout)
    validateEntries(entries, "SetPreview")
    self.previewEntries, self.previewLayout = entries, layout or { direction = "UP", spacing = 0, maxVisible = 1 }
    if self.panel then self:RenderPanel() end
    if self.worldCollection then self:RenderWorld(self.anchor:Ensure()) end
end
function Controller:RenderPanel()
    if self.panel then self.panel:Render(self.previewEntries or {}, self.previewLayout) end
end
function Controller:MountPanel(dock)
    if self.panel then self.panel:Release() end
    self.panel = EXUI:CreateTextPanelPreview(dock, self.moduleKey)
    EXUI:BindStandardPreviewInteractions(self.panel, {
        moduleKey = self.moduleKey, binding = self.binding,
        requiredPositionGuiKeys = self.spec.preview and self.spec.preview.positionGuiKeys or {},
        elements = self.spec.preview and self.spec.preview.elements or {},
    })
    self:RenderPanel()
end
function Controller:ReleasePanel() if self.panel then self.panel:Release(); self.panel = nil end end
function Controller:RefreshActiveSurfaces(changedPath, phase)
    -- Core owns the one controller.  This optional hook only rebuilds the
    -- module's current presentation data before existing surfaces are reapplied.
    -- AnchorGroup 的手动输入和选择器共用这份 DB；统一由中央重套实际锚点。
    self.anchor:ApplyPosition()
    if self.moduleRefreshActiveSurfaces then self.moduleRefreshActiveSurfaces(self, changedPath, phase) end
    local function resolve(entries, id)
        for _, entry in ipairs(entries or {}) do if entry.itemID == id then return copy(entry.presentation) end end
    end
    local function reapply(surface, entries)
        if surface and type(surface.ReapplyCurrentItems) == "function" then surface:ReapplyCurrentItems(function(presentation, item)
            local nextPresentation = resolve(entries, item and item.id)
            if nextPresentation then for key in pairs(presentation) do presentation[key] = nil end; for key, value in pairs(nextPresentation) do presentation[key] = value end end
        end) end
    end
    reapply(self.panel, self.previewEntries); reapply(self.worldCollection, self.previewEntries); reapply(self.runtimeCollection, self.runtimeEntries)
end
function Controller:RenderWorld(host)
    if self.runtimeCollection then self.runtimeCollection:Release(); self.runtimeCollection = nil end
    if self.worldCollection then self.worldCollection:Release(); self.worldCollection = nil end
    self.worldCollection = self:CreateCollection(host, "world")
    self:Apply(self.worldCollection, self.previewEntries or {}, self.previewLayout)
    local w, h = self.worldCollection:GetBounds(); host:SetSize(math.max(1, w or 1), math.max(1, h or 1)); host:Show()
end
function Controller:ReleaseWorld() if self.worldCollection then self.worldCollection:Release(); self.worldCollection = nil end end
function Controller:GetWorldBounds() return self.worldCollection and self.worldCollection:GetWorldBounds() or nil end
function Controller:OnWorldPreviewStateChanged(editing)
    self.editing = editing == true
    if not self.editing and self.runtimeEntries then self:SetRuntime(self.runtimeEntries, self.runtimeLayout) end
end
function Controller:RefreshVisuals(options)
    options = type(options) == "table" and options or {}
    if self.panel and options.rebuildPanelPreview ~= false then self:RenderPanel() end
    if self.worldCollection then self:RenderWorld(self.anchor:Ensure()) end
    if self.runtimeEntries then self:SetRuntime(self.runtimeEntries, self.runtimeLayout) end
end

function EXUI:RegisterTextModule(spec)
    local declaration, refresh = splitRefreshContract(spec)
    validateSpec(declaration)
    local registered = copy(declaration); specs[registered.moduleKey] = registered
    local moduleMeta = ExwindTools:GetModuleMeta(registered.moduleKey)
    if not moduleMeta then error("MODULE_SPEC.moduleKey is missing from ExwindTools.ModuleList: " .. registered.moduleKey, 2) end
    local db = ExwindTools:GetModuleDB(registered.moduleKey)
    local controller = setmetatable({ moduleKey = registered.moduleKey, spec = registered, db = db, previewEntries = {}, moduleRefreshActiveSurfaces = refresh }, Controller)
    local anchorDB = getPath(db, registered.anchor.dbPath)
    if type(anchorDB) ~= "table" then error("MODULE_SPEC.anchor.dbPath does not resolve to table", 2) end
    controller.anchor = ExwindTools:CreateAnchorController({
        moduleKey = registered.moduleKey, frameName = "ExwindCentral_" .. registered.moduleKey:gsub("[^%w]", "_"), title = moduleMeta.Name,
        getDB = function() return anchorDB end,
        offsetXKey = registered.anchor.xKey, offsetYKey = registered.anchor.yKey,
        defaultOffsetX = registered.anchor.defaultX or 0, defaultOffsetY = registered.anchor.defaultY or 0,
        attachEnabledKey = registered.anchor.attachEnabledKey, attachTargetKey = registered.anchor.attachTargetKey,
        initialWidth = registered.anchor.initialWidth or 1, initialHeight = registered.anchor.initialHeight or 1,
        clampedToScreen = registered.anchor.clampedToScreen == true,
    })
    controller.binding = EXUI:RegisterStandardConfigBinding({
        moduleKey = registered.moduleKey, getConfig = function() return controller.db end,
    })
    EXUI:RegisterEditableModule({
        addon = "ExwindTools", key = registered.moduleKey, name = moduleMeta.Name,
        orientation = "HORIZONTAL", settingsPage = registered.moduleKey,
        getAnchor = function() return controller.anchor:Ensure() end,
        RenderWorld = function(host) controller:RenderWorld(host) end,
        ReleaseWorld = function() controller:ReleaseWorld() end,
        GetWorldBounds = function() return controller:GetWorldBounds() end,
        OnWorldPreviewStateChanged = function(editing) controller:OnWorldPreviewStateChanged(editing) end,
    })
    controllers[registered.moduleKey] = controller
    EXUI:RegisterModuleValueController(registered.moduleKey, controller)
    return controller
end
function EXUI:GetCentralTextModuleController(moduleKey) return specs[moduleKey] and controllers[moduleKey] or nil end
function EXUI:GetCentralTextModuleSpec(moduleKey) return specs[moduleKey] and copy(specs[moduleKey]) or nil end
function EXUI:GetCentralTextModuleKeys()
    local keys = {}; for key in pairs(specs) do keys[#keys + 1] = key end; table.sort(keys); return keys
end
