-- =========================================================
-- ExwindModuleDefinition
--
-- 新模块唯一入口。一个 ModuleDefinition 同时声明设置页、Panel Preview、
-- 输入事务与正式显示同步；它绝不经过 RegisterModuleLayout / RegisterModulePreview。
-- 旧注册表仍仅供未迁移模块使用，不能与本入口混用。
-- =========================================================

local ExwindTools = _G.ExwindTools
local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

if not ExwindTools or not ExwindTools.UI then return end

local EXUI = ExwindTools.UI
ExwindTools.ModuleDefinitions = ExwindTools.ModuleDefinitions or {}

local function RequireModuleKey(value, api)
    if type(value) ~= "string" or value == "" then
        error(api .. " requires a non-empty moduleKey", 3)
    end
    return value
end

local function RequireFunction(value, name)
    if type(value) ~= "function" then error("RegisterModule requires " .. name .. " function", 3) end
    return value
end

local function Equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do if right[key] ~= value then return false end end
    for key, value in pairs(right) do if left[key] ~= value then return false end end
    return true
end

local function ShallowCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, entry in pairs(value) do copy[key] = entry end
    return copy
end

local function CreatePanelSession(kind, dock, moduleKey, onIntent, options)
    local callbacks = type(onIntent) == "function" and { onIntent = onIntent } or nil
    if type(options) == "table" then
        callbacks = callbacks or {}
        for key, value in pairs(options) do callbacks[key] = value end
    end
    if kind == "icon" then return EXUI:CreateIconPanelPreview(dock, moduleKey, callbacks) end
    if kind == "timerbar" then return EXUI:CreateTimerBarPanelPreview(dock, moduleKey, callbacks) end
    if kind == "text" then return EXUI:CreateTextPanelPreview(dock, moduleKey, callbacks) end
    error("RegisterModule display.kind must be icon, timerbar, or text", 3)
end

local Controller = {}
Controller.__index = Controller

function Controller:GetConfig()
    local config = self.definition.getConfig()
    if type(config) ~= "table" then error("ModuleDefinition getConfig returned non-table: " .. self.moduleKey, 2) end
    return config
end

function Controller:GetLayout()
    local layout = self.definition.settings.layout
    layout = type(layout) == "function" and layout(self:GetConfig()) or layout
    if type(layout) ~= "table" then error("ModuleDefinition settings.layout must resolve to table: " .. self.moduleKey, 2) end
    return layout
end

function Controller:MountPreview(dock)
    if self.panel and self.dock ~= dock then self:ReleasePreview() end
    if not self.panel then
        self.panel = CreatePanelSession(self.definition.display.kind, dock, self.moduleKey, function(intent)
            local handler = self.definition.display.onIntent
            if handler then return handler(intent, self) end
        end, self.definition.display.panelOptions)
        self.dock = dock
    end
    return self:RenderPreview()
end

function Controller:RenderPreview()
    if not self.panel then return nil end
    local entries, layout = self.definition.display.buildPanel(self:GetConfig(), self)
    if type(entries) ~= "table" or type(layout) ~= "table" then
        error("ModuleDefinition display.buildPanel must return entries, layout: " .. self.moduleKey, 2)
    end
    self.panel:Render(entries, layout)
    local rendered = self.definition.display.onPanelRendered
    if rendered then rendered(self.panel, self.dock, self) end
    return self.panel
end

function Controller:ReleasePreview()
    if self.panel then self.panel:Release() end
    self.panel, self.dock = nil, nil
end

function Controller:RefreshRuntime()
    local refresh = self.definition.runtime and self.definition.runtime.refresh
    if refresh then refresh(self:GetConfig(), self) end
end

function Controller:RefreshActiveSurfaces(changedPath, phase)
    -- RegisterModule 只负责安装唯一 controller；具体模块必须从它自己的
    -- 当前 DB 重套已存在表面，Core 不猜测 Rule/Clone/Runtime 结构。
    return self.definition.RefreshActiveSurfaces(self, changedPath, phase)
end

-- 新模块唯一公开注册。注册后模块页从 definition.settings.layout 自动取得，
-- Preview 也只由本 controller 管理；禁止与任一旧注册表并存。
function ExwindTools:RegisterModule(definition)
    if type(definition) ~= "table" then error("RegisterModule requires definition table", 2) end
    local moduleKey = RequireModuleKey(definition.moduleKey, "RegisterModule")
    if self.ModuleDefinitions[moduleKey] then error("RegisterModule duplicate moduleKey: " .. moduleKey, 2) end
    if self.RegisteredLayouts and self.RegisteredLayouts[moduleKey] then
        error("RegisterModule cannot coexist with RegisterModuleLayout: " .. moduleKey, 2)
    end
    if self.ModulePreviewRenderers and self.ModulePreviewRenderers[moduleKey] then
        error("RegisterModule cannot coexist with RegisterModulePreview: " .. moduleKey, 2)
    end
    RequireFunction(definition.getConfig, "getConfig")
    if type(definition.settings) ~= "table" or definition.settings.layout == nil then
        error("RegisterModule requires settings.layout", 2)
    end
    if type(definition.display) ~= "table" then error("RegisterModule requires display table", 2) end
    RequireFunction(definition.display.buildPanel, "display.buildPanel")
    RequireFunction(definition.RefreshActiveSurfaces, "RefreshActiveSurfaces")
    definition.display.kind = definition.display.kind or "icon"

    local controller = setmetatable({ moduleKey = moduleKey, definition = definition }, Controller)
    self.ModuleDefinitions[moduleKey] = controller
    EXUI:RegisterModuleValueController(moduleKey, controller)
    if definition.editable ~= nil then
        if type(definition.editable) ~= "table" then error("RegisterModule editable must be table", 2) end
        EXUI:RegisterEditableModule(definition.editable)
    end
    return controller
end

function ExwindTools:GetModuleDefinition(moduleKey)
    return self.ModuleDefinitions[RequireModuleKey(moduleKey, "GetModuleDefinition")]
end

-- =========================================================
-- basicTimerBar declaration
--
-- 仍由上面的 ModuleDefinition Controller 管理。这个入口只负责把最小声明
-- 展开为同一套 settings / Panel / World / Runtime / InputTransaction 合同。
-- =========================================================

local function BasicTimerBarSchema(slots)
    slots = type(slots) == "table" and slots or {}
    return ExwindTools.StandardTimerBar.NormalizeSchema({
        timerBarKey = slots.timerBarKey or "timerGroup",
        layoutKey = slots.layoutKey or "layout",
        offsetXKey = false,
        offsetYKey = false,
        showTextBKey = false,
        showTextCKey = false,
        textA = { key = slots.textAKey or "font_spell", role = "spellName", label = L["文字"] },
        textB = { key = slots.textBKey or "font_target", role = "targetName", label = L["目标"], optional = true },
        textC = { key = slots.textCKey or "font_timer", role = "time", label = L["时间"] },
    })
end

local function BuildBasicAtlasSlots(model)
    local declarations = type(model) == "table" and model.atlasExtraSlots or nil
    if type(declarations) ~= "table" then return nil, nil, nil, nil end
    local hosts, values = {}, {}
    for _, slot in ipairs(declarations) do
        if type(slot) == "table" and type(slot.id) == "string" and slot.id ~= "" then
            hosts[slot.id] = {
                id = slot.id,
                shown = slot.shown ~= false,
                width = math.max(1, tonumber(slot.width) or 18),
                height = math.max(1, tonumber(slot.height) or 18),
                anchor = type(slot.anchor) == "table" and slot.anchor or {},
            }
            values[slot.id] = slot
        end
    end
    if not next(hosts) then return nil, nil, nil, nil end
    return hosts, values, function(widget, materializedHosts, payloads)
        -- TimerBar 的 ExtraHost map 只由 Collection 回调传入；保存在 widget 的
        -- Core-private 字段，release 与同一份 map 配对，绝不猜测 Widget internals。
        widget._exuiBasicAtlasHosts = materializedHosts
        for id, slot in pairs(payloads) do
            local host = materializedHosts[id]
            if host then
                local child = host._exuiBasicAtlas
                if not child or child._released then
                    child = EXUI:CreateExtraTextureWidget(host)
                    host._exuiBasicAtlas = child
                end
                child:SetSize(math.max(1, host:GetWidth() or 1), math.max(1, host:GetHeight() or 1))
                child:SetAnchor("CENTER", host, "CENTER", 0, 0)
                if slot.atlasName and slot.atlasName ~= "" then
                    child:SetAtlas(slot.atlasName)
                elseif tonumber(slot.raidMarkerNumber) then
                    child:SetRaidTargetIndex(math.floor(slot.raidMarkerNumber))
                else
                    child:Clear()
                end
                child:SetVisible(slot.shown ~= false)
            end
        end
    end, function(widget)
        local hostsByID = type(widget) == "table" and widget._exuiBasicAtlasHosts or nil
        for _, host in pairs(type(hostsByID) == "table" and hostsByID or {}) do
            local child = host and host._exuiBasicAtlas
            if child then
                child:Release()
                host._exuiBasicAtlas = nil
            end
        end
        if widget then widget._exuiBasicAtlasHosts = nil end
    end
end

local function BasicPresentation(definition, schema, mode)
    local state = {}
    for key, value in pairs(definition._basicState or {}) do state[key] = value end
    state.mode = mode
    local model = definition.BuildDisplayModel(state, definition.getConfig()) or {}
    local hosts, children, renderChildren, releaseChildren = BuildBasicAtlasSlots(model)
    -- basicTimerBar 的三文字槽永远是 StandardTimerBar 的固定样本。模块可覆盖
    -- 内容，但 Panel/World 在无业务状态时仍提供非空名称、目标与时间文本。
    local content = ShallowCopy(model.content)
    if content.textA == nil then content.textA = state.text or "Standard TimerBar" end
    if content.textB == nil then content.textB = "EXUI Target" end
    if content.textC == nil and content.durationObject == nil and content.secretDuration == nil
        and content.start == nil then
        content.textC = "5.0"
    end
    return {
        schema = schema,
        db = definition.getConfig(),
        content = content,
        textColors = model.textColors,
        textShownFromBoolean = model.textShownFromBoolean,
        extraHosts = hosts,
        extraChildren = children,
        renderExtraChildren = renderChildren,
        releaseExtraChildren = releaseChildren,
        shown = model.shown ~= false,
    }
end

local function BasicApplyCollection(collection, definition, schema, mode, itemID)
    local item = collection:AcquireItem(itemID)
    collection:ApplyItem(item, BasicPresentation(definition, schema, mode))
    collection:SetItems({ item }, definition.getConfig()[schema.layoutKey])
    return item
end

function EXUI:RegisterBasicTimerBar(declaration)
    if type(declaration) ~= "table" then error("RegisterBasicTimerBar requires declaration", 2) end
    local moduleKey = RequireModuleKey(declaration.moduleKey, "RegisterBasicTimerBar")
    if type(declaration.defaultVisualDB) ~= "table" then error("RegisterBasicTimerBar requires defaultVisualDB", 2) end
    if type(declaration.basicTimerBar) ~= "table" then error("RegisterBasicTimerBar requires basicTimerBar", 2) end
    if type(declaration.BuildDisplayModel) ~= "function" then error("RegisterBasicTimerBar requires BuildDisplayModel", 2) end

    local schema = BasicTimerBarSchema(declaration.basicTimerBar)
    local sourceGroups = {
        "anchor", schema.layoutKey, schema.timerBarKey, schema.textA.key, schema.textB.key, schema.textC.key,
    }
    local defaultSchema = {}
    for _, group in ipairs(sourceGroups) do
        local source = declaration.defaultVisualDB[group]
        if type(source) ~= "table" then
            error("RegisterBasicTimerBar defaultVisualDB." .. tostring(group) .. " must be a table", 2)
        end
        local fields = {}
        for field in pairs(source) do fields[#fields + 1] = field end
        table.sort(fields)
        defaultSchema[#defaultSchema + 1] = { group = group, fields = fields }
    end
    ExwindTools:DeclareModuleDefaults(moduleKey, declaration.defaultVisualDB, defaultSchema)
    local db = ExwindTools:GetModuleDB(moduleKey)
    ExwindTools.StandardTimerBar.EnsureDefaults(db, schema)
    db.anchor = type(db.anchor) == "table" and db.anchor or { x = 0, y = 0 }
    if db.anchor.x == nil then db.anchor.x = 0 end
    if db.anchor.y == nil then db.anchor.y = 0 end

    local runtimeCollection, worldCollection, anchorController, EnsureBasicAnchor
    local definition = {
        moduleKey = moduleKey,
        getConfig = function() return db end,
        BuildDisplayModel = declaration.BuildDisplayModel,
        _basicSchema = schema,
        _basicState = { active = false },
        settings = {
            layout = {
                { key = "header", type = "header", x = 1, y = 1, w = 197, h = 8,
                    label = "EXUI Standard TimerBar Test", labelSize = 25 },
                { key = "description", type = "description", x = 1, y = 14, w = 197, h = 10,
                    label = "/run extoolstest(\"timerbar\", 5, \"text\", 8, \"atlas\")" },
                { key = schema.timerBarKey, type = "timerbargroup", x = 1, y = 27, w = 197, h = 56,
                    measure = true, label = "TimerBar", opts = {} },
                { key = schema.textA.key, type = "fontgroup", x = 1, y = 87, w = 197, h = 50,
                    measure = true, label = L["法术名称"], opts = {} },
                { key = schema.textB.key, type = "fontgroup", x = 1, y = 141, w = 197, h = 50,
                    measure = true, label = L["目标名称"], opts = {} },
                { key = schema.textC.key, type = "fontgroup", x = 1, y = 195, w = 197, h = 50,
                    measure = true, label = L["时间"], opts = {} },
            },
        },
        display = {
            kind = "timerbar",
            basicTimerBar = true,
            timerBarKey = schema.timerBarKey,
            panelOptions = { schema = schema },
            buildPanel = function()
                return { { itemID = moduleKey .. ":panel", presentation = BasicPresentation(definition, schema, "panel") } }, db[schema.layoutKey]
            end,
        },
        runtime = {
            refresh = function()
                if definition._basicState.active ~= true then return end
                local host = EnsureBasicAnchor()
                anchorController:ApplyPosition()
                runtimeCollection = runtimeCollection or EXUI:CreateStandardTimerBarCollection(host, "runtime", moduleKey, { schema = schema })
                definition._basicRuntimeCollection = runtimeCollection
                BasicApplyCollection(runtimeCollection, definition, schema, "runtime", moduleKey .. ":runtime")
                local width, height = runtimeCollection:GetBounds()
                host:SetSize(math.max(1, width or 1), math.max(1, height or 1))
                host:Show()
            end,
        },
        RefreshActiveSurfaces = function(controller)
            local function reapply(surface, mode)
                if not surface or type(surface.ReapplyCurrentItems) ~= "function" then return end
                surface:ReapplyCurrentItems(function(presentation)
                    local nextPresentation = BasicPresentation(definition, schema, mode)
                    for key in pairs(presentation) do presentation[key] = nil end
                    for key, value in pairs(nextPresentation) do presentation[key] = value end
                end)
                if type(surface.ReapplyCurrentLayout) == "function" then
                    surface:ReapplyCurrentLayout(db[schema.layoutKey])
                end
            end
            if anchorController then anchorController:ApplyPosition() end
            reapply(controller.panel, "panel")
            reapply(runtimeCollection, "runtime")
            reapply(worldCollection, "world")
        end,
    }

    EnsureBasicAnchor = function()
        if not anchorController then
            anchorController = ExwindTools:CreateAnchorController({
                moduleKey = moduleKey,
                frameName = "ExwindBasicTimerBar_" .. moduleKey:gsub("[^%w]", "_"),
                title = "EXUI Standard TimerBar Test",
                getDB = function() return db.anchor end,
                offsetXKey = "x", offsetYKey = "y",
                defaultOffsetX = 0, defaultOffsetY = 0,
                initialWidth = db[schema.timerBarKey].width,
                initialHeight = db[schema.timerBarKey].height,
                clampedToScreen = true,
            })
            definition._basicAnchor = anchorController
        end
        return anchorController:Ensure()
    end

    local controller = ExwindTools:RegisterModule(definition)
    EXUI:RegisterEditableModule({
        addon = "ExwindTools", key = moduleKey, name = "EXUI Standard TimerBar Test",
        orientation = "HORIZONTAL", settingsPage = moduleKey,
        getAnchor = function()
            return EnsureBasicAnchor()
        end,
        RenderWorld = function(host)
            if worldCollection then worldCollection:Release() end
            worldCollection = EXUI:CreateStandardTimerBarCollection(host, "world", moduleKey, { schema = schema })
            definition._basicWorldCollection = worldCollection
            BasicApplyCollection(worldCollection, definition, schema, "world", moduleKey .. ":world")
        end,
        ReleaseWorld = function()
            if worldCollection then worldCollection:Release() end
            worldCollection = nil
            definition._basicWorldCollection = nil
        end,
        GetWorldBounds = function()
            return worldCollection and worldCollection:GetWorldBounds() or nil
        end,
    })
    return controller
end

function EXUI:RunDisplayTest(kind, seconds, text, raidMarkerNumber, atlasName)
    if kind ~= "timerbar" then error('usage: extoolstest("timerbar", seconds, text, raidMarkerNumber, atlasName)', 2) end
    local controller = ExwindTools.ModuleDefinitions["ExTools.StandardTimerBarTest"]
    if not controller then error("StandardTimerBarTest is not registered", 2) end
    seconds = tonumber(seconds) or 5
    if seconds <= 0 then error("extoolstest seconds must be positive", 2) end
    if not _G.C_DurationUtil or not _G.C_DurationUtil.CreateDuration then error("C_DurationUtil is unavailable", 2) end
    local definition = controller.definition
    definition._basicGeneration = (definition._basicGeneration or 0) + 1
    local generation = definition._basicGeneration
    local duration = _G.C_DurationUtil.CreateDuration()
    duration:SetTimeFromStart(GetTime(), seconds, 1)
    definition._basicState = {
        active = true, duration = duration, seconds = seconds, text = tostring(text or "Standard TimerBar"),
        raidMarkerNumber = tonumber(raidMarkerNumber), atlasName = atlasName,
    }
    controller:RefreshRuntime()
    C_Timer.After(seconds, function()
        if definition._basicGeneration ~= generation then return end
        definition._basicState = { active = false }
        if definition._basicRuntimeCollection then
            definition._basicRuntimeCollection:SetItems({}, definition.getConfig()[definition._basicSchema.layoutKey])
        end
        if definition._basicAnchor then definition._basicAnchor:Ensure():Hide() end
    end)
    return controller
end

_G.extoolstest = function(kind, seconds, text, raidMarkerNumber, atlasName)
    return EXUI:RunDisplayTest(kind, seconds, text, raidMarkerNumber, atlasName)
end
