-- EXUI 中央显示入口：只管理既有 IconCollection 宿主；不含模块业务或模块专用分支。
local ExwindTools = _G.ExwindTools
if type(ExwindTools) ~= "table" or type(ExwindTools.UI) ~= "table" then error("ExwindCentralRender requires initialized EXUI", 0) end
local EXUI = ExwindTools.UI
if EXUI.CentralRenderModuleRegistryInitialized then error("ExwindCentralRender already initialized", 0) end
EXUI.CentralRenderModuleRegistryInitialized = true

local specs = {}
local controllers = EXUI.CentralModuleControllers or {}
EXUI.CentralModuleControllers = controllers
local function requireString(value, name, level)
    if type(value) ~= "string" or value:match("^%s*$") then error(name .. " must be non-empty string", level or 3) end
    return value
end
local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}; if seen[value] then error("central declaration must not be cyclic", 3) end
    local result = {}; seen[value] = true
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    seen[value] = nil; return result
end
local function requireGeometry(item, name)
    for _, key in ipairs({ "x", "y", "w", "h" }) do if type(item[key]) ~= "number" then error(name .. " requires numeric " .. key, 3) end end
    if item.w <= 0 or item.h <= 0 then error(name .. " requires positive w/h", 3) end
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
local function validateGUI(gui, moduleKey)
    if type(gui) ~= "table" then error("MODULE_SPEC.gui is required", 3) end
    if gui.version ~= 1 or type(gui.sections) ~= "table" or gui.cards ~= nil
        or gui.static ~= nil or gui.fields ~= nil or gui.groups ~= nil then
        error("MODULE_SPEC.gui accepts only version=1 sections; special cards are not a central-module settings entry", 3)
    end
    local grid = _G.ExwindGrid
    if not grid or type(grid.ValidateSettingsDeclaration) ~= "function" then
        error("MODULE_SPEC.gui version 1 requires ExwindGrid typed settings validation", 3)
    end
    local ok, reason = grid:ValidateSettingsDeclaration(gui, {
        pageId = moduleKey,
        regionId = "central-icon-registration",
    })
    if not ok then error(reason, 3) end
end
local function visitGUIItems(gui, visitor)
    local function visit(items, contextPath)
        for _, item in ipairs(items or {}) do
            local currentPath = contextPath
            if item.parentKey ~= nil then
                currentPath = currentPath and (currentPath .. "." .. tostring(item.parentKey))
                    or tostring(item.parentKey)
            end
            visitor(item, currentPath)
            if type(item.children) == "table" then visit(item.children, currentPath) end
        end
    end
    if gui.version == 1 then
        for _, section in ipairs(gui.sections) do
            if section.kind == "settings" then
                for _, item in ipairs(section.items or {}) do
                    if item.controls then visit(item.controls) else visit({ item }) end
                end
            elseif section.kind == "table" then
                local function visitCells(cells)
                    for _, cell in ipairs(cells or {}) do
                        if type(cell) == "table" and cell.text == nil then visit({ cell }) end
                    end
                end
                if section.add then visitCells(section.add.cells) end
                for _, row in ipairs(section.records or {}) do visitCells(row.cells) end
            elseif section.kind == "composite" then
                visit({ {
                    type = string.lower(section.component), key = section.key,
                    parentKey = section.parentKey, subKey = section.subKey,
                    setKey = section.setKey, opts = section.opts,
                } })
            end
        end
        return
    end
    visit(gui.static)
    visit(gui.fields)
end
local function declaredItemPath(item, contextPath)
    if type(item.opts) == "table" and item.opts.bindRoot == true then return "$root" end
    if item.setKey ~= nil then return tostring(item.setKey) end
    local key = item.subKey or item.key
    if contextPath ~= nil then return tostring(contextPath) .. "." .. tostring(key) end
    if item.parentKey ~= nil then return tostring(item.parentKey) .. "." .. tostring(key) end
    return tostring(key)
end
local function validateSpec(spec)
    if type(spec) ~= "table" then error("RegisterIconModule requires MODULE_SPEC", 3) end
    validatePure(spec, "MODULE_SPEC"); requireString(spec.moduleKey, "MODULE_SPEC.moduleKey", 3)
    if spec.kind ~= "icon" then error("MODULE_SPEC.kind must be icon", 3) end
    if specs[spec.moduleKey] then error("duplicate MODULE_SPEC: " .. spec.moduleKey, 3) end
    if spec.catalog ~= nil then error("MODULE_SPEC.catalog is forbidden; define metadata in ExwindTools.ModuleList", 3) end
    validateGUI(spec.gui, spec.moduleKey)
    if type(spec.anchor) ~= "table" then error("MODULE_SPEC.anchor is required", 3) end
    requireString(spec.anchor.dbPath, "MODULE_SPEC.anchor.dbPath", 3); requireString(spec.anchor.xKey, "MODULE_SPEC.anchor.xKey", 3); requireString(spec.anchor.yKey, "MODULE_SPEC.anchor.yKey", 3)
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
        if type(entry) ~= "table" or type(entry.itemID) ~= "string" or entry.itemID == "" or type(entry.presentation) ~= "table" then error(api .. " entry " .. index .. " requires itemID and presentation", 3) end
        validatePure(entry.presentation, api .. " presentation")
    end
end

local Controller = {}; Controller.__index = Controller
function Controller:GetConfig() return self.db end
function Controller:CompileGUIItem(source, preservePlacement)
    local item = copy(source)
    if not preservePlacement then item.group, item.order = nil, nil end
    if item.type == "anchorgroup" then
        local opts = copy(item.opts or item.options or {})
        opts.bindRoot = self.spec.anchor.bindRoot == true
        opts.offsetXKey = self.spec.anchor.xKey
        opts.offsetYKey = self.spec.anchor.yKey
        opts.defaultOffsetX = self.spec.anchor.defaultX or 0
        opts.defaultOffsetY = self.spec.anchor.defaultY or 0
        opts.attachEnabledKey = self.spec.anchor.attachEnabledKey
        opts.attachTargetKey = self.spec.anchor.attachTargetKey
        opts.onPickFrame = function() return self.anchor:StartFramePicker() end
        item.opts, item.options = opts, nil
    elseif item.type == "icongroup" then
        local opts = copy(item.opts or item.options or {})
        opts.hideIconID = true
        item.opts, item.options = opts, nil
    elseif item.options then
        item.opts = copy(item.options); item.options = nil
    end
    if type(item.children) == "table" then
        local children = {}
        for index, child in ipairs(item.children) do
            children[index] = self:CompileGUIItem(child, true)
        end
        item.children = children
    end
    return item
end
function Controller:BuildGridLayout()
    if self.spec.gui.version == 1 then
        error("card MODULE_SPEC.gui must be requested through BuildSettingsDeclaration", 2)
    end
    local layout = {}; for _, source in ipairs(self.spec.gui.static) do layout[#layout + 1] = copy(source) end
    for _, source in ipairs(self.spec.gui.fields) do
        layout[#layout + 1] = self:CompileGUIItem(source, false)
    end
    return layout
end
function Controller:BuildSettingsDeclaration()
    if self.spec.gui.version ~= 1 then return self:BuildGridLayout() end
    local declaration = copy(self.spec.gui)
    for _, section in ipairs(declaration.sections) do
        if section.kind == "composite" then
            local item = self:CompileGUIItem({
                type = string.lower(section.component),
                opts = section.opts,
            }, true)
            section.opts = item.opts
        end
    end
    return declaration
end
function Controller:Apply(collection, entries, layout)
    local items = {}; for _, entry in ipairs(entries) do local item = collection:AcquireItem(entry.itemID); collection:ApplyItem(item, entry.presentation); items[#items + 1] = item end; collection:SetItems(items, layout); return collection
end
function Controller:ClearRuntime()
    if self.runtimeCollection then self.runtimeCollection:Release(); self.runtimeCollection = nil end
    if self.anchor.frame then self.anchor.frame:Hide() end
end
function Controller:SetRuntime(entries, layout)
    validateEntries(entries, "SetRuntime"); self.runtimeEntries, self.runtimeLayout = entries, layout or { direction = "RIGHT", spacing = 0, maxVisible = 1 }
    if self.editing then return end; if #entries == 0 then return self:ClearRuntime() end
    local host = self.anchor:Ensure(); self.anchor:ApplyPosition(); self.runtimeCollection = self.runtimeCollection or EXUI:CreateIconCollection(host, "runtime", self.moduleKey)
    self:Apply(self.runtimeCollection, self.runtimeEntries, self.runtimeLayout); local w,h=self.runtimeCollection:GetBounds(); host:SetSize(math.max(1,w or 1),math.max(1,h or 1)); host:Show()
end
function Controller:Clear() return self:SetRuntime({}, { direction = "RIGHT", spacing = 0, maxVisible = 1 }) end
function Controller:SetPreview(entries, layout)
    validateEntries(entries, "SetPreview"); self.previewEntries, self.previewLayout = entries, layout or { direction = "RIGHT", spacing = 0, maxVisible = 1 }
    if self.panel then self:RenderPanel() end; if self.worldCollection then self:RenderWorld(self.anchor:Ensure()) end
end
function Controller:RenderPanel()
    if self.panel then self.panel:Render(self.previewEntries or {}, self.previewLayout) end
end
function Controller:MountPanel(dock)
    if self.panel then self.panel:Release() end; self.panel = EXUI:CreateIconPanelPreview(dock, self.moduleKey, {})
    EXUI:BindStandardPreviewInteractions(self.panel, { moduleKey = self.moduleKey, binding = self.binding, requiredPositionGuiKeys = self.spec.preview and self.spec.preview.positionGuiKeys or {}, elements = self.spec.preview and self.spec.preview.elements or {}, resize = { widthPath = self.resizePath .. ".width", heightPath = self.resizePath .. ".height", minWidth = 10, maxWidth = 300, minHeight = 10, maxHeight = 300 } }); self:RenderPanel()
end
function Controller:ReleasePanel() if self.panel then self.panel:Release(); self.panel = nil end end
-- GUI 连续输入只做一件事：写入模块唯一 DB 后，重套已经存在的三处
-- presentation。这里不解析字段名、不维护字段映射，也不触碰模块业务。
function Controller:RefreshActiveSurfaces(changedPath, phase)
    -- The Core controller remains the sole value controller.  A factory module
    -- may only supply this one business projection hook; it never registers a
    -- second controller or receives a GUI callback itself.
    -- AnchorGroup 的手动输入和选择器都已经写入同一份 DB；每次提交统一重套
    -- AnchorController，避免模块各自猜测锚点字段路径。
    self.anchor:ApplyPosition()
    if self.moduleRefreshActiveSurfaces then self.moduleRefreshActiveSurfaces(self, changedPath, phase) end
    local function resolve(entries, id)
        for _, entry in ipairs(entries or {}) do if entry.itemID == id then return copy(entry.presentation) end end
    end
    local function reapply(surface, entries, layout)
        if surface and type(surface.ReapplyCurrentItems) == "function" then surface:ReapplyCurrentItems(function(presentation, item)
            local nextPresentation = resolve(entries, item and item.id)
            if nextPresentation then for key in pairs(presentation) do presentation[key] = nil end; for key, value in pairs(nextPresentation) do presentation[key] = value end end
        end)
        -- ReapplyCurrentItems preserves the surface's old currentLayout.  Layout
        -- fields are a separate input path, so apply the controller's freshly
        -- projected layout to the same materialized item set as well.
        if type(surface.ReapplyCurrentLayout) == "function" then surface:ReapplyCurrentLayout(layout) end
        end
    end
    reapply(self.panel, self.previewEntries, self.previewLayout)
    reapply(self.worldCollection, self.previewEntries, self.previewLayout)
    reapply(self.runtimeCollection, self.runtimeEntries, self.runtimeLayout)
end
function Controller:RenderWorld(host)
    if self.runtimeCollection then self.runtimeCollection:Release(); self.runtimeCollection = nil end; if self.worldCollection then self.worldCollection:Release(); self.worldCollection = nil end
    self.worldCollection = EXUI:CreateIconCollection(host, "world", self.moduleKey); self:Apply(self.worldCollection, self.previewEntries or {}, self.previewLayout); local w,h=self.worldCollection:GetBounds(); host:SetSize(math.max(1,w or 1),math.max(1,h or 1)); host:Show()
end
function Controller:ReleaseWorld() if self.worldCollection then self.worldCollection:Release(); self.worldCollection = nil end end
function Controller:GetWorldBounds() return self.worldCollection and self.worldCollection:GetWorldBounds() or nil end
function Controller:OnWorldPreviewStateChanged(editing) self.editing = editing == true; if not self.editing and self.runtimeEntries then self:SetRuntime(self.runtimeEntries,self.runtimeLayout) end end
function Controller:RefreshVisuals(options)
    options = type(options) == "table" and options or {}
    if self.panel and options.rebuildPanelPreview ~= false then self:RenderPanel() end
    if self.worldCollection then self:RenderWorld(self.anchor:Ensure()) end
    if self.runtimeEntries then self:SetRuntime(self.runtimeEntries,self.runtimeLayout) end
end

function EXUI:RegisterIconModule(spec)
    local declaration, refresh = splitRefreshContract(spec)
    validateSpec(declaration); local registered = copy(declaration); specs[registered.moduleKey] = registered
    local moduleMeta = ExwindTools:GetModuleMeta(registered.moduleKey)
    if not moduleMeta then error("MODULE_SPEC.moduleKey is missing from ExwindTools.ModuleList: " .. registered.moduleKey, 2) end
    local db = ExwindTools:GetModuleDB(registered.moduleKey); local controller=setmetatable({ moduleKey=registered.moduleKey,spec=registered,db=db,previewEntries={},moduleRefreshActiveSurfaces=refresh },Controller)
    local anchorDB=getPath(db,registered.anchor.dbPath); if type(anchorDB) ~= "table" then error("MODULE_SPEC.anchor.dbPath does not resolve to table",2) end
    visitGUIItems(registered.gui, function(field, contextPath)
        if field.type == "icongroup" then
            if controller.resizePath then error("MODULE_SPEC icon family requires exactly one icongroup", 2) end
            controller.resizePath = declaredItemPath(field, contextPath)
        end
    end)
    local resizeDB = controller.resizePath and getPath(db, controller.resizePath) or nil
    if type(resizeDB) ~= "table" or type(resizeDB.width) ~= "number" or type(resizeDB.height) ~= "number" then
        error("MODULE_SPEC icon family requires one icongroup with numeric width/height", 2)
    end
    controller.anchor=ExwindTools:CreateAnchorController({ moduleKey=registered.moduleKey,frameName="ExwindCentral_"..registered.moduleKey:gsub("[^%w]","_"),title=moduleMeta.Name,getDB=function() return anchorDB end,offsetXKey=registered.anchor.xKey,offsetYKey=registered.anchor.yKey,defaultOffsetX=registered.anchor.defaultX or 0,defaultOffsetY=registered.anchor.defaultY or 0,attachEnabledKey=registered.anchor.attachEnabledKey,attachTargetKey=registered.anchor.attachTargetKey,initialWidth=registered.anchor.initialWidth or 1,initialHeight=registered.anchor.initialHeight or 1,clampedToScreen=registered.anchor.clampedToScreen==true })
    controller.binding=EXUI:RegisterStandardConfigBinding({ moduleKey=registered.moduleKey,getConfig=function() return controller.db end })
    if registered.gui.version == 1 then
        if type(EXUI.RegisterSettingsPage) ~= "function" then error("RegisterSettingsPage is unavailable", 2) end
        EXUI:RegisterSettingsPage(registered.moduleKey, registered.gui)
    end
    EXUI:RegisterEditableModule({ addon="ExwindTools",key=registered.moduleKey,name=moduleMeta.Name,orientation="HORIZONTAL",settingsPage=registered.moduleKey,getAnchor=function() return controller.anchor:Ensure() end,RenderWorld=function(host) controller:RenderWorld(host) end,ReleaseWorld=function() controller:ReleaseWorld() end,GetWorldBounds=function() return controller:GetWorldBounds() end,OnWorldPreviewStateChanged=function(editing) controller:OnWorldPreviewStateChanged(editing) end })
    controllers[registered.moduleKey]=controller
    EXUI:RegisterModuleValueController(registered.moduleKey, controller)
    return controller
end
function EXUI:GetCentralModuleController(moduleKey) return controllers[moduleKey] end
function EXUI:GetCentralModuleSpec(moduleKey) return specs[moduleKey] and copy(specs[moduleKey]) or nil end
function EXUI:GetCentralModuleKeys() local keys={};for key in pairs(specs) do keys[#keys+1]=key end;table.sort(keys);return keys end
