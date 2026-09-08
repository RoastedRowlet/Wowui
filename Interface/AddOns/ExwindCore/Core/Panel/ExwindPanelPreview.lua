-- =============================================================
-- ExwindPanelPreview.lua
-- 设置页 PreviewDock 的唯一会话封装。
--
-- 这里不创建第二套视觉树、不解释模块业务，也不拥有 Dock 的页面几何。
-- 它只把同一份 presentation 交给已存在的 Icon/Text/TimerBar Collection，
-- 固定 interactionMode="panel"、contentCenter=true，并统一生命周期。
-- =============================================================

local ExwindTools = _G.ExwindTools
local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

if not ExwindTools or not ExwindTools.UI then return end
local EXUI = ExwindTools.UI

-- GUI 修改 ModuleDB 后的唯一刷新注册表。注册项只能重套已经存在的
-- presentation；创建、释放与完整 Render 仍只属于各自正常的生命周期入口。
local moduleValueControllers = EXUI.ModuleValueControllers or {}
EXUI.ModuleValueControllers = moduleValueControllers

function EXUI:RegisterModuleValueController(moduleKey, controller)
    moduleKey = EXUI:RequireModuleKey(moduleKey, "RegisterModuleValueController")
    if type(controller) ~= "table" or type(controller.RefreshActiveSurfaces) ~= "function" then
        error("module value controller requires RefreshActiveSurfaces", 2)
    end
    if moduleValueControllers[moduleKey] ~= nil then
        error("module value controller already registered: " .. moduleKey, 2)
    end
    moduleValueControllers[moduleKey] = controller
    return controller
end

function EXUI:NotifyModuleValueChanged(moduleKey, changedPath, phase)
    moduleKey = EXUI:RequireModuleKey(moduleKey, "NotifyModuleValueChanged")
    if type(changedPath) ~= "string" or changedPath == "" then
        error("NotifyModuleValueChanged requires changedPath", 2)
    end
    if phase ~= "changing" and phase ~= "committed" then
        error("NotifyModuleValueChanged phase must be changing or committed", 2)
    end
    local controller = moduleValueControllers[moduleKey]
    if not controller then return false end
    -- The controller always remains the one formal module entry.  Path is not
    -- a routing key; phase only distinguishes the cheap drag projection from
    -- the final committed projection.
    controller:RefreshActiveSurfaces(changedPath, phase)
    return true
end

function EXUI:CreateModuleNotifyFlow(options)
    if type(options) ~= "table" or type(options.moduleKey) ~= "string" or options.moduleKey == ""
        or type(options.path) ~= "string" or options.path == "" or type(options.writeValue) ~= "function" then
        error("CreateModuleNotifyFlow requires moduleKey, path and writeValue", 2)
    end
    return {
        onBegin = function() end,
        onLive = function(value)
            options.writeValue(value)
            EXUI:NotifyModuleValueChanged(options.moduleKey, options.path, "changing")
        end,
        onCommit = function(value)
            options.writeValue(value)
            EXUI:NotifyModuleValueChanged(options.moduleKey, options.path, "committed")
        end,
    }
end

function EXUI:CommitModuleValue(options, value)
    if type(options) ~= "table" or type(options.moduleKey) ~= "string" or options.moduleKey == ""
        or type(options.path) ~= "string" or options.path == "" or type(options.writeValue) ~= "function" then
        error("CommitModuleValue requires moduleKey, path and writeValue", 2)
    end
    options.writeValue(value)
    return EXUI:NotifyModuleValueChanged(options.moduleKey, options.path, "committed")
end

-- 已注册的标准显示合同。这里只保存声明和函数，不缓存 config table、不读取业务
-- state，也不创建 renderer；EXAura 的 per-rule getConfig 因而始终可返回当前 rule。
local standardDisplayModules = {}
-- AnchorController is loaded after this file.  It registers the same immutable
-- declaration here; RegisterStandardConfigBinding then joins the three Core
-- contracts (binding/surface/anchor) by ModuleKey rather than allowing Pages
-- to carry a second, private copy.
local standardAnchorDeclarations = {}

function EXUI:RegisterStandardConfigBinding(binding)
    if type(binding) ~= "table" then error("RegisterStandardConfigBinding requires table", 2) end
    local moduleKey = EXUI:RequireModuleKey(binding.moduleKey, "RegisterStandardConfigBinding")
    if standardDisplayModules[moduleKey] then error("standard display binding already registered: " .. moduleKey, 2) end
    if type(binding.getConfig) ~= "function" then error("standard display binding requires getConfig", 2) end
    binding.contract = binding.contract or {}
    if type(binding.contract) ~= "table" then error("standard display binding contract must be table", 2) end
    binding.contract.moduleKey = moduleKey
    binding.contract.binding = binding
    binding.contract.anchor = standardAnchorDeclarations[moduleKey]
    standardDisplayModules[moduleKey] = binding
    -- Binding 只声明标准配置和锚点合同；它绝不能暗中安装一个只会重套
    -- Panel 的 fallback controller。正式 RefreshActiveSurfaces 必须由 Core
    -- 工厂或 SPECIAL 模块各注册一次。
    return binding
end

function EXUI:GetStandardConfigBinding(moduleKey)
    return standardDisplayModules[EXUI:RequireModuleKey(moduleKey, "GetStandardConfigBinding")]
end

function EXUI:RegisterStandardAnchorDeclaration(moduleKey, declaration)
    moduleKey = EXUI:RequireModuleKey(moduleKey, "RegisterStandardAnchorDeclaration")
    if type(declaration) ~= "table" or declaration.moduleKey ~= moduleKey then
        error("standard anchor declaration must match moduleKey", 2)
    end
    if standardAnchorDeclarations[moduleKey] and standardAnchorDeclarations[moduleKey] ~= declaration then
        error("standard anchor declaration already registered: " .. moduleKey, 2)
    end
    standardAnchorDeclarations[moduleKey] = declaration
    local binding = standardDisplayModules[moduleKey]
    if binding then binding.contract.anchor = declaration end
end

local function ValidateAnchorDeclaration(binding, declaration)
    if type(declaration) ~= "table" then error("missing standard Anchor declaration") end
    local requiredFields = { "offsetXKey", "offsetYKey" }
    if declaration.allowCustomAttach ~= false then
        requiredFields[#requiredFields + 1] = "attachEnabledKey"
        requiredFields[#requiredFields + 1] = "attachTargetKey"
    end
    for _, field in ipairs(requiredFields) do
        local path = declaration[field]
        if type(path) ~= "string" or path == "" then error("standard Anchor declaration has invalid path: " .. tostring(field)) end
    end
    if type(declaration.syncWidgets) == "table" then
        for _, path in ipairs(declaration.syncWidgets) do
            if type(path) ~= "string" or path == "" then error("standard Anchor declaration has invalid sync path") end
        end
    end
    local anchorDB = type(declaration.getDB) == "function" and declaration.getDB() or declaration.db
    local bindingDB = binding.getConfig()
    if type(anchorDB) ~= "table" or anchorDB ~= bindingDB then
        error("standard Anchor must use the same DB table as its binding")
    end
end

function EXUI:ValidateRegisteredDisplayModules(expectedKeys, options)
    options = options or {}
    if expectedKeys ~= nil and type(expectedKeys) ~= "table" then
        error("ValidateRegisteredDisplayModules expectedKeys must be table", 2)
    end
    local result = {}
    local seen = {}
    local expected = nil
    if expectedKeys ~= nil then
        expected = {}
        for _, moduleKey in ipairs(expectedKeys) do
            expected[EXUI:RequireModuleKey(moduleKey, "ValidateRegisteredDisplayModules")] = true
        end
    end
    for moduleKey, binding in pairs(standardDisplayModules) do
        if not expected or expected[moduleKey] then
            local ok, reason = pcall(function()
                if type(binding.getConfig()) ~= "table" then
                    error("getConfig did not return table")
                end
                local contract = binding.contract
                if type(contract) ~= "table" or contract.binding ~= binding then
                    error("binding contract was not registered")
                end
                ValidateAnchorDeclaration(binding, contract.anchor)
                if options.requireSurface and type(contract.surface) ~= "table" then
                    error("missing StandardPreviewSurface declaration")
                end
                if options.requirePage and contract.page ~= true then
                    error("missing StandardModulePage declaration")
                end
                if options.requireSlider and type(contract.slider) ~= "table" and type(contract.slider) ~= "function" then
                    error("missing standard Slider declaration")
                end
            end)
            seen[moduleKey] = true
            result[#result + 1] = { moduleKey = moduleKey, ok = ok, reason = ok and nil or tostring(reason) }
        end
    end
    for _, moduleKey in ipairs(expectedKeys or {}) do
        if not seen[moduleKey] then
            result[#result + 1] = { moduleKey = moduleKey, ok = false, reason = "standard display binding is not registered" }
        end
    end
    return result
end

function EXUI:AssertRegisteredDisplayModules(expectedKeys, options)
    local result = self:ValidateRegisteredDisplayModules(expectedKeys, options)
    local failures = {}
    for _, entry in ipairs(result) do
        if not entry.ok then failures[#failures + 1] = entry.moduleKey .. ": " .. tostring(entry.reason) end
    end
    if #failures > 0 then error("standard display contract audit failed:\n" .. table.concat(failures, "\n"), 2) end
    return result
end

local function CopyCallbacks(callbacks)
    local copy = {}
    for key, value in pairs(type(callbacks) == "table" and callbacks or {}) do
        copy[key] = value
    end
    copy.contentCenter = true
    return copy
end

local function RequireDock(dock, apiName)
    if not dock or type(dock.SetPoint) ~= "function" then
        error(apiName .. " requires a PreviewDock Frame", 3)
    end
end

local function RequireEntry(entry, index, kind)
    if type(entry) ~= "table" then
        error(kind .. " panel preview entry #" .. tostring(index) .. " must be a table", 3)
    end
    local itemID = entry.itemID or entry.id
    if type(itemID) ~= "string" or itemID == "" then
        error(kind .. " panel preview entry #" .. tostring(index) .. " requires itemID", 3)
    end
    if type(entry.presentation) ~= "table" then
        error(kind .. " panel preview entry " .. itemID .. " requires presentation", 3)
    end
    return itemID, entry.presentation
end

local function CopyTable(source)
    local copy = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        copy[key] = type(value) == "table" and CopyTable(value) or value
    end
    return copy
end

local function ReadDBPath(db, path, apiName)
    local value = db
    for part in string.gmatch(tostring(path or ""), "[^%.]+") do
        if type(value) ~= "table" then
            error(apiName .. " path is not a table: " .. tostring(path), 3)
        end
        value = value[part]
    end
    if type(value) ~= "number" then
        error(apiName .. " requires numeric DB path: " .. tostring(path), 3)
    end
    return value
end

local function WriteDBPath(db, path, value, apiName)
    local target = db
    local parts = {}
    for part in string.gmatch(tostring(path or ""), "[^%.]+") do parts[#parts + 1] = part end
    if #parts == 0 then error(apiName .. " requires a DB path", 3) end
    for index = 1, #parts - 1 do
        local part = parts[index]
        if type(target[part]) ~= "table" then
            error(apiName .. " DB path is not declared: " .. tostring(path), 3)
        end
        target = target[part]
    end
    target[parts[#parts]] = value
end

local function RequireExistingDBPath(db, path, apiName)
    local target = db
    local parts = {}
    for part in string.gmatch(tostring(path or ""), "[^%.]+") do parts[#parts + 1] = part end
    if #parts == 0 then error(apiName .. " requires a DB path", 3) end
    for _, part in ipairs(parts) do
        if type(target) ~= "table" or target[part] == nil then
            error(apiName .. " DB path is not declared: " .. tostring(path), 3)
        end
        target = target[part]
    end
    return target
end

local function ResolveBindingDB(source)
    local db = type(source) == "function" and source() or source
    if type(db) ~= "table" then error("BindStandardIconPreviewInteractions requires ModuleDB table", 3) end
    return db
end

local function RefreshActiveGridControls(moduleKey)
    local Grid = _G.ExwindGrid
    local container = EXUI.ActivePageFrame
    if not Grid or not container or type(Grid.RefreshContainerControlsFromDB) ~= "function" then
        error("standard icon interaction has no active Grid container for " .. moduleKey, 3)
    end
    Grid:RefreshContainerControlsFromDB(container)
end

-- Panel 与世界编辑模式共享这一份声明校验。模块不能因为 world adapter
-- 没有 Grid/右键需求，就绕过 guiKey、movable、X/Y 与注册 schema 的合同。
local function ValidateStandardInteractionSchema(binding, schema, apiName)
    if type(schema) ~= "table" then error(apiName .. " requires elements schema", 3) end
    local declaredGUIKeys = {}
    for elementID, declaration in pairs(schema) do
        if type(elementID) ~= "string" or elementID == "" or type(declaration) ~= "table" then
            error("standard interaction schema is malformed", 3)
        end
        if type(declaration.guiKey) ~= "string" or declaration.guiKey == "" then
            error("standard interaction " .. elementID .. " has no guiKey", 3)
        end
        declaredGUIKeys[declaration.guiKey] = declaration
        if declaration.movable == true then
            local position = declaration.position
            if type(position) ~= "table" or type(position.x) ~= "string" or type(position.y) ~= "string" then
                error("movable standard interaction " .. elementID .. " has no X/Y mapping", 3)
            end
            if position.toStorage ~= nil and type(position.toStorage) ~= "function" then
                error("standard interaction position.toStorage must be function: " .. elementID, 3)
            end
        end
    end
    return declaredGUIKeys
end

-- 个别旧显示的 SavedVariables X/Y 是相对业务基线，而 panel 命中层报告的是
-- 已计算的语义坐标。模块只能在 INTERACTION_SCHEMA 声明纯坐标换算；EXUI
-- 仍是唯一的校验、写 DB、刷新和 Grid 回读拥有者，禁止模块再写 onIntent。
local function ResolveStoredInteractionPosition(db, declaration, position, apiName)
    local mapping = declaration.position
    local stored = position
    if type(mapping.toStorage) == "function" then
        stored = mapping.toStorage(db, { x = position.x, y = position.y })
    end
    if type(stored) ~= "table" or type(stored.x) ~= "number" or type(stored.y) ~= "number" then
        error(apiName .. " position transform must return numeric { x, y }", 3)
    end
    return stored
end

local function ResolvePanelStyleFontSlot(family, guiKey, textRole)
    if family == "icon" then
        if guiKey == "font_text" or textRole == "label" then return "text" end
        if guiKey == "font_time" or textRole == "time" then return "time" end
        if guiKey == "font_stacks" or textRole == "stacks" then return "stacks" end
        return nil
    end
    if guiKey == "font_spell" or guiKey == "font_name"
        or textRole == "spellName" or textRole == "label" or textRole == "A" then
        return "spell"
    end
    if guiKey == "font_target" or textRole == "targetName" or textRole == "B" then return "target" end
    if guiKey == "font_timer" or guiKey == "font_time" or textRole == "time" or textRole == "C" then
        return "time"
    end
    return nil
end

-- Preset 只消费当前 Grid 已经解析完成的真实 DB 表与路径。它不猜 icon、
-- timerGroup 等业务命名，也不会把 timeline/material/text 误认成可套样式的显示。
local function ResolvePanelStylePresetBinding(panelPreview, moduleKey, declaredGUIKeys, state, container)
    local family, bodyType
    if panelPreview.kind == "Icon" then
        family, bodyType = "icon", "icongroup"
    elseif panelPreview.kind == "TimerBar" or panelPreview.kind == "StandardTimerBar" then
        family, bodyType = "timerbar", "timerbargroup"
    else
        return nil
    end

    local bodyWidget
    for _, widget in ipairs(state.instances or {}) do
        local element = widget and widget._exGridPixelElement
        if type(element) == "table" and string.lower(tostring(element.type or "")) == bodyType
            and type(widget._exCompositeDb) == "table" then
            if bodyWidget then return nil end
            bodyWidget = widget
        end
    end
    if not bodyWidget or bodyWidget._exCompositeDb.width == nil or bodyWidget._exCompositeDb.height == nil then
        return nil
    end
    local writeContext = bodyWidget._exCompositeOpts and bodyWidget._exCompositeOpts._exWriteContext
    if type(writeContext) ~= "table" or writeContext.moduleKey ~= moduleKey
        or type(writeContext.pathPrefix) ~= "string" then
        return nil
    end

    local fonts = {}
    for guiKey, declaration in pairs(declaredGUIKeys) do
        local slot = ResolvePanelStyleFontSlot(family, guiKey, declaration.textRole)
        local widget = slot and state.widgets[guiKey]
        local element = widget and widget._exGridPixelElement
        if slot and not fonts[slot] and type(element) == "table"
            and string.lower(tostring(element.type or "")) == "fontgroup"
            and type(widget._exCompositeDb) == "table" then
            fonts[slot] = widget._exCompositeDb
        end
    end

    local bodyPath = writeContext.pathPrefix
    return {
        family = family,
        moduleKey = moduleKey,
        container = container,
        gridState = state,
        bodyWidget = bodyWidget,
        bodyDB = bodyWidget._exCompositeDb,
        changedPath = bodyPath == "" and "width" or (bodyPath .. ".width"),
        fonts = fonts,
    }
end

-- 标准 Preview 的交互声明转换器。Icon、TimerBar、StandardTimerBar 使用 slots；
-- TextCollection 只允许一个直接 interaction。模块只提供语义槽、GUI key、可移动性
-- 和同一 ModuleDB 的 X/Y path；命中层、右键、写回、页面回读全部属于 EXUI。
function EXUI:BuildStandardPreviewInteraction(kind, dbSource, schema)
    local db = ResolveBindingDB(dbSource)
    if type(schema) ~= "table" then error("BuildStandardPreviewInteraction requires schema", 2) end
    local slots = {}
    for elementID, declaration in pairs(schema) do
        if type(elementID) ~= "string" or elementID == "" or type(declaration) ~= "table" then
            error("standard icon interaction schema has invalid element", 2)
        end
        local guiKey = declaration.guiKey
        if type(guiKey) ~= "string" or guiKey == "" then
            error("standard icon interaction " .. elementID .. " requires guiKey", 2)
        end
        local slot = {
            movable = declaration.movable == true,
            guiTarget = guiKey,
            tooltip = declaration.tooltip,
            textRole = declaration.textRole,
            extraTextID = declaration.extraTextID,
            positionMode = declaration.positionMode,
            relativeSlot = declaration.relativeSlot,
            semanticBounds = declaration.semanticBounds,
            hostID = declaration.hostID,
        }
        if slot.movable then
            local position = declaration.position
            if type(position) ~= "table" or type(position.x) ~= "string" or type(position.y) ~= "string" then
                error("movable standard icon interaction " .. elementID .. " requires position.x/y DB paths", 2)
            end
            local anchor = CopyTable(declaration.anchor)
            anchor.x = ReadDBPath(db, position.x, "standard icon interaction " .. elementID)
            anchor.y = ReadDBPath(db, position.y, "standard icon interaction " .. elementID)
            slot.anchor = anchor
        elseif type(declaration.anchor) == "table" then
            slot.anchor = CopyTable(declaration.anchor)
        end
        slots[elementID] = slot
    end
    if kind == "Text" then
        local count, onlyID, onlySlot = 0, nil, nil
        for elementID, slot in pairs(slots) do count = count + 1; onlyID, onlySlot = elementID, slot end
        if count ~= 1 then error("Text standard preview interaction requires exactly one element", 2) end
        onlySlot.elementID = onlyID
        return onlySlot
    end
    return { slots = slots }
end

-- 标准 Panel 的唯一意图合同。不得由模块自行注册 onIntent、写 DB、Focus 或刷新
-- Grid；这里严格验证 schema，再把各 Collection 的 intent 收口到同一处。
function EXUI:BindStandardPreviewInteractions(panelPreview, options)
    if type(panelPreview) ~= "table" or type(panelPreview.kind) ~= "string" or type(panelPreview.SetIntentHandler) ~= "function" then
        error("BindStandardPreviewInteractions requires panel preview", 2)
    end
    options = type(options) == "table" and options or {}
    local moduleKey = EXUI:RequireModuleKey(options.moduleKey, "BindStandardPreviewInteractions")
    local binding = options.binding or EXUI:GetStandardConfigBinding(moduleKey)
    if binding then
        if binding.moduleKey ~= moduleKey then error("standard preview binding moduleKey mismatch", 2) end
        options.db = binding.getConfig
    end
    local schema = options.elements
    local declaredGUIKeys = ValidateStandardInteractionSchema(binding, schema, "BindStandardPreviewInteractions")
    for _, guiKey in ipairs(type(options.requiredPositionGuiKeys) == "table" and options.requiredPositionGuiKeys or {}) do
        local declaration = declaredGUIKeys[guiKey]
        if not declaration or declaration.movable ~= true then
            error("GUI position group has no movable standard icon mapping: " .. tostring(guiKey), 2)
        end
    end
    local Grid, container = _G.ExwindGrid, EXUI.ActivePageFrame
    local state = Grid and container and Grid.ContainerStates and Grid.ContainerStates[container]
    if not state or type(state.widgets) ~= "table" then
        error("standard icon interaction cannot validate active Grid for " .. moduleKey, 2)
    end
    for guiKey in pairs(declaredGUIKeys) do
        if not state.widgets[guiKey] then
            error("standard icon interaction GUI key is not rendered: " .. guiKey, 2)
        end
    end

    -- Timeline owns its own static hitboxes.  It receives the same schema and
    -- exact formal config root as the generic handler below, so it never needs
    -- a BunBar-specific ReadDBPath/HandlePreviewIntent implementation.
    if type(panelPreview.SetInteractionSchema) == "function" then
        panelPreview:SetInteractionSchema(schema, ResolveBindingDB(options.db))
    end

    panelPreview:SetIntentHandler(function(intent)
        if type(intent) ~= "table" then error("standard icon preview received malformed intent", 2) end
        local declaration = schema[intent.elementID]
        if type(declaration) ~= "table" then
            error("standard icon preview undeclared elementID: " .. tostring(intent.elementID), 2)
        end
        if intent.type == "elementRightClicked" then
            local guiKey = declaration.guiKey
            if not EXUI:FocusCurrentModuleGridKey(moduleKey, guiKey) then
                error("standard icon preview GUI key is not rendered: " .. tostring(guiKey), 2)
            end
            return true
        end
        -- IconCollection 为不可拖动的已声明语义槽发出左键点击；这只是
        -- 命中层的消费信号，不能写 DB、刷新预览或触发任何模块业务。
        -- movable=true 的槽不应走此路径，仍按严格合同报错。
        if intent.type == "elementClicked" then
            if declaration.movable == false then return true end
            error("standard icon preview elementClicked requires movable=false: " .. tostring(intent.elementID), 2)
        end
        if intent.type == "elementMoved" then
            if declaration.movable ~= true then
                error("standard icon preview element is not movable: " .. tostring(intent.elementID), 2)
            end
            local position = intent.position
            if type(position) ~= "table" or type(position.x) ~= "number" or type(position.y) ~= "number" then
                error("standard icon preview received malformed position", 2)
            end
            local db = ResolveBindingDB(options.db)
            local stored = ResolveStoredInteractionPosition(db, declaration, position,
                "standard icon interaction " .. intent.elementID)
            WriteDBPath(db, declaration.position.x, stored.x, "standard icon interaction " .. intent.elementID)
            WriteDBPath(db, declaration.position.y, stored.y, "standard icon interaction " .. intent.elementID)
            -- 一次拖动是一个提交事务；记录其中一个真实 leaf path 即可。path
            -- 不参与字段路由，不能为同一笔 x/y 写入重复全量重套。
            EXUI:NotifyModuleValueChanged(moduleKey, declaration.position.x, "committed")
            RefreshActiveGridControls(moduleKey)
            return true
        end
        error("standard icon preview unsupported intent: " .. tostring(intent.type), 2)
    end)
    if options.resize ~= nil then
        if type(panelPreview.BindResize) ~= "function" then
            error("standard panel preview does not support resize", 2)
        end
        local resize = CopyTable(options.resize)
        resize.binding = binding
        panelPreview:BindResize(resize)
    end
    if type(panelPreview.BindStylePresets) == "function" then
        panelPreview:BindStylePresets(ResolvePanelStylePresetBinding(
            panelPreview, moduleKey, declaredGUIKeys, state, container))
    end
    return panelPreview
end

-- 世界编辑模式的唯一 elementMoved adapter。它和 panel 完全复用同一个
-- INTERACTION_SCHEMA/注册 binding，却不引入 panel、Grid、右键或预览会话。
-- BuildPreview/ApplyLayoutIntent 仍是 EditMode 的既有入口；模块只交出本函数
-- 返回的 handler，不能再私写 DB 路径遍历或 RefreshVisuals。
function EXUI:BuildStandardWorldLayoutIntent(options)
    options = type(options) == "table" and options or {}
    local moduleKey = EXUI:RequireModuleKey(options.moduleKey, "BuildStandardWorldLayoutIntent")
    local binding = options.binding or EXUI:GetStandardConfigBinding(moduleKey)
    if type(binding) ~= "table" or binding.moduleKey ~= moduleKey then
        error("BuildStandardWorldLayoutIntent requires registered standard binding", 2)
    end

    local getConfig = options.getConfig or binding.getConfig
    if type(getConfig) ~= "function" then error("BuildStandardWorldLayoutIntent requires getConfig", 2) end
    local schema = options.elements
    ValidateStandardInteractionSchema(binding, schema, "BuildStandardWorldLayoutIntent")

    -- 不是“能写某个看起来一样的表”即可：world 与标准 binding 必须消费
    -- 同一 ModuleDB root，避免出现 EditMode 写到第二份配置的隐性兼容链。
    local function RequireSameConfigRoot()
        local db = ResolveBindingDB(getConfig)
        if db ~= ResolveBindingDB(binding.getConfig) then
            error("standard world interaction does not use registered config root: " .. moduleKey, 3)
        end
        return db
    end
    local initialDB = RequireSameConfigRoot()
    for elementID, declaration in pairs(schema) do
        if declaration.movable == true then
            ReadDBPath(initialDB, declaration.position.x, "standard world interaction " .. elementID)
            ReadDBPath(initialDB, declaration.position.y, "standard world interaction " .. elementID)
        end
    end

    return function(intent)
        if type(intent) ~= "table" or intent.type ~= "elementMoved" then
            error("standard world interaction received unsupported intent", 2)
        end
        local declaration = schema[intent.elementID]
        if type(declaration) ~= "table" then
            error("standard world interaction undeclared elementID: " .. tostring(intent.elementID), 2)
        end
        if declaration.movable ~= true then
            error("standard world interaction element is not movable: " .. tostring(intent.elementID), 2)
        end
        local position = intent.position
        if type(position) ~= "table" or type(position.x) ~= "number" or type(position.y) ~= "number" then
            error("standard world interaction received malformed position", 2)
        end
        local db = RequireSameConfigRoot()
        local stored = ResolveStoredInteractionPosition(db, declaration, position,
            "standard world interaction " .. intent.elementID)
        WriteDBPath(db, declaration.position.x, stored.x, "standard world interaction " .. intent.elementID)
        WriteDBPath(db, declaration.position.y, stored.y, "standard world interaction " .. intent.elementID)
        EXUI:NotifyModuleValueChanged(moduleKey, declaration.position.x, "committed")
        return true
    end
end

-- 兼容本轮首个 Icon 调用点的清晰别名；新模块一律使用上面的通用入口。
function EXUI:BuildStandardIconInteractionSlots(dbSource, schema)
    return self:BuildStandardPreviewInteraction("Icon", dbSource, schema)
end

function EXUI:BindStandardIconPreviewInteractions(panelPreview, options)
    if type(panelPreview) ~= "table" or panelPreview.kind ~= "Icon" then
        error("BindStandardIconPreviewInteractions requires Icon panel preview", 2)
    end
    return self:BindStandardPreviewInteractions(panelPreview, options)
end

local function ClampPanelResizeValue(value, minimum, maximum)
    value = math.floor((tonumber(value) or minimum) + 0.5)
    return math.max(minimum, math.min(maximum, value))
end

local function ShowPanelResizeTooltip(handle, width, height)
    local tooltip = _G.GameTooltip
    if not tooltip then return end
    tooltip:SetOwner(handle, "ANCHOR_RIGHT")
    tooltip:ClearLines()
    tooltip:SetText(L["拖动调整大小"])
    tooltip:AddLine(string.format(L["宽度：%d   高度：%d"], width, height), 1, 1, 1)
    tooltip:Show()
end

local function HidePanelResizeTooltip(handle)
    if _G.GameTooltip and _G.GameTooltip:GetOwner() == handle then _G.GameTooltip:Hide() end
end

local function RefreshPanelResizeControls(moduleKey)
    local Grid, container = _G.ExwindGrid, EXUI.ActivePageFrame
    local state = Grid and container and Grid.ContainerStates and Grid.ContainerStates[container]
    if EXUI.CurrentModule ~= moduleKey or not state or type(state.widgets) ~= "table"
        or type(Grid.RefreshContainerControlsFromDB) ~= "function" then return false end
    Grid:RefreshContainerControlsFromDB(container)
    return true
end

local function CreatePanelResizeTexture(handle, r, g, b, a)
    local texture = handle:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(handle)
    texture:SetColorTexture(r, g, b, a)
    return texture
end

local function AcquirePanelResizeHandle(dock)
    local handle = dock.__ExwindPanelResizeHandle
    if handle then return handle end
    handle = CreateFrame("Button", nil, dock)
    handle:SetSize(14, 14)
    handle:RegisterForClicks("LeftButtonUp")
    handle:SetNormalTexture(CreatePanelResizeTexture(handle, 1.00, 0.82, 0.12, 1.00))
    handle:SetHighlightTexture(CreatePanelResizeTexture(handle, 1.00, 1.00, 1.00, 1.00))
    handle:SetPushedTexture(CreatePanelResizeTexture(handle, 1.00, 0.48, 0.08, 1.00))
    dock.__ExwindPanelResizeHandle = handle
    return handle
end

-- 一次性外观预设。图标/计时条本体坐标、iconID、挂接目标及模块业务字段
-- 从源表中不存在；文字控件则完整套用外观与 X/Y，LSM font 单独由确认勾选控制。
local ICON_STYLE_BODY = {
    alpha = 1, blendMode = "BLEND",
    borderColorA = 1, borderColorB = 0, borderColorG = 0, borderColorR = 0,
    borderPadding = 0.6, borderSize = 0, borderTexture = "EX_Default",
    colorA = 1, colorB = 1, colorG = 1, colorR = 1,
    cooldown = {
        edgeAlpha = 0.75, showBling = false, showEdge = true,
        showSwipe = true, swipeAlpha = 0.55000001192093,
    },
    cropBottom = 0.92, cropLeft = 0.08, cropRight = 0.92, cropTop = 0.08,
    desaturated = false, enableCrop = true, height = 45, reverse = false,
    rotation = 0, showBorder = true, showCooldown = true, showIcon = true, width = 45,
}
local ICON_STYLE_TIME_FONT = {
    a = 1, autoWidth = false, b = 0, enabled = true, fixedWidth = 200, font = "默认", g = 0.82,
    gradientEnabled = false, gradientLength = 0, gradientStart = 0,
    justifyH = "CENTER", justifyV = "MIDDLE", maxWidth = 0, outline = "OUTLINE",
    r = 1, rotation = 0, shadow = false, shadowColorA = 1, shadowColorB = 0,
    shadowColorG = 0, shadowColorR = 0, shadowX = 1, shadowY = -1, size = 20, x = 0, y = 0,
}
local ICON_STYLE_TEXT_FONT = {
    a = 1, autoWidth = false, b = 1, font = "默认", g = 0.91372555494308,
    justifyH = "CENTER", justifyV = "MIDDLE", outline = "OUTLINE",
    r = 0.24705883860588, shadow = true, shadowX = 1, shadowY = -1,
    size = 18, x = 0, y = -6,
}
local ICON_STYLE_STACKS_A = {
    a = 1, autoWidth = false, b = 1, enabled = true, fixedWidth = 200, font = "默认", g = 1,
    gradientEnabled = false, gradientLength = 0, gradientStart = 0,
    justifyH = "RIGHT", justifyV = "MIDDLE", maxWidth = 0, outline = "OUTLINE",
    r = 1, rotation = 0, shadow = false, shadowColorA = 1, shadowColorB = 0,
    shadowColorG = 0, shadowColorR = 0, shadowX = 1, shadowY = -1, size = 15,
    x = 0.80002391012601, y = -0.80021978225236,
}
local ICON_STYLE_STACKS_B = CopyTable(ICON_STYLE_STACKS_A)
ICON_STYLE_STACKS_B.justifyH = "CENTER"
ICON_STYLE_STACKS_B.size = 22
ICON_STYLE_STACKS_B.x = 79.170220937111
ICON_STYLE_STACKS_B.y = -15.994008844103

local TIMERBAR_STYLE_BODY_A = {
    barBgColorA = 0.5, barBgColorB = 0, barBgColorG = 0, barBgColorR = 0,
    barColorA = 1, barColorB = 1, barColorG = 0.9098, barColorR = 0.2902,
    borderColorA = 1, borderColorB = 0, borderColorG = 0, borderColorR = 0,
    borderPadding = 0.6, borderSize = 0.90000003576279, borderTexture = "EX_Default",
    height = 30,
    iconBorderColorA = 1, iconBorderColorB = 0, iconBorderColorG = 0, iconBorderColorR = 0,
    iconBorderPadding = 0.6, iconBorderSize = 0, iconBorderTexture = "EX_Default",
    iconHeight = 30, iconOffsetX = -2, iconOffsetY = 0, iconSide = "LEFT", iconWidth = 30,
    showBorder = true, showIcon = true,
    showIconBorder = true, texture = "EX_WhiteTexture", width = 220,
}
local TIMERBAR_STYLE_BODY_B = CopyTable(TIMERBAR_STYLE_BODY_A)
TIMERBAR_STYLE_BODY_B.height = 15
TIMERBAR_STYLE_BODY_B.iconHeight = 25
TIMERBAR_STYLE_BODY_B.iconOffsetX = -3
TIMERBAR_STYLE_BODY_B.iconOffsetY = 5
TIMERBAR_STYLE_BODY_B.iconWidth = 25

local TIMERBAR_STYLE_SPELL_FONT = {
    a = 1, autoWidth = false, b = 1, enabled = true, fixedWidth = 200, font = "默认", g = 1,
    gradientEnabled = false, gradientLength = 0, gradientStart = 0,
    justifyH = "LEFT", justifyV = "MIDDLE", maxWidth = 0, outline = "OUTLINE",
    r = 1, rotation = 0, shadow = false, shadowColorA = 1, shadowColorB = 0,
    shadowColorG = 0, shadowColorR = 0, shadowX = 1, shadowY = -1, size = 18, x = -7, y = 0,
}
local TIMERBAR_STYLE_TARGET_FONT = CopyTable(TIMERBAR_STYLE_SPELL_FONT)
TIMERBAR_STYLE_TARGET_FONT.b = 0.4039
TIMERBAR_STYLE_TARGET_FONT.g = 0.8
TIMERBAR_STYLE_TARGET_FONT.justifyH = "CENTER"
TIMERBAR_STYLE_TARGET_FONT.r = 0.2706
TIMERBAR_STYLE_TARGET_FONT.x = 46.400692305465
local TIMERBAR_STYLE_TIME_FONT = CopyTable(TIMERBAR_STYLE_SPELL_FONT)
TIMERBAR_STYLE_TIME_FONT.justifyH = "RIGHT"
TIMERBAR_STYLE_TIME_FONT.x = 8

local TIMERBAR_STYLE_SPELL_FONT_B = CopyTable(TIMERBAR_STYLE_SPELL_FONT)
TIMERBAR_STYLE_SPELL_FONT_B.x = -9
TIMERBAR_STYLE_SPELL_FONT_B.y = 7
local TIMERBAR_STYLE_TARGET_FONT_B = CopyTable(TIMERBAR_STYLE_TARGET_FONT)
TIMERBAR_STYLE_TARGET_FONT_B.x = 37.603991677111
TIMERBAR_STYLE_TARGET_FONT_B.y = 7
local TIMERBAR_STYLE_TIME_FONT_B = CopyTable(TIMERBAR_STYLE_TIME_FONT)
TIMERBAR_STYLE_TIME_FONT_B.x = 7
TIMERBAR_STYLE_TIME_FONT_B.y = 7

local PANEL_STYLE_PRESETS = {
    icon = {
        A = { body = ICON_STYLE_BODY, fonts = {
            text = ICON_STYLE_TEXT_FONT, time = ICON_STYLE_TIME_FONT, stacks = ICON_STYLE_STACKS_A,
        } },
        B = { body = ICON_STYLE_BODY, fonts = {
            text = ICON_STYLE_TEXT_FONT, time = ICON_STYLE_TIME_FONT, stacks = ICON_STYLE_STACKS_B,
        } },
    },
    timerbar = {
        A = { body = TIMERBAR_STYLE_BODY_A, fonts = {
            spell = TIMERBAR_STYLE_SPELL_FONT, target = TIMERBAR_STYLE_TARGET_FONT, time = TIMERBAR_STYLE_TIME_FONT,
        } },
        B = { body = TIMERBAR_STYLE_BODY_B, fonts = {
            spell = TIMERBAR_STYLE_SPELL_FONT_B, target = TIMERBAR_STYLE_TARGET_FONT_B, time = TIMERBAR_STYLE_TIME_FONT_B,
        } },
    },
}
local CUSTOM_STYLE_PRESET_PREFIX = "custom:"
local MAX_CUSTOM_STYLE_PRESETS = 3
local LSM_FONT_PRESET_EXCLUSION = { font = true }
-- 计时条的推进规则属于模块业务语义。A/B 只覆盖外观，不能改变读条的方向、
-- 填充/消退算法；`fillMode` 同时拦截历史自定义样式里的退役字段。
local TIMERBAR_PRESET_BODY_EXCLUSION = {
    x = true,
    y = true,
    fillDirection = true,
    progressMode = true,
    fillMode = true,
}

-- 玩家样式属于 Core 级共享资源，而不是某个业务插件的模块配置。这样由
-- Tools 保存的图标样式可以直接用于 EXBoss 的图标，计时条同理；两种家族
-- 仍各自保存，避免把不兼容的 body/font schema 混用。
local function GetCustomStylePresetStore(family)
    _G.EXCORE12S2 = type(_G.EXCORE12S2) == "table" and _G.EXCORE12S2 or {}
    local root = _G.EXCORE12S2.PanelStylePresets
    if type(root) ~= "table" then
        root = { version = 1, icon = {}, timerbar = {} }
        _G.EXCORE12S2.PanelStylePresets = root
    end
    root.version = 1
    root.icon = type(root.icon) == "table" and root.icon or {}
    root.timerbar = type(root.timerbar) == "table" and root.timerbar or {}
    local normalized, seen = {}, {}
    for _, preset in ipairs(root[family]) do
        local id = type(preset) == "table" and math.floor(tonumber(preset.id) or 0) or 0
        if id >= 1 and id <= MAX_CUSTOM_STYLE_PRESETS and not seen[id]
            and type(preset.body) == "table" and type(preset.fonts) == "table" then
            preset.id = id
            preset.name = L["自定义样式"] .. tostring(id)
            normalized[#normalized + 1] = preset
            seen[id] = true
        end
    end
    table.sort(normalized, function(a, b) return a.id < b.id end)
    root[family] = normalized
    return root, normalized
end

local function ParseCustomStylePresetID(slot)
    if type(slot) ~= "string" or slot:sub(1, #CUSTOM_STYLE_PRESET_PREFIX) ~= CUSTOM_STYLE_PRESET_PREFIX then
        return nil
    end
    local id = tonumber(slot:sub(#CUSTOM_STYLE_PRESET_PREFIX + 1))
    id = id and math.floor(id) or nil
    return id and id >= 1 and id <= MAX_CUSTOM_STYLE_PRESETS and id or nil
end

local function GetPanelStylePreset(family, slot)
    local builtIn = PANEL_STYLE_PRESETS[family] and PANEL_STYLE_PRESETS[family][slot]
    if builtIn then return builtIn, false end
    local id = ParseCustomStylePresetID(slot)
    if not id then return nil, false end
    local _, presets = GetCustomStylePresetStore(family)
    for _, preset in ipairs(presets) do
        if type(preset) == "table" and preset.id == id then return preset, true end
    end
    return nil, false
end

local function CopyDeclaredPresetFields(source, schema)
    if type(source) ~= "table" or type(schema) ~= "table" then return {} end
    local result = {}
    for key, schemaValue in pairs(schema) do
        local value = source[key]
        if value ~= nil then
            if type(schemaValue) == "table" and type(value) == "table" then
                result[key] = CopyDeclaredPresetFields(value, schemaValue)
            elseif type(schemaValue) ~= "table" and type(value) ~= "table" then
                result[key] = value
            end
        end
    end
    return result
end

local function ApplyExistingPresetFields(target, preset, excludedKeys)
    if type(target) ~= "table" or type(preset) ~= "table" then return end
    for key, value in pairs(preset) do
        local current = target[key]
        if current ~= nil and not (excludedKeys and excludedKeys[key]) then
            if type(value) == "table" and type(current) == "table" then
                ApplyExistingPresetFields(current, value, excludedKeys)
            elseif type(value) ~= "table" and type(current) ~= "table" then
                target[key] = value
            end
        end
    end
end

local function CreatePanelPresetButton(parent, width, textValue)
    return EXUI:CreateButton(parent, width, 24, textValue)
end

local function AcquirePanelPresetSidebarTexture(button, key, r, g, b, a)
    button.__ExwindPanelPresetSidebarTextures = button.__ExwindPanelPresetSidebarTextures or {}
    local textures = button.__ExwindPanelPresetSidebarTextures
    local texture = textures[key]
    if not texture then
        texture = EXUI:CreateVisualTexture(button, _G.EXBASEFRAME)
        texture:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        textures[key] = texture
    end
    texture:SetColorTexture(r, g, b, a)
    return texture
end

local function SetPanelPresetButtonPresentation(button, sidebar, role)
    if not button then return end
    local fontString = button.GetFontString and button:GetFontString() or nil
    if sidebar then
        local normal = AcquirePanelPresetSidebarTexture(button, "normal", 0.055, 0.086, 0.122, 1)
        local pushed = AcquirePanelPresetSidebarTexture(button, "pushed", 0.102, 0.153, 0.204, 1)
        local disabled = AcquirePanelPresetSidebarTexture(button, "disabled", 0.039, 0.063, 0.090, 0.75)
        local highlight = AcquirePanelPresetSidebarTexture(button, "highlight", 0.306, 0.835, 0.914, 0.18)
        button:SetNormalTexture(normal)
        button:SetPushedTexture(pushed)
        button:SetDisabledTexture(disabled)
        button:SetHighlightTexture(highlight, "ADD")
        if not button.__ExwindPanelPresetSidebarBorder then
            local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
            border:SetAllPoints()
            border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            border:EnableMouse(false)
            button.__ExwindPanelPresetSidebarBorder = border
        end
        local border = button.__ExwindPanelPresetSidebarBorder
        border:SetBackdropBorderColor(0.141, 0.216, 0.278, 1)
        border:Show()
        if fontString then
            if role == "delete" then
                fontString:SetTextColor(0.929, 0.349, 0.392, 1)
            elseif role == "add" then
                fontString:SetTextColor(0.306, 0.835, 0.914, 1)
            else
                fontString:SetTextColor(0.906, 0.941, 0.969, 1)
            end
        end
    else
        if button.__ExwindPanelPresetSidebarBorder then
            button.__ExwindPanelPresetSidebarBorder:Hide()
        end
        if button.SetNormalAtlas then button:SetNormalAtlas("common-button-tertiary-normal") end
        if button.SetPushedAtlas then button:SetPushedAtlas("common-button-tertiary-pressed") end
        if button.SetDisabledAtlas then button:SetDisabledAtlas("common-button-tertiary-disabled") end
        if button.SetHighlightAtlas then button:SetHighlightAtlas("common-button-tertiary-normal", "ADD") end
        if fontString then fontString:SetTextColor(1, 0.82, 0, 1) end
    end
end

local ReleasePanelPresetThumbnail

local function CreatePanelPresetThumbnail(parent, width, height)
    local view = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    view:SetSize(width, height)
    view:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    view:SetBackdropColor(0.20, 0.23, 0.29, 1)
    view:SetBackdropBorderColor(0.75, 0.82, 0.94, 0.70)
    if type(view.SetClipsChildren) == "function" then view:SetClipsChildren(true) end
    local host = CreateFrame("Frame", nil, view)
    host:SetPoint("CENTER", view, "CENTER", 0, 0)
    host:SetSize(1, 1)
    view.renderHost = host
    view:SetScript("OnHide", function(frame)
        ReleasePanelPresetThumbnail(frame)
    end)
    return view
end

ReleasePanelPresetThumbnail = function(view)
    if not view then return end
    if view.collection then view.collection:Release() end
    view.collection = nil
    view.family = nil
    view.moduleKey = nil
    view.renderHost:SetScale(1)
    view.renderHost:ClearAllPoints()
    view.renderHost:SetPoint("CENTER", view, "CENTER", 0, 0)
    view.renderHost:SetSize(1, 1)
end

local function BuildPanelPresetFontStyle(presetStyle, currentStyle, includeLSMFont)
    if type(presetStyle) ~= "table" or type(currentStyle) ~= "table" then return nil end
    local style = CopyTable(presetStyle)
    if includeLSMFont ~= true and type(currentStyle.font) == "string" then style.font = currentStyle.font end
    return style
end

local function ExpandPanelPresetBounds(bounds, style, content)
    if type(style) ~= "table" then return end
    local size = math.max(8, tonumber(style.size) or 14)
    local width = math.max(size * 1.5, size * math.max(1, #tostring(content or "")) * 0.58)
    local height = size * 1.35
    local x, y = tonumber(style.x) or 0, tonumber(style.y) or 0
    bounds.left, bounds.right = math.min(bounds.left, x - width * .5), math.max(bounds.right, x + width * .5)
    bounds.bottom, bounds.top = math.min(bounds.bottom, y - height * .5), math.max(bounds.top, y + height * .5)
end

local function ScalePanelPresetThumbnail(view, bounds, bodyWidth, bodyHeight)
    local width = math.max(1, bounds.right - bounds.left)
    local height = math.max(1, bounds.top - bounds.bottom)
    local scale = math.min((view:GetWidth() - 24) / width, (view:GetHeight() - 20) / height, 2)
    local centerX = (bounds.left + bounds.right) * .5
    local centerY = (bounds.bottom + bounds.top) * .5
    view.renderHost:ClearAllPoints()
    view.renderHost:SetPoint("CENTER", view, "CENTER", -centerX, -centerY)
    view.renderHost:SetScale(math.max(0.1, scale))
    view.renderHost:SetSize(math.max(1, bodyWidth), math.max(1, bodyHeight))
end

local function GetPanelPresetCollectionBounds(collection, fallback)
    local bounds = collection and type(collection.GetWorldBounds) == "function" and collection:GetWorldBounds() or nil
    if type(bounds) == "table" and tonumber(bounds.left) and tonumber(bounds.right)
        and tonumber(bounds.bottom) and tonumber(bounds.top) then
        return bounds
    end
    return fallback
end

local function RenderIconPanelPresetThumbnail(view, moduleKey, preset, currentFonts, includeLSMFont)
    local body = CopyTable(preset.body)
    local width, height = math.max(1, tonumber(body.width) or 45), math.max(1, tonumber(body.height) or 45)
    local labelStyle = BuildPanelPresetFontStyle(preset.fonts.text, currentFonts.text, includeLSMFont)
    local timeStyle = BuildPanelPresetFontStyle(preset.fonts.time, currentFonts.time, includeLSMFont)
    local stacksStyle = BuildPanelPresetFontStyle(preset.fonts.stacks, currentFonts.stacks, includeLSMFont)
    local bounds = { left = -width * .5, right = width * .5, bottom = -height * .5, top = height * .5 }
    ExpandPanelPresetBounds(bounds, labelStyle, "888K")
    ExpandPanelPresetBounds(bounds, timeStyle, "8.2")
    ExpandPanelPresetBounds(bounds, stacksStyle, "3")

    local collection = EXUI:CreateIconCollection(view.renderHost, "panel", moduleKey, { contentCenter = true })
    local item = collection:AcquireItem("panel-style-preset")
    collection:ApplyItem(item, {
        style = { icon = body, text = { label = labelStyle or {}, countdown = timeStyle or {}, stacks = stacksStyle or {} } },
        icon = { value = 135834 },
        label = labelStyle and "888K" or "",
        stacks = stacksStyle and "3" or nil,
        cooldown = timeStyle and { static = true, remaining = 8.2, duration = 30 } or nil,
        countdownTextVisible = timeStyle ~= nil,
        bodySize = { width = width, height = height },
        declaredBounds = bounds,
    })
    collection:SetItems({ item }, { mode = "FLOW", direction = "RIGHT", spacing = 0, maxVisible = 1 })
    view.collection = collection
    ScalePanelPresetThumbnail(view, GetPanelPresetCollectionBounds(collection, bounds), width, height)
end

local function GetPanelPresetSourcePresentation(sourceCollection)
    local item = sourceCollection and sourceCollection.currentItems and sourceCollection.currentItems[1]
    return type(item) == "table" and type(item.presentation) == "table" and item.presentation or nil
end

local function RenderTimerBarPanelPresetThumbnail(view, moduleKey, preset, currentFonts, includeLSMFont,
    sourceCollection, currentBody)
    local standard = ExwindTools.StandardTimerBar
    if type(standard) ~= "table" or type(standard.NormalizeSchema) ~= "function" then
        error("panel style preset requires StandardTimerBar", 2)
    end
    local sourcePresentation = GetPanelPresetSourcePresentation(sourceCollection)
    local schema = sourcePresentation and sourcePresentation.schema or sourceCollection and sourceCollection.standardSchema
    schema = standard.NormalizeSchema(schema or {
        timerBarKey = "timerGroup", layoutKey = "layout", showTextBKey = false, showTextCKey = false,
        textA = { key = "font_spell", role = "spellName" },
        textB = { key = "font_target", role = "targetName", optional = true },
        textC = { key = "font_timer", role = "time" },
    })
    -- 确认预览必须保留当前模块自己的推进语义；A/B 不覆盖这些字段。
    local body = CopyTable(currentBody)
    ApplyExistingPresetFields(body, preset.body, TIMERBAR_PRESET_BODY_EXCLUSION)
    body.x, body.y = 0, 0
    local spellStyle = BuildPanelPresetFontStyle(preset.fonts.spell, currentFonts.spell, includeLSMFont)
    local targetStyle = BuildPanelPresetFontStyle(preset.fonts.target, currentFonts.target, includeLSMFont)
    local timeStyle = BuildPanelPresetFontStyle(preset.fonts.time, currentFonts.time, includeLSMFont)
    local layout = { mode = "FLOW", direction = "RIGHT", spacing = 0, maxVisible = 1 }
    local db = { [schema.timerBarKey] = body, [schema.layoutKey] = layout }
    db[schema.textA.key] = spellStyle or { enabled = false }
    db[schema.textB.key] = targetStyle or { enabled = false }
    db[schema.textC.key] = timeStyle or { enabled = false }
    local width, height = math.max(1, tonumber(body.width) or 220), math.max(1, tonumber(body.height) or 24)
    local iconWidth = body.showIcon == false and 0 or math.max(0, tonumber(body.iconWidth) or height)
    local iconHeight = body.showIcon == false and 0 or math.max(0, tonumber(body.iconHeight) or height)
    local bounds = {
        left = -width * .5 - iconWidth - math.abs(tonumber(body.iconOffsetX) or 0),
        right = width * .5,
        bottom = math.min(-height * .5, (tonumber(body.iconOffsetY) or 0) - iconHeight * .5),
        top = math.max(height * .5, (tonumber(body.iconOffsetY) or 0) + iconHeight * .5),
    }
    ExpandPanelPresetBounds(bounds, spellStyle, L["技能名称"])
    ExpandPanelPresetBounds(bounds, targetStyle, L["目标"])
    ExpandPanelPresetBounds(bounds, timeStyle, "8.2")

    local collection = EXUI:CreateStandardTimerBarCollection(view.renderHost, "panel", moduleKey,
        { contentCenter = true, schema = schema })
    local item = collection:AcquireItem("panel-style-preset")
    local content = CopyTable(sourcePresentation and sourcePresentation.content or {
        textA = L["技能名称"], textB = L["目标"], textC = "8.2", progress = .68, maximum = 1,
    })
    content.icon = 135834
    collection:ApplyItem(item, {
        schema = schema, db = db, shown = true,
        content = content,
        -- 模块可能在正式 presentation 中声明业务级显示覆盖，例如酒池用
        -- root.textAlign 强制主文字居中。缩略图必须保留这些覆盖，不能只复用
        -- Widget 后重新发明一份通用 presentation。
        styleOverrides = sourcePresentation and sourcePresentation.styleOverrides or nil,
        textColors = sourcePresentation and sourcePresentation.textColors or nil,
        fillColor = sourcePresentation and sourcePresentation.fillColor or nil,
        fillFromBoolean = sourcePresentation and sourcePresentation.fillFromBoolean or nil,
        textShownFromBoolean = sourcePresentation and sourcePresentation.textShownFromBoolean
            or { A = spellStyle ~= nil, B = targetStyle ~= nil, C = timeStyle ~= nil },
        regionElements = {},
    })
    collection:SetItems({ item }, layout)
    view.collection = collection
    ScalePanelPresetThumbnail(view, GetPanelPresetCollectionBounds(collection, bounds), width, height)
end

local function ApplyPanelPresetThumbnail(view, family, slot, currentFonts, includeLSMFont, moduleKey,
    sourceCollection, presetOverride, currentBody)
    local preset = presetOverride or GetPanelStylePreset(family, slot)
    if not preset or type(moduleKey) ~= "string" or moduleKey == "" then
        ReleasePanelPresetThumbnail(view)
        view:Hide()
        return false
    end
    ReleasePanelPresetThumbnail(view)
    currentFonts = type(currentFonts) == "table" and currentFonts or {}
    if family == "icon" then
        RenderIconPanelPresetThumbnail(view, moduleKey, preset, currentFonts, includeLSMFont)
    elseif family == "timerbar" then
        RenderTimerBarPanelPresetThumbnail(view, moduleKey, preset, currentFonts, includeLSMFont,
            sourceCollection, currentBody)
    else
        return false
    end
    view.family, view.moduleKey = family, moduleKey
    view:Show()
    return true
end

local function PlacePanelStylePresetControls(dock, controls)
    if not dock or not controls or not controls.bar then return end
    local placement = dock.__ExwindPanelStylePresetPlacement
    local host = placement and placement.host
    if not host or type(host.SetPoint) ~= "function" then host = dock end
    local mode = placement and placement.mode == "sidebar" and "sidebar" or "inline"
    controls.host = host
    controls.layoutMode = mode
    controls.bar:SetParent(host)
    controls.bar:ClearAllPoints()
    if mode == "sidebar" then
        controls.bar:SetPoint("TOPLEFT", host, "TOPLEFT", 9, -40)
        controls.bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -9, -40)
    else
        controls.bar:SetPoint("TOPLEFT", dock, "TOPLEFT", 10, -8)
    end
end

local function AcquirePanelStylePresetControls(dock)
    local controls = dock.__ExwindPanelStylePresetControls
    if controls then
        PlacePanelStylePresetControls(dock, controls)
        return controls
    end

    controls = {}
    local bar = CreateFrame("Frame", nil, dock)
    bar:SetSize(1, 24)
    controls.bar = bar
    controls.buttons = {}
    controls.deleteButtons = {}
    controls.addButton = CreatePanelPresetButton(bar, 96, L["新增样式"])
    controls.addButton:SetScript("OnClick", function()
        local owner = controls.owner
        if owner then owner:OpenAddStylePresetConfirmation() end
    end)

    local confirm = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    confirm:SetSize(430, 260)
    confirm:SetPoint("CENTER", dock, "CENTER", 0, 0)
    confirm:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    confirm:SetBackdropColor(0.10, 0.12, 0.17, 1)
    confirm:SetBackdropBorderColor(0.35, 0.72, 1.00, 1)
    confirm:SetFrameStrata("TOOLTIP")
    confirm:SetToplevel(true)
    confirm:EnableMouse(true)
    -- 即使外层页面只 Hide、尚未来得及走 Release，也要把待确认交易本身
    -- 变成隐藏状态；再次显示同一 Dock 时不能复活旧模块的确认框。
    confirm:SetScript("OnHide", function(frame)
        local owner = controls.owner
        if not owner or not owner.stylePresetPending then return end
        owner.stylePresetPending = nil
        controls.fontCheck:SetChecked(false)
        for _, button in ipairs(controls.buttons) do button:Enable() end
        controls.addButton:Enable()
        for _, button in ipairs(controls.deleteButtons) do button:Enable() end
        if owner.RefreshStylePresetButtons then owner:RefreshStylePresetButtons() end
        if frame:IsShown() then frame:Hide() end
    end)
    confirm:Hide()
    controls.confirm = confirm

    local title = confirm:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", confirm, "TOP", 0, -14)
    controls.title = title
    local description = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    description:SetPoint("TOP", title, "BOTTOM", 0, -7)
    description:SetText(L["一次性覆盖当前外观；本体位置与业务设置不会改变。"])
    controls.description = description

    local confirmPreview = CreatePanelPresetThumbnail(confirm, 390, 120)
    confirmPreview:SetPoint("TOP", confirm, "TOP", 0, -54)
    controls.confirmPreview = confirmPreview

    local fontCheck = CreateFrame("CheckButton", nil, confirm, "UICheckButtonTemplate")
    fontCheck:SetSize(24, 24)
    fontCheck:SetPoint("BOTTOMLEFT", confirm, "BOTTOMLEFT", 112, 47)
    fontCheck:SetScript("OnClick", function()
        local owner = controls.owner
        if owner then owner:RefreshStylePresetConfirmationPreview() end
    end)
    controls.fontCheck = fontCheck
    local fontLabel = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fontLabel:SetPoint("LEFT", fontCheck, "RIGHT", 4, 0)
    fontLabel:SetText(L["同时覆盖字体（LSM）"])
    controls.fontLabel = fontLabel

    local applyButton = CreatePanelPresetButton(confirm, 92, L["确认应用"])
    applyButton:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -5, 10)
    applyButton:SetScript("OnClick", function()
        local owner = controls.owner
        if owner then owner:ConfirmStylePreset() end
    end)
    controls.applyButton = applyButton
    local cancelButton = CreatePanelPresetButton(confirm, 92, L["取消"])
    cancelButton:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 5, 10)
    cancelButton:SetScript("OnClick", function()
        local owner = controls.owner
        if owner then owner:CloseStylePresetConfirmation() end
    end)
    controls.cancelButton = cancelButton

    local tooltip = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    tooltip:SetSize(360, 154)
    tooltip:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    tooltip:SetBackdropColor(0.10, 0.12, 0.17, 1)
    tooltip:SetBackdropBorderColor(0.35, 0.72, 1.00, 1)
    tooltip:SetFrameStrata("TOOLTIP")
    tooltip:SetToplevel(true)
    tooltip:EnableMouse(false)
    tooltip:Hide()
    controls.tooltip = tooltip
    local tooltipTitle = tooltip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tooltipTitle:SetPoint("TOP", tooltip, "TOP", 0, -10)
    controls.tooltipTitle = tooltipTitle
    local tooltipPreview = CreatePanelPresetThumbnail(tooltip, 330, 110)
    tooltipPreview:SetPoint("BOTTOM", tooltip, "BOTTOM", 0, 8)
    controls.tooltipPreview = tooltipPreview

    dock.__ExwindPanelStylePresetControls = controls
    PlacePanelStylePresetControls(dock, controls)
    return controls
end

-- Panel style presets remain Core-owned, but a product editor may provide a
-- dedicated chrome host instead of letting the preset bar cover its preview.
-- The host changes presentation only; preset storage, confirmation, apply and
-- delete transactions stay in this file.
function EXUI:SetPanelStylePresetControlsHost(dock, host, mode)
    RequireDock(dock, "SetPanelStylePresetControlsHost")
    if host ~= nil and type(host.SetPoint) ~= "function" then
        error("SetPanelStylePresetControlsHost requires a Frame host", 2)
    end
    dock.__ExwindPanelStylePresetPlacement = host and {
        host = host,
        mode = mode == "sidebar" and "sidebar" or "inline",
    } or nil
    local controls = dock.__ExwindPanelStylePresetControls
    if not controls then return true end
    PlacePanelStylePresetControls(dock, controls)
    local owner = controls.owner
    if owner and type(owner.RefreshStylePresetButtons) == "function" then
        owner:RefreshStylePresetButtons()
    end
    return true
end

function EXUI:IsPanelStylePresetControlsActive(dock)
    local controls = dock and dock.__ExwindPanelStylePresetControls
    return controls ~= nil and controls.owner ~= nil
        and controls.bar ~= nil and controls.bar:IsShown()
end

local function CreatePanelPreview(kind, dock, moduleKey, callbacks, factory)
    RequireDock(dock, "Create" .. kind .. "PanelPreview")
    moduleKey = EXUI:RequireModuleKey(moduleKey, "Create" .. kind .. "PanelPreview")
    local collection = factory(dock, "panel", moduleKey, CopyCallbacks(callbacks))
    local session = {
        kind = kind,
        moduleKey = moduleKey,
        dock = dock,
        collection = collection,
        lastLayout = nil,
        hasItems = false,
        released = false,
    }

    function session:RefreshStylePresetButtons()
        local descriptor = self.stylePresetDescriptor
        local controls = self.stylePresetControls
        if not descriptor or not controls or controls.owner ~= self then return false end

        PlacePanelStylePresetControls(self.dock, controls)
        local sidebar = controls.layoutMode == "sidebar"
        local entries = {
            { slot = "A", label = L["样式 A"], custom = false, x = 0, y = 0, width = 82 },
            { slot = "B", label = L["样式 B"], custom = false, x = 88, y = 0, width = 82 },
        }
        local _, customPresets = GetCustomStylePresetStore(descriptor.family)
        for row, preset in ipairs(customPresets) do
            entries[#entries + 1] = {
                slot = CUSTOM_STYLE_PRESET_PREFIX .. tostring(preset.id),
                label = L["自定义样式"] .. tostring(preset.id),
                custom = true,
                x = 0,
                y = -row * 30,
                width = 118,
                customRow = row,
                customID = preset.id,
            }
        end

        for index, entry in ipairs(entries) do
            local button = controls.buttons[index]
            if not button then
                button = CreatePanelPresetButton(controls.bar, 82, entry.label)
                button:SetScript("OnClick", function(clicked)
                    local owner = controls.owner
                    if owner then
                        owner:HideStylePresetTooltip()
                        owner:OpenStylePresetConfirmation(clicked.presetSlot, "apply")
                    end
                end)
                button:SetScript("OnEnter", function(clicked)
                    local owner = controls.owner
                    if owner then owner:ShowStylePresetTooltip(clicked, clicked.presetSlot) end
                end)
                button:SetScript("OnLeave", function()
                    local owner = controls.owner
                    if owner then owner:HideStylePresetTooltip() end
                end)
                controls.buttons[index] = button
            end
            button.presetSlot = entry.slot
            button.isCustomStylePreset = entry.custom
            button:SetSize(entry.width, 24)
            button:SetText(entry.label)
            SetPanelPresetButtonPresentation(button, sidebar, "preset")
            button:ClearAllPoints()
            if sidebar then
                local y = -(index - 1) * 30
                button:SetPoint("TOPLEFT", controls.bar, "TOPLEFT", 0, y)
                button:SetPoint("TOPRIGHT", controls.bar, "TOPRIGHT", entry.custom and -30 or 0, y)
            else
                button:SetPoint("TOPLEFT", controls.bar, "TOPLEFT", entry.x, entry.y)
            end
            button:SetShown(true)

            if entry.custom then
                local deleteButton = controls.deleteButtons[entry.customRow]
                if not deleteButton then
                    deleteButton = CreatePanelPresetButton(controls.bar, 140, "")
                    deleteButton:SetScript("OnClick", function(clicked)
                        local owner = controls.owner
                        if owner then owner:OpenStylePresetConfirmation(clicked.presetSlot, "delete") end
                    end)
                    controls.deleteButtons[entry.customRow] = deleteButton
                end
                deleteButton.presetSlot = entry.slot
                deleteButton:SetText(sidebar and "×" or (L["删除自定义样式"] .. tostring(entry.customID)))
                SetPanelPresetButtonPresentation(deleteButton, sidebar, "delete")
                deleteButton:ClearAllPoints()
                if sidebar then
                    local y = -(index - 1) * 30
                    deleteButton:SetSize(24, 24)
                    deleteButton:SetPoint("TOPRIGHT", controls.bar, "TOPRIGHT", 0, y)
                else
                    deleteButton:SetSize(140, 24)
                    deleteButton:SetPoint("TOPLEFT", controls.bar, "TOPLEFT", 124, entry.y)
                end
                deleteButton:Show()
            end
        end
        for index = #entries + 1, #controls.buttons do
            controls.buttons[index]:Hide()
        end
        for index = #customPresets + 1, #controls.deleteButtons do
            controls.deleteButtons[index]:Hide()
        end

        controls.addButton:ClearAllPoints()
        SetPanelPresetButtonPresentation(controls.addButton, sidebar, "add")
        if sidebar then
            controls.addButton:SetText("+ " .. L["新增样式"])
            controls.addButton:SetPoint("TOPLEFT", controls.bar, "TOPLEFT", 0, -#entries * 30)
            controls.addButton:SetPoint("TOPRIGHT", controls.bar, "TOPRIGHT", 0, -#entries * 30)
            controls.bar:SetHeight((#entries + 1) * 30)
        else
            controls.addButton:SetText(L["新增样式"])
            controls.addButton:SetPoint("TOPLEFT", controls.bar, "TOPLEFT", 176, 0)
            controls.bar:SetSize(264, 24 + #customPresets * 30)
        end
        controls.addButton:Show()
        if #customPresets >= MAX_CUSTOM_STYLE_PRESETS then
            controls.addButton:Disable()
        else
            controls.addButton:Enable()
        end
        return true
    end

    function session:BuildCurrentCustomStylePreset(id)
        if not self:IsStylePresetSessionCurrent() then return false end
        local descriptor = self.stylePresetDescriptor
        local schema = PANEL_STYLE_PRESETS[descriptor.family] and PANEL_STYLE_PRESETS[descriptor.family].A
        if not schema then return false end
        local preset = {
            id = id,
            name = L["自定义样式"] .. tostring(id),
            body = CopyDeclaredPresetFields(descriptor.bodyDB, schema.body),
            fonts = {},
        }
        for fontSlot, fontSchema in pairs(schema.fonts or {}) do
            local current = descriptor.fonts[fontSlot]
            if type(current) == "table" then
                preset.fonts[fontSlot] = CopyDeclaredPresetFields(current, fontSchema)
            end
        end
        return preset
    end

    function session:AddCustomStylePreset(preset)
        if not self:IsStylePresetSessionCurrent() or type(preset) ~= "table" then return false end
        local descriptor = self.stylePresetDescriptor
        local _, presets = GetCustomStylePresetStore(descriptor.family)
        if #presets >= MAX_CUSTOM_STYLE_PRESETS then return false end
        local id = math.floor(tonumber(preset.id) or 0)
        if id < 1 or id > MAX_CUSTOM_STYLE_PRESETS then return false end
        for _, existing in ipairs(presets) do
            if existing.id == id then return false end
        end
        presets[#presets + 1] = preset
        self:RefreshStylePresetButtons()
        return true
    end

    function session:OpenAddStylePresetConfirmation()
        if not self:IsStylePresetSessionCurrent() then return false end
        local descriptor = self.stylePresetDescriptor
        local _, presets = GetCustomStylePresetStore(descriptor.family)
        if #presets >= MAX_CUSTOM_STYLE_PRESETS then return false end
        local occupied = {}
        for _, preset in ipairs(presets) do occupied[preset.id] = true end
        local id
        for candidate = 1, MAX_CUSTOM_STYLE_PRESETS do
            if not occupied[candidate] then id = candidate break end
        end
        if not id then return false end
        local preset = self:BuildCurrentCustomStylePreset(id)
        if not preset then return false end
        return self:OpenStylePresetConfirmation(CUSTOM_STYLE_PRESET_PREFIX .. tostring(id), "add", preset)
    end

    function session:DeleteCustomStylePreset(slot)
        local descriptor = self.stylePresetDescriptor
        local id = descriptor and ParseCustomStylePresetID(slot)
        if not id then return false end
        local _, presets = GetCustomStylePresetStore(descriptor.family)
        for index, preset in ipairs(presets) do
            if type(preset) == "table" and preset.id == id then
                table.remove(presets, index)
                self:RefreshStylePresetButtons()
                return true
            end
        end
        return false
    end

    function session:CloseStylePresetConfirmation()
        local controls = self.stylePresetControls
        self.stylePresetPending = nil
        if not controls or controls.owner ~= self then return end
        controls.confirm:Hide()
        controls.fontCheck:SetChecked(false)
        for _, button in ipairs(controls.buttons) do button:Enable() end
        controls.addButton:Enable()
        for _, button in ipairs(controls.deleteButtons) do button:Enable() end
        controls.fontCheck:Show()
        controls.fontLabel:Show()
        self:RefreshStylePresetButtons()
    end

    function session:HideStylePresetTooltip()
        local controls = self.stylePresetControls
        if controls and controls.owner == self then controls.tooltip:Hide() end
    end

    function session:IsStylePresetSessionCurrent()
        local descriptor = self.stylePresetDescriptor
        local controls = self.stylePresetControls
        local Grid = _G.ExwindGrid
        local familyMatches = descriptor and ((descriptor.family == "icon" and self.kind == "Icon")
            or (descriptor.family == "timerbar" and (self.kind == "TimerBar" or self.kind == "StandardTimerBar")))
        return self.released ~= true and familyMatches and controls and controls.owner == self
            and descriptor.moduleKey == self.moduleKey and EXUI.CurrentModule == self.moduleKey
            and EXUI.ActivePageFrame == descriptor.container and Grid and Grid.ContainerStates
            and Grid.ContainerStates[descriptor.container] == descriptor.gridState
            and descriptor.bodyWidget._exCompositeDb == descriptor.bodyDB
    end

    function session:ShowStylePresetTooltip(button, slot)
        local descriptor = self.stylePresetDescriptor
        local controls = self.stylePresetControls
        if not self:IsStylePresetSessionCurrent() then
            self:ReleaseStylePresets()
            return false
        end
        local preset = GetPanelStylePreset(descriptor.family, slot)
        if controls.confirm:IsShown() or not preset then return false end
        controls.tooltip:ClearAllPoints()
        controls.tooltip:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -5)
        controls.tooltipTitle:SetText(tostring(button:GetText() or slot) .. L[" 预览（点击选择）"])
        ApplyPanelPresetThumbnail(controls.tooltipPreview, descriptor.family, slot, descriptor.fonts, false,
            self.moduleKey, self.collection, nil, descriptor.bodyDB)
        controls.tooltip:Show()
        controls.tooltip:Raise()
        return true
    end

    function session:RefreshStylePresetConfirmationPreview()
        local descriptor = self.stylePresetDescriptor
        local pending = self.stylePresetPending
        local controls = self.stylePresetControls
        if not self:IsStylePresetSessionCurrent() or not pending then return false end
        return ApplyPanelPresetThumbnail(controls.confirmPreview, descriptor.family, pending.slot,
            descriptor.fonts, controls.fontCheck:GetChecked() == true, self.moduleKey, self.collection,
            pending.preset, descriptor.bodyDB)
    end

    function session:ReleaseStylePresets()
        self.stylePresetToken = {}
        self.stylePresetPending = nil
        self.stylePresetDescriptor = nil
        local controls = self.stylePresetControls
        self.stylePresetControls = nil
        if not controls or controls.owner ~= self then return end
        controls.owner = nil
        controls.confirm:Hide()
        controls.tooltip:Hide()
        controls.fontCheck:SetChecked(false)
        controls.bar:Hide()
        for _, button in ipairs(controls.buttons) do
            button:Enable()
            button:Hide()
        end
        controls.addButton:Hide()
        for _, button in ipairs(controls.deleteButtons) do button:Hide() end
    end

    function session:BindStylePresets(descriptor)
        if self.released then error(kind .. " panel preview is released", 2) end
        if descriptor == nil then
            self:ReleaseStylePresets()
            return self
        end
        if type(descriptor) ~= "table" or descriptor.moduleKey ~= self.moduleKey
            or not PANEL_STYLE_PRESETS[descriptor.family] then
            error(kind .. " panel preview received invalid style preset binding", 2)
        end
        local controls = AcquirePanelStylePresetControls(self.dock)
        if controls.owner and controls.owner ~= self then controls.owner:ReleaseStylePresets() end
        controls.owner = self
        self.stylePresetControls = controls
        self.stylePresetDescriptor = descriptor
        self.stylePresetToken = {}
        self.stylePresetPending = nil
        controls.bar:SetFrameLevel(self.dock:GetFrameLevel() + 100)
        controls.tooltip:SetFrameLevel(self.dock:GetFrameLevel() + 180)
        controls.confirm:SetFrameLevel(self.dock:GetFrameLevel() + 200)
        controls.fontCheck:SetChecked(false)
        controls.tooltip:Hide()
        controls.confirm:Hide()
        controls.bar:Show()
        controls.addButton:Enable()
        self:RefreshStylePresetButtons()
        return self
    end

    function session:OpenStylePresetConfirmation(slot, action, presetOverride)
        local descriptor = self.stylePresetDescriptor
        local controls = self.stylePresetControls
        if not self:IsStylePresetSessionCurrent() then
            self:ReleaseStylePresets()
            return false
        end
        local preset, isCustom = GetPanelStylePreset(descriptor.family, slot)
        if action ~= "delete" and action ~= "add" then action = "apply" end
        if action == "add" then
            preset = presetOverride
            isCustom = type(preset) == "table" and ParseCustomStylePresetID(slot) ~= nil
        end
        if not preset or ((action == "delete" or action == "add") and not isCustom) then return false end
        self.stylePresetPending = {
            slot = slot,
            action = action,
            preset = action == "add" and preset or nil,
            token = self.stylePresetToken,
            moduleKey = self.moduleKey,
            container = descriptor.container,
            gridState = descriptor.gridState,
        }
        local presetName = type(preset.name) == "string" and preset.name or (L["样式 "] .. slot)
        local actionTitle = action == "delete" and L["删除 "] or (action == "add" and L["新增 "] or L["应用 "])
        controls.title:SetText(actionTitle .. presetName .. "？")
        controls.description:SetText(action == "delete" and L["删除后无法恢复；内置样式 A/B 不会受到影响。"]
            or (action == "add" and L["保存当前外观为 Core 共享样式；本体位置不会保存。"]
            or L["一次性覆盖当前外观；本体位置与业务设置不会改变。"]))
        controls.applyButton:SetText(action == "delete" and L["确认删除"]
            or (action == "add" and L["确认新增"] or L["确认应用"]))
        controls.fontCheck:SetChecked(false)
        controls.fontCheck:SetShown(action == "apply")
        controls.fontLabel:SetShown(action == "apply")
        for _, button in ipairs(controls.buttons) do button:Disable() end
        controls.addButton:Disable()
        for _, button in ipairs(controls.deleteButtons) do button:Disable() end
        self:RefreshStylePresetConfirmationPreview()
        controls.confirm:Show()
        controls.confirm:Raise()
        return true
    end

    function session:IsStylePresetConfirmationCurrent()
        local pending = self.stylePresetPending
        local descriptor = self.stylePresetDescriptor
        local controls = self.stylePresetControls
        return self:IsStylePresetSessionCurrent() and type(pending) == "table" and type(descriptor) == "table"
            and pending.token == self.stylePresetToken
            and pending.moduleKey == self.moduleKey and pending.container == descriptor.container
            and pending.gridState == descriptor.gridState
    end

    function session:ApplyStylePreset(slot, includeLSMFont)
        local descriptor = self.stylePresetDescriptor
        local preset = descriptor and GetPanelStylePreset(descriptor.family, slot)
        if not preset then return false end
        local bodyExclusions = descriptor.family == "timerbar" and TIMERBAR_PRESET_BODY_EXCLUSION or nil
        ApplyExistingPresetFields(descriptor.bodyDB, preset.body, bodyExclusions)
        local fontExclusions = includeLSMFont == true and nil or LSM_FONT_PRESET_EXCLUSION
        for fontSlot, fontPreset in pairs(preset.fonts or {}) do
            local target = descriptor.fonts[fontSlot]
            if target then ApplyExistingPresetFields(target, fontPreset, fontExclusions) end
        end
        -- 整个预设是一笔提交：无论覆盖多少字段都只触发一次正式重绘，随后
        -- 当前 Grid 从同一份 DB 回读一次，绝不形成逐字段刷新风暴。
        EXUI:NotifyModuleValueChanged(self.moduleKey, descriptor.changedPath, "committed")
        RefreshActiveGridControls(self.moduleKey)
        return true
    end

    function session:ConfirmStylePreset()
        if not self:IsStylePresetConfirmationCurrent() then
            self:CloseStylePresetConfirmation()
            return false
        end
        local slot = self.stylePresetPending.slot
        local action = self.stylePresetPending.action
        local pendingPreset = self.stylePresetPending.preset
        local includeLSMFont = self.stylePresetControls.fontCheck:GetChecked() == true
        self:CloseStylePresetConfirmation()
        if action == "delete" then return self:DeleteCustomStylePreset(slot) end
        if action == "add" then return self:AddCustomStylePreset(pendingPreset) end
        return self:ApplyStylePreset(slot, includeLSMFont)
    end

    function session:PositionResizeHandle()
        local handle = self.resizeHandle
        if not handle or handle.__ExwindPanelResizeSession ~= self then return end
        handle:ClearAllPoints()
        handle:SetPoint("CENTER", self.collection.layout, "BOTTOMRIGHT", 2, -2)
        handle:SetFrameLevel(math.max(self.dock:GetFrameLevel(), self.collection.layout:GetFrameLevel()) + 100)
        handle:SetShown(self.hasItems == true)
    end

    function session:ReadResizeSize()
        local options = self.resizeOptions
        local db = ResolveBindingDB(options.binding.getConfig)
        return ReadDBPath(db, options.widthPath, "panel resize width"),
            ReadDBPath(db, options.heightPath, "panel resize height")
    end

    function session:WriteResizeSize(width, height, phase)
        local options = self.resizeOptions
        local db = ResolveBindingDB(options.binding.getConfig)
        WriteDBPath(db, options.widthPath, width, "panel resize width")
        WriteDBPath(db, options.heightPath, height, "panel resize height")
        -- TimerBar 拖动期只改变现有 Panel Item 的临时几何，不能逐帧重套原生
        -- 计时内容。松手仍走唯一 committed 通知，由正式 DB 样式接回 ownership。
        if phase == "changing" and (kind == "StandardTimerBar" or kind == "TimerBar") then
            if type(self.collection.ResizeCurrentItems) ~= "function"
                or not self.collection:ResizeCurrentItems(width, height) then
                error(kind .. " panel preview cannot resize current items", 2)
            end
        else
            EXUI:NotifyModuleValueChanged(self.moduleKey, options.widthPath, phase)
        end
    end

    function session:UpdateResize()
        local resizeState = self.resizeState
        if not resizeState then return end
        local cursorX, cursorY = GetCursorPosition()
        cursorX, cursorY = cursorX / resizeState.scale, cursorY / resizeState.scale
        local options = self.resizeOptions
        -- Panel sample 永远以 Dock CENTER 为原点；与暴雪固定对角的 StartSizing
        -- 不同，Body 尺寸每增加 2px，右/下边缘只移动 1px。多项集合在排列轴
        -- 上还会同时改变每个 Item，因此必须按本轮可见数量折算鼠标位移。
        local width = ClampPanelResizeValue(resizeState.startWidth
            + (cursorX - resizeState.cursorX) * 2 / resizeState.widthItemCount,
            options.minWidth, options.maxWidth)
        local height = ClampPanelResizeValue(resizeState.startHeight
            + (resizeState.cursorY - cursorY) * 2 / resizeState.heightItemCount,
            options.minHeight, options.maxHeight)
        resizeState.width, resizeState.height = width, height

        if width ~= resizeState.appliedWidth or height ~= resizeState.appliedHeight then
            resizeState.appliedWidth, resizeState.appliedHeight = width, height
            self:WriteResizeSize(width, height, "changing")
        end
        local handle = self.resizeHandle
        ShowPanelResizeTooltip(handle, width, height)
    end

    function session:FinishResize(commit)
        local resizeState = self.resizeState
        if not resizeState then return end
        self:UpdateResize()
        local width, height = resizeState.width, resizeState.height
        local handle = self.resizeHandle
        handle:SetScript("OnUpdate", nil)
        handle:SetButtonState("NORMAL", false)
        local highlight = handle:GetHighlightTexture()
        if highlight then highlight:Show() end
        self.resizeState = nil
        if commit ~= false then
            self:WriteResizeSize(width, height, "committed")
            RefreshPanelResizeControls(self.moduleKey)
        end
        self:PositionResizeHandle()
        if handle:IsMouseOver() then ShowPanelResizeTooltip(handle, width, height)
        else HidePanelResizeTooltip(handle) end
    end

    function session:StartResize(handle)
        if self.resizeState or not self.hasItems then return end
        local width, height = self:ReadResizeSize()
        local cursorX, cursorY = GetCursorPosition()
        local scale = handle:GetEffectiveScale()
        if type(scale) ~= "number" or scale <= 0 then return end
        local _, _, visibleCount = self.collection:GetBounds()
        visibleCount = math.max(1, math.floor(tonumber(visibleCount) or 1))
        local direction = self.collection.layout and self.collection.layout.direction
        local horizontal = direction == "RIGHT" or direction == "LEFT" or direction == "CENTER_HORIZONTAL"
        cursorX, cursorY = cursorX / scale, cursorY / scale
        self.resizeState = {
            cursorX = cursorX, cursorY = cursorY, scale = scale,
            widthItemCount = horizontal and visibleCount or 1,
            heightItemCount = horizontal and 1 or visibleCount,
            startWidth = width, startHeight = height, width = width, height = height,
            appliedWidth = width, appliedHeight = height,
        }
        handle:SetButtonState("PUSHED", true)
        local highlight = handle:GetHighlightTexture()
        if highlight then highlight:Hide() end
        ShowPanelResizeTooltip(handle, width, height)
        handle:SetScript("OnUpdate", function()
            if not IsMouseButtonDown("LeftButton") then self:FinishResize(true); return end
            self:UpdateResize()
        end)
    end

    function session:BindResize(options)
        if self.released then error(kind .. " panel preview is released", 2) end
        if kind ~= "Icon" and kind ~= "StandardTimerBar" and kind ~= "TimerBar" then
            error(kind .. " panel preview does not support resize", 2)
        end
        if type(options) ~= "table" or type(options.binding) ~= "table"
            or type(options.widthPath) ~= "string" or options.widthPath == ""
            or type(options.heightPath) ~= "string" or options.heightPath == "" then
            error(kind .. " panel resize requires binding and width/height paths", 2)
        end
        for _, key in ipairs({ "minWidth", "maxWidth", "minHeight", "maxHeight" }) do
            if type(options[key]) ~= "number" then error(kind .. " panel resize requires numeric " .. key, 2) end
        end
        if options.minWidth <= 0 or options.minHeight <= 0 or options.maxWidth < options.minWidth
            or options.maxHeight < options.minHeight then
            error(kind .. " panel resize bounds are invalid", 2)
        end
        local db = ResolveBindingDB(options.binding.getConfig)
        ReadDBPath(db, options.widthPath, "panel resize width")
        ReadDBPath(db, options.heightPath, "panel resize height")
        self.resizeOptions = options
        local handle = AcquirePanelResizeHandle(self.dock)
        self.resizeHandle = handle
        handle.__ExwindPanelResizeSession = self
        handle:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then self:StartResize(handle) end
        end)
        handle:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then self:FinishResize(true) end
        end)
        handle:SetScript("OnEnter", function()
            local width, height = self:ReadResizeSize()
            ShowPanelResizeTooltip(handle, width, height)
        end)
        handle:SetScript("OnLeave", function()
            if not self.resizeState then HidePanelResizeTooltip(handle) end
        end)
        handle:SetScript("OnHide", function()
            if self.resizeState then self:FinishResize(true)
            else HidePanelResizeTooltip(handle) end
        end)
        self:PositionResizeHandle()
        return self
    end

    function session:Render(entries, layout)
        if self.released then
            error(kind .. " panel preview is released", 2)
        end
        if type(layout) ~= "table" then
            error(kind .. " panel preview Render requires a semantic layout table", 2)
        end
        local items = {}
        for index, entry in ipairs(entries or {}) do
            local itemID, presentation = RequireEntry(entry, index, kind)
            local item = self.collection:AcquireItem(itemID)
            self.collection:ApplyItem(item, presentation)
            items[#items + 1] = item
        end
        self.collection:SetItems(items, layout)
        self.lastLayout = layout
        self.hasItems = #items > 0
        self:PositionResizeHandle()
        return items
    end

    function session:Clear()
        if self.released then return end
        self.collection:SetItems({}, self.lastLayout or { mode = "FLOW", direction = "DOWN", spacing = 0, maxVisible = 1 })
        self.hasItems = false
        self:PositionResizeHandle()
    end

    function session:GetBounds()
        if self.released then return nil end
        return self.collection:GetBounds()
    end

    -- 只暴露 Collection 的正式 API，不暴露 Widget/Hitbox/PreviewDock 的私有树。
    -- 模块可用它做已声明的窄 live visual Apply；不得借此自行创建预览元素。
    function session:GetCollection()
        if self.released then return nil end
        return self.collection
    end

    function session:SetIntentHandler(handler)
        if self.released then error(kind .. " panel preview is released", 2) end
        if type(handler) ~= "function" then error(kind .. " panel preview requires intent handler", 2) end
        self.collection.callbacks = self.collection.callbacks or {}
        self.collection.callbacks.onIntent = handler
    end

    -- Surface Release 必须先断开模块闭包，再把 Item / hitbox 交还给已有
    -- Collection。Collection:ReleaseItem 是唯一负责清脚本、鼠标与 pool 引用的
    -- 位置；这里不越过它触碰 Widget/Overlay 私有树。
    function session:ClearIntentHandler()
        if not self.collection then return end
        if self.collection.callbacks then self.collection.callbacks.onIntent = nil end
    end

    -- 已声明的 GUI live visual 只能重套本 session 已有的 presentation；它
    -- 不能创建 Item、不能碰 Widget/Overlay，也不能替代 commit 的 Render。
    function session:ReapplyCurrentItems(mutatePresentation, options)
        if self.released or type(self.collection.ReapplyCurrentItems) ~= "function" then return false end
        return self.collection:ReapplyCurrentItems(mutatePresentation, options)
    end

    -- StandardPreviewSurface uses this one in-place route for icon, text and
    -- timer-bar panel sessions.  It intentionally accepts only the exact
    -- already-materialized topology: no Acquire, Release or Render fallback
    -- is permitted during a GUI changing/committed notification.
    function session:ReapplyCurrent(entries, layout)
        if self.released or type(entries) ~= "table" or type(layout) ~= "table"
            or not self.collection or type(self.collection.ReapplyCurrentItems) ~= "function"
            or type(self.collection.ReapplyCurrentLayout) ~= "function" then
            return false
        end
        local currentItems = self.collection.currentItems or {}
        if #entries ~= #currentItems then return false end
        local presentationByID = {}
        for index, entry in ipairs(entries) do
            local itemID, presentation = RequireEntry(entry, index, kind)
            if presentationByID[itemID] ~= nil then return false end
            presentationByID[itemID] = presentation
        end
        for _, item in ipairs(currentItems) do
            if not item or presentationByID[item.id] == nil then return false end
        end
        local patched = self.collection:ReapplyCurrentItems(function(presentation, item)
            local nextPresentation = presentationByID[item.id]
            for key in pairs(presentation) do presentation[key] = nil end
            for key, value in pairs(nextPresentation) do presentation[key] = value end
        end)
        if not patched then return false end
        local laidOut = self.collection:ReapplyCurrentLayout(layout)
        if laidOut then
            self.lastLayout = layout
            self:PositionResizeHandle()
        end
        return laidOut == true
    end

    -- 标准 Page 的排列 Slider 可重排本 session 已有 Item；这不是完整 Render，
    -- 因而不得创建、回收或替换 session。
    function session:ReapplyCurrentLayout(layout)
        if self.released or type(self.collection.ReapplyCurrentLayout) ~= "function" then return false end
        return self.collection:ReapplyCurrentLayout(layout)
    end

    function session:ReapplyExistingItemSet(itemIDs, layout)
        if self.released or type(self.collection.ReapplyExistingItemSet) ~= "function" then return false end
        return self.collection:ReapplyExistingItemSet(itemIDs, layout)
    end

    -- 标准 Slider 的拖动期只可 Patch 已物化的 Panel Item。Collection 用字符串
    -- 明确区分 patched / requiresRebuild / unsupported；这里不以 Render 兜底，
    -- 也不暴露 Item、Widget 或预览树给模块。
    function session:Release()
        if self.released then return end
        if self.resizeState then self:FinishResize(true) end
        self.released = true
        self:ClearIntentHandler()
        self:ReleaseStylePresets()
        if self.resizeHandle and self.resizeHandle.__ExwindPanelResizeSession == self then
            local handle = self.resizeHandle
            handle:SetScript("OnUpdate", nil)
            handle:SetScript("OnMouseDown", nil)
            handle:SetScript("OnMouseUp", nil)
            handle:SetScript("OnEnter", nil)
            handle:SetScript("OnLeave", nil)
            handle:SetScript("OnHide", nil)
            handle.__ExwindPanelResizeSession = nil
            HidePanelResizeTooltip(handle)
            handle:Hide()
            handle:ClearAllPoints()
        end
        self.collection:Release()
        self.collection = nil
        self.dock = nil
        self.lastLayout = nil
        self.resizeHandle = nil
        self.resizeOptions = nil
        self.stylePresetControls = nil
        self.stylePresetDescriptor = nil
        self.stylePresetPending = nil
        self.stylePresetToken = nil
        self.hasItems = false
    end

    return session
end

--- 设置页图标预览。图标本体默认只读；只有 presentation 明确声明 interaction 时
--- 才会由 IconCollection 创建局部意图层。
function EXUI:CreateIconPanelPreview(dock, moduleKey, callbacks)
    return CreatePanelPreview("Icon", dock, moduleKey, callbacks, function(parent, mode, ownerKey, options)
        return EXUI:CreateIconCollection(parent, mode, ownerKey, options)
    end)
end

--- 设置页纯文本预览。文本本体默认只读；局部位置编辑必须由 presentation 明确声明。
function EXUI:CreateTextPanelPreview(dock, moduleKey, callbacks)
    return CreatePanelPreview("Text", dock, moduleKey, callbacks, function(parent, mode, ownerKey, options)
        return EXUI:CreateTextCollection(parent, mode, ownerKey, options)
    end)
end

--- 设置页计时条预览。传 callbacks.schema 时使用三文字 StandardTimerBarCollection；
--- 否则使用普通 TimerBarCollection。两者的 panel interaction 都由 Collection 内部拥有。
function EXUI:CreateTimerBarPanelPreview(dock, moduleKey, callbacks)
    EXUI:RequireModuleKey(moduleKey, "CreateTimerBarPanelPreview")
    callbacks = type(callbacks) == "table" and callbacks or {}
    if type(callbacks.schema) == "table" then
        return CreatePanelPreview("StandardTimerBar", dock, moduleKey, callbacks, function(parent, mode, ownerKey, options)
            return EXUI:CreateStandardTimerBarCollection(parent, mode, ownerKey, options)
        end)
    end
    return CreatePanelPreview("TimerBar", dock, moduleKey, callbacks, function(parent, mode, ownerKey, options)
        return EXUI:CreateTimerBarCollection(parent, mode, ownerKey, options)
    end)
end

-- =============================================================
-- Static Timeline panel preview
-- =============================================================
-- BunBar is a timeline, not a disguised IconCollection.  Its panel sample is
-- nevertheless a *static* declaration: the module describes geometry/content;
-- EXUI owns the one panel frame tree, visual nodes, hover/drag hitboxes and
-- release/pool lifecycle.  No runtime timer, Scheduler record or OnUpdate is
-- consumed here.  Drag's short-lived cursor watcher is input handling only and
-- is removed on mouse-up/release; it is never a duration renderer.

local timelineRootPool = {}
local timelineNodePool = {}

local function RequireTimelineNumber(value, label, level, positive)
    if type(value) ~= "number" or value ~= value or (positive and value <= 0) then
        error("Timeline panel preview requires " .. label .. " number" .. (positive and " > 0" or ""), level or 3)
    end
    return value
end

local function ApplyTimelineColor(region, color, label)
    if color == nil then
        region:SetVertexColor(1, 1, 1, 1)
        return
    end
    if type(color) ~= "table" then error("Timeline " .. label .. " color must be table", 3) end
    local r = RequireTimelineNumber(color.r or color[1], label .. ".color.r", 4)
    local g = RequireTimelineNumber(color.g or color[2], label .. ".color.g", 4)
    local b = RequireTimelineNumber(color.b or color[3], label .. ".color.b", 4)
    local a = color.a or color[4] or 1
    RequireTimelineNumber(a, label .. ".color.a", 4)
    region:SetVertexColor(r, g, b, a)
end

local function ApplyTimelineTexture(region, spec, label)
    if type(spec) ~= "table" then error("Timeline " .. label .. " must be table", 3) end
    RequireTimelineNumber(spec.x, label .. ".x", 4)
    RequireTimelineNumber(spec.y, label .. ".y", 4)
    RequireTimelineNumber(spec.width, label .. ".width", 4, true)
    RequireTimelineNumber(spec.height, label .. ".height", 4, true)
    if spec.atlas ~= nil then
        if type(spec.atlas) ~= "string" or spec.atlas == "" then
            error("Timeline " .. label .. ".atlas must be non-empty string", 3)
        end
        if spec.texture ~= nil then error("Timeline " .. label .. " may declare atlas or texture, not both", 3) end
        region:SetTexture(nil)
        region:SetAtlas(spec.atlas, true)
    elseif spec.texture == nil then
        region:SetColorTexture(1, 1, 1, 1)
    else
        if type(spec.texture) ~= "string" and type(spec.texture) ~= "number" then
            error("Timeline " .. label .. ".texture must be string, fileID, or nil", 3)
        end
        region:SetTexture(spec.texture)
        local left = spec.left == nil and 0 or RequireTimelineNumber(spec.left, label .. ".left", 4)
        local right = spec.right == nil and 1 or RequireTimelineNumber(spec.right, label .. ".right", 4)
        local top = spec.top == nil and 0 or RequireTimelineNumber(spec.top, label .. ".top", 4)
        local bottom = spec.bottom == nil and 1 or RequireTimelineNumber(spec.bottom, label .. ".bottom", 4)
        region:SetTexCoord(left, right, top, bottom)
    end
    ApplyTimelineColor(region, spec.color, label)
    region:ClearAllPoints()
    region:SetPoint("BOTTOMLEFT", region:GetParent(), "BOTTOMLEFT", spec.x, spec.y)
    region:SetSize(spec.width, spec.height)
    region:Show()
end

-- Timeline 是静态预览，但轨道与图标的边框仍属于同一份展示声明。边框只包住
-- 已存在的 Texture Region，绝不创建业务节点或改变 timeline 的生命周期。
local function ApplyTimelineBorder(border, region, spec, label)
    if not border or not region or spec == nil or spec.enabled == false then
        if border then border:SetBackdrop(nil); border:Hide(); border:ClearAllPoints() end
        return
    end
    if type(spec) ~= "table" then error("Timeline " .. label .. " must be table or nil", 3) end
    local texture = spec.texture
    if type(texture) ~= "string" or texture == "" then error("Timeline " .. label .. ".texture must be non-empty string", 3) end
    local edgeSize = RequireTimelineNumber(spec.edgeSize or 1, label .. ".edgeSize", 4, true)
    local padding = spec.padding == nil and 0 or RequireTimelineNumber(spec.padding, label .. ".padding", 4)
    border:SetBackdrop({ edgeFile = texture, edgeSize = edgeSize })
    local color = spec.color
    if color ~= nil and type(color) ~= "table" then error("Timeline " .. label .. ".color must be table or nil", 3) end
    border:SetBackdropBorderColor(
        (color and (color.r or color[1])) or 1,
        (color and (color.g or color[2])) or 1,
        (color and (color.b or color[3])) or 1,
        (color and (color.a or color[4])) or 1)
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", region, "TOPLEFT", -padding, padding)
    border:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", padding, -padding)
    border:Show()
end

local function SetTimelineOverlayVisual(overlay, visible, dragging)
    if dragging then
        overlay:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        overlay:SetBackdropBorderColor(1.00, 0.82, 0.20, 1.00)
        overlay:SetBackdropColor(1.00, 0.72, 0.12, 0.18)
    elseif visible then
        overlay:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        overlay:SetBackdropBorderColor(0.32, 0.82, 1.00, 0.95)
        overlay:SetBackdropColor(0.20, 0.65, 1.00, 0.10)
    else
        -- Never leave pooled selection borders visible.  alpha=0 is not enough
        -- on all clients after re-parenting, so remove the Backdrop itself.
        overlay:SetBackdrop(nil)
    end
end

local function ClearTimelineOverlay(overlay)
    if not overlay then return end
    overlay:SetScript("OnUpdate", nil)
    overlay:SetScript("OnMouseDown", nil)
    overlay:SetScript("OnMouseUp", nil)
    overlay:SetScript("OnEnter", nil)
    overlay:SetScript("OnLeave", nil)
    overlay._timelineDrag = nil
    overlay:EnableMouse(false)
    overlay:Hide()
    overlay:ClearAllPoints()
    SetTimelineOverlayVisual(overlay, false, false)
end

local function AcquireTimelineNode(parent)
    local node = table.remove(timelineNodePool)
    if not node then
        node = CreateFrame("Frame", nil, parent)
        node.icon = node:CreateTexture(nil, "ARTWORK")
        node.iconBorder = CreateFrame("Frame", nil, node, "BackdropTemplate")
        node.texts = {}
        node.alertIcons = {}
        node.overlays = {}
    else
        node:SetParent(parent)
    end
    -- Node/overlay pool objects retain explicit layers after SetParent.
    -- Re-establish the complete hierarchy whenever a dock is reused.
    node:SetFrameStrata(parent:GetFrameStrata() or "MEDIUM")
    node:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
    for _, overlay in pairs(node.overlays) do
        overlay:SetFrameStrata(node:GetFrameStrata() or "MEDIUM")
        overlay:SetFrameLevel((node:GetFrameLevel() or 1) + 80)
    end
    node:ClearAllPoints()
    node:SetAllPoints(parent)
    node:Show()
    return node
end

local function AcquireTimelineRoot(dock)
    local root = table.remove(timelineRootPool)
    if not root then
        root = CreateFrame("Frame", nil, dock)
        root.track = root:CreateTexture(nil, "BACKGROUND")
        root.trackBorder = CreateFrame("Frame", nil, root, "BackdropTemplate")
        root.fiveSecondLine = root:CreateTexture(nil, "BORDER")
    else
        root:SetParent(dock)
    end
    root:SetFrameStrata(dock:GetFrameStrata() or "MEDIUM")
    root:SetFrameLevel((dock:GetFrameLevel() or 1) + 1)
    return root
end

local function ReleaseTimelineRoot(root)
    if not root then return end
    root.track:Hide(); root.track:ClearAllPoints(); root.track:SetTexture(nil)
    if root.trackBorder then root.trackBorder:SetBackdrop(nil); root.trackBorder:Hide(); root.trackBorder:ClearAllPoints() end
    root.fiveSecondLine:Hide(); root.fiveSecondLine:ClearAllPoints(); root.fiveSecondLine:SetTexture(nil)
    root:Hide(); root:ClearAllPoints(); root:SetParent(UIParent)
    table.insert(timelineRootPool, root)
end

local function EnsureTimelineText(node, index)
    local text = node.texts[index]
    if text then return text end
    text = node:CreateFontString(nil, "OVERLAY")
    node.texts[index] = text
    return text
end

local function EnsureTimelineAlertIcon(node, index)
    local icon = node.alertIcons[index]
    if icon then return icon end
    icon = node:CreateTexture(nil, "OVERLAY")
    node.alertIcons[index] = icon
    return icon
end

local function EnsureTimelineOverlay(node, key)
    local overlay = node.overlays[key]
    if overlay then return overlay end
    overlay = CreateFrame("Button", nil, node, "BackdropTemplate")
    overlay:SetFrameStrata(node:GetFrameStrata() or "MEDIUM")
    overlay:SetFrameLevel((node:GetFrameLevel() or 1) + 80)
    node.overlays[key] = overlay
    return overlay
end

-- 图标的只读命中层不能盖住位于图标中央、可拖动的倒数文字。文字与 Atlas
-- 命中层统一比 core.icon 高一层，避免同层 sibling 的创建/复用顺序决定输入。
local function GetTimelineOverlayLevel(node, key)
    return (node:GetFrameLevel() or 1) + 80 + (key == "icon" and 0 or 1)
end

local function ReleaseTimelineNode(node)
    if not node then return end
    for _, overlay in pairs(node.overlays or {}) do ClearTimelineOverlay(overlay) end
    if node.icon then node.icon:SetTexture(nil); node.icon:Hide(); node.icon:ClearAllPoints() end
    if node.iconBorder then node.iconBorder:SetBackdrop(nil); node.iconBorder:Hide(); node.iconBorder:ClearAllPoints() end
    for _, text in pairs(node.texts or {}) do text:SetText(""); text:Hide(); text:ClearAllPoints() end
    for _, icon in pairs(node.alertIcons or {}) do icon:SetTexture(nil); icon:Hide(); icon:ClearAllPoints() end
    node:Hide()
    node:ClearAllPoints()
    node:SetParent(UIParent)
    table.insert(timelineNodePool, node)
end

local function ApplyTimelineFontString(region, spec, label)
    if type(spec) ~= "table" then error("Timeline " .. label .. " must be table", 3) end
    RequireTimelineNumber(spec.x, label .. ".x", 4)
    RequireTimelineNumber(spec.y, label .. ".y", 4)
    RequireTimelineNumber(spec.width, label .. ".width", 4, true)
    RequireTimelineNumber(spec.height, label .. ".height", 4, true)
    if type(spec.text) ~= "string" then error("Timeline " .. label .. ".text must be string", 3) end
    if spec.fontObject ~= nil then
        region:SetFontObject(spec.fontObject)
    elseif spec.font ~= nil or spec.size ~= nil or spec.flags ~= nil then
        if type(spec.font) ~= "string" or spec.font == "" then
            error("Timeline " .. label .. ".font must be non-empty string when custom font fields are present", 3)
        end
        RequireTimelineNumber(spec.size, label .. ".size", 4, true)
        if spec.flags ~= nil and type(spec.flags) ~= "string" then
            error("Timeline " .. label .. ".flags must be string or nil", 3)
        end
        region:SetFont(spec.font, spec.size, spec.flags or "")
    else
        region:SetFontObject(GameFontNormal)
    end
    if type(spec.color) == "table" then
        region:SetTextColor(spec.color.r or spec.color[1] or 1, spec.color.g or spec.color[2] or 1,
            spec.color.b or spec.color[3] or 1, spec.color.a or spec.color[4] or 1)
    elseif spec.color ~= nil then
        error("Timeline " .. label .. ".color must be table or nil", 3)
    else
        region:SetTextColor(1, 1, 1, 1)
    end
    if type(spec.shadowColor) == "table" then
        region:SetShadowColor(spec.shadowColor.r or spec.shadowColor[1] or 0, spec.shadowColor.g or spec.shadowColor[2] or 0,
            spec.shadowColor.b or spec.shadowColor[3] or 0, spec.shadowColor.a or spec.shadowColor[4] or 1)
    elseif spec.shadowColor ~= nil then
        error("Timeline " .. label .. ".shadowColor must be table or nil", 3)
    else
        region:SetShadowColor(0, 0, 0, 0)
    end
    local shadowX = spec.shadowX == nil and 0 or RequireTimelineNumber(spec.shadowX, label .. ".shadowX", 4)
    local shadowY = spec.shadowY == nil and 0 or RequireTimelineNumber(spec.shadowY, label .. ".shadowY", 4)
    region:SetShadowOffset(shadowX, shadowY)
    if spec.justifyH ~= nil and type(spec.justifyH) ~= "string" then
        error("Timeline " .. label .. ".justifyH must be string or nil", 3)
    end
    if spec.justifyV ~= nil and type(spec.justifyV) ~= "string" then
        error("Timeline " .. label .. ".justifyV must be string or nil", 3)
    end
    region:SetJustifyH(spec.justifyH or "LEFT")
    region:SetJustifyV(spec.justifyV or "MIDDLE")
    region:ClearAllPoints()
    region:SetPoint("BOTTOMLEFT", region:GetParent(), "BOTTOMLEFT", spec.x, spec.y)
    region:SetSize(spec.width, spec.height)
    region:SetText(spec.text)
    region:Show()
end

local function RequireTimelineElementID(spec, label)
    local elementID = spec.elementID
    if elementID == nil then return nil end
    if type(elementID) ~= "string" or elementID == "" then
        error("Timeline " .. label .. ".elementID must be non-empty string", 3)
    end
    return elementID
end

-- TimerBar 的局部拖动会把同一语义槽同步投影到所有已物化样本。Timeline 也必须
-- 遵守该规则：拖动期不写 DB、不重建，只给每个同 elementID 的既存 Region 加同一
-- 个增量；mouse-up 再由唯一标准 intent 写回 DB 并正式重套。
local function ApplyTimelineTransientPosition(session, elementID, deltaX, deltaY)
    for _, entry in ipairs(session.lastEntries or {}) do
        local itemID = entry.itemID or entry.id
        local node = itemID and session.nodesByID[itemID] or nil
        if node then
            local function apply(region, overlayKey, spec)
                if not region or type(spec) ~= "table" or spec.elementID ~= elementID then return end
                region:ClearAllPoints()
                region:SetPoint("BOTTOMLEFT", region:GetParent(), "BOTTOMLEFT", spec.x + deltaX, spec.y + deltaY)
                local overlay = node.overlays and node.overlays[overlayKey]
                if overlay then
                    overlay:ClearAllPoints()
                    overlay:SetPoint("CENTER", region, "CENTER")
                end
            end
            apply(node.icon, "icon", entry.icon)
            for index, spec in ipairs(entry.texts or {}) do
                apply(node.texts and node.texts[index], "text" .. tostring(index), spec)
            end
            for index, spec in ipairs(entry.alertIcons or {}) do
                apply(node.alertIcons and node.alertIcons[index], "alert" .. tostring(index), spec)
            end
        end
    end
end

-- The interaction schema is installed by BindStandardPreviewInteractions after
-- the page Grid exists.  That keeps movable/guiKey truth in one declaration:
-- timeline visual records provide geometry only and never repeat a private
-- movable flag or write a module DB.
local function ConfigureTimelineOverlay(session, node, key, spec, region, label)
    local elementID = RequireTimelineElementID(spec, label)
    local overlay = node.overlays[key]
    if not elementID then
        if overlay then ClearTimelineOverlay(overlay) end
        return
    end
    -- The standard binder is intentionally installed after the first Surface
    -- Render (only then has Grid rendered its GUI keys).  The first static
    -- materialization therefore draws visuals but owns no active hitbox yet;
    -- SetInteractionSchema immediately re-renders the same declaration.
    if not session.interactionSchema then
        if overlay then ClearTimelineOverlay(overlay) end
        return
    end
    local overlaySpec = session.interactionSchema and session.interactionSchema[elementID]
    if type(overlaySpec) ~= "table" then
        error("Timeline panel elementID is not declared by standard interaction schema: " .. elementID, 3)
    end
    local overlay = EnsureTimelineOverlay(node, key)
    -- Overlay buttons have explicit frame levels, therefore inheriting their
    -- parent alone is insufficient after a pool/reparent cycle.
    overlay:SetFrameStrata(node:GetFrameStrata() or "MEDIUM")
    overlay:SetFrameLevel(GetTimelineOverlayLevel(node, key))
    overlay:ClearAllPoints()
    overlay:SetPoint("CENTER", region, "CENTER")
    overlay:SetSize(spec.width, spec.height)
    overlay:EnableMouse(true)
    overlay:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown")
    SetTimelineOverlayVisual(overlay, false, false)

    -- A Timeline region moves its own hitbox during drag, so Blizzard can
    -- deliver the physical button-up either through OnMouseUp or only after
    -- the next OnUpdate observes that the button is no longer down.  Those
    -- two paths must share one idempotent commit: clearing _timelineDrag in
    -- the fallback first would otherwise turn a valid move into a visual-only
    -- drag that snaps back to its stored position.
    local function FinishTimelineDrag(button)
        local drag = button._timelineDrag
        if not drag then return false end
        button:SetScript("OnUpdate", nil)
        button._timelineDrag = nil
        ApplyTimelineTransientPosition(session, elementID, 0, 0)
        SetTimelineOverlayVisual(button, button:IsMouseOver(), false)
        if not drag.moved then return true end
        if type(session.intentHandler) ~= "function" then
            error("Timeline panel preview has no intent handler", 2)
        end
        local cursorX, cursorY = GetCursorPosition()
        local dx = cursorX / drag.scale - drag.cursorX
        local dy = cursorY / drag.scale - drag.cursorY
        session.intentHandler({ type = "elementMoved", elementID = elementID,
            position = { x = drag.baseX + dx, y = drag.baseY + dy } })
        return true
    end

    overlay:SetScript("OnMouseDown", function(button, mouseButton)
        if mouseButton == "RightButton" then
            if type(session.intentHandler) ~= "function" then error("Timeline panel preview has no intent handler", 2) end
            session.intentHandler({ type = "elementRightClicked", elementID = elementID })
            return
        end
        if mouseButton ~= "LeftButton" then return end
        if overlaySpec.movable ~= true then
            -- Standard binder consumes declared readonly element clicks.  It is
            -- still important that right click above can focus its controls.
            if type(session.intentHandler) == "function" then
                session.intentHandler({ type = "elementClicked", elementID = elementID })
            end
            return
        end
        local position = overlaySpec.position
        if type(position) ~= "table" or type(position.x) ~= "string" or type(position.y) ~= "string" then
            error("Timeline movable element lacks standard position declaration: " .. elementID, 2)
        end
        local db = session.configRoot
        local baseX = ReadDBPath(db, position.x, "timeline interaction " .. elementID)
        local baseY = ReadDBPath(db, position.y, "timeline interaction " .. elementID)
        local scale = (UIParent and UIParent:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        local cursorX, cursorY = GetCursorPosition()
        button._timelineDrag = { scale = scale, cursorX = cursorX / scale, cursorY = cursorY / scale,
            baseX = baseX, baseY = baseY, moved = false }
        SetTimelineOverlayVisual(button, true, true)
        button:SetScript("OnUpdate", function(active)
            local drag = active._timelineDrag
            if not drag then return end
            if not IsMouseButtonDown("LeftButton") then
                FinishTimelineDrag(active)
                return
            end
            local x, y = GetCursorPosition()
            local dx, dy = x / drag.scale - drag.cursorX, y / drag.scale - drag.cursorY
            if not drag.moved and math.abs(dx) < 2 and math.abs(dy) < 2 then return end
            drag.moved = true
            -- Immediate visual movement is deliberately limited to this static
            -- declared region/hitbox; DB write/full presentation refresh happens
            -- on mouse-up through the standard interaction contract.
            ApplyTimelineTransientPosition(session, elementID, dx, dy)
        end)
    end)
    overlay:SetScript("OnMouseUp", function(button, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        FinishTimelineDrag(button)
    end)
    overlay:SetScript("OnEnter", function(button)
        SetTimelineOverlayVisual(button, true, button._timelineDrag ~= nil)
        if GameTooltip then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["左键拖动位置；右键定位设置"], 0.72, 0.94, 1.00)
            GameTooltip:Show()
        end
    end)
    overlay:SetScript("OnLeave", function(button)
        if not button._timelineDrag then SetTimelineOverlayVisual(button, false, false) end
        if GameTooltip and GameTooltip:GetOwner() == button then GameTooltip:Hide() end
    end)
    overlay:Show()
end

local function AddTimelineBounds(bounds, region)
    if not region or (region.IsShown and not region:IsShown()) then return end
    local left, right, top, bottom = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
    if not (left and right and top and bottom) then return end
    bounds.left = bounds.left and math.min(bounds.left, left) or left
    bounds.right = bounds.right and math.max(bounds.right, right) or right
    bounds.top = bounds.top and math.max(bounds.top, top) or top
    bounds.bottom = bounds.bottom and math.min(bounds.bottom, bottom) or bottom
end

local function GetTimelineBounds(root, nodesByID)
    local bounds = {}
    AddTimelineBounds(bounds, root)
    AddTimelineBounds(bounds, root and root.track)
    AddTimelineBounds(bounds, root and root.fiveSecondLine)
    for _, node in pairs(nodesByID or {}) do
        AddTimelineBounds(bounds, node)
        AddTimelineBounds(bounds, node.icon)
        for _, text in pairs(node.texts or {}) do AddTimelineBounds(bounds, text) end
        for _, icon in pairs(node.alertIcons or {}) do AddTimelineBounds(bounds, icon) end
    end
    if not bounds.left then
        return { width = root:GetWidth() or 1, height = root:GetHeight() or 1 }
    end
    return { left = bounds.left, right = bounds.right, top = bounds.top, bottom = bounds.bottom,
        width = math.max(1, bounds.right - bounds.left), height = math.max(1, bounds.top - bounds.bottom),
        anchorOffsetX = (bounds.left + bounds.right) * 0.5, anchorOffsetY = (bounds.bottom + bounds.top) * 0.5 }
end

local function FitTimelineRootToDock(session, timeline, anchor, timelineX, timelineY)
    -- 部分时间轴的语义根（BunBar）就是轨道中心：名称/Atlas 可以向外延伸，
    -- 却不能反过来把模块中心或图标中心推离固定锚点。
    if timeline.lockAnchor == true then return end
    local dock, root = session.dock, session.root
    local dockLeft, dockRight = dock and dock:GetLeft(), dock and dock:GetRight()
    local bounds = GetTimelineBounds(root, session.nodesByID)
    if not (dockLeft and dockRight and bounds.left and bounds.right) then return end
    local inset = 8
    local minShift, maxShift = (dockLeft + inset) - bounds.left, (dockRight - inset) - bounds.right
    local shift = minShift <= maxShift and math.min(maxShift, math.max(minShift, 0)) or maxShift
    if shift == 0 then return end
    root:ClearAllPoints()
    root:SetPoint(anchor, dock, anchor, timelineX + shift, timelineY)
end

-- 已物化 Timeline 的窄重套路径：只应用既存 root/node/region，绝不向池索取
-- 或释放对象。任何 itemID、文本、Atlas 数量或交互 elementID 的拓扑变化都返回
-- false，留给 mouse-up 的完整 Render 处理。
local function TimelineEntryHasSameTopology(previous, entry)
    if type(previous) ~= "table" or type(entry) ~= "table" then return false end
    local previousID, itemID = previous.itemID or previous.id, entry.itemID or entry.id
    if previousID ~= itemID then return false end
    local previousIcon = previous.icon and previous.icon.elementID or nil
    local icon = entry.icon and entry.icon.elementID or nil
    if previousIcon ~= icon or #(previous.texts or {}) ~= #(entry.texts or {})
        or #(previous.alertIcons or {}) ~= #(entry.alertIcons or {}) then
        return false
    end
    for index, spec in ipairs(entry.texts or {}) do
        if (previous.texts[index] or {}).elementID ~= spec.elementID then return false end
    end
    for index, spec in ipairs(entry.alertIcons or {}) do
        if (previous.alertIcons[index] or {}).elementID ~= spec.elementID then return false end
    end
    return true
end

local function ReapplyTimelineNode(session, node, entry, itemID)
    local icon = entry.icon
    if icon then
        ApplyTimelineTexture(node.icon, icon, "entry " .. itemID .. ".icon")
        ApplyTimelineBorder(node.iconBorder, node.icon, icon.border, "entry " .. itemID .. ".icon.border")
        ConfigureTimelineOverlay(session, node, "icon", icon, node.icon, "entry " .. itemID .. ".icon")
    else
        node.icon:Hide()
        ApplyTimelineBorder(node.iconBorder, node.icon, nil, "entry " .. itemID .. ".icon.border")
        ConfigureTimelineOverlay(session, node, "icon", {}, node.icon, "entry " .. itemID .. ".icon")
    end
    for textIndex, textSpec in ipairs(entry.texts or {}) do
        local text = node.texts[textIndex]
        ApplyTimelineFontString(text, textSpec, "entry " .. itemID .. ".texts[" .. tostring(textIndex) .. "]")
        ConfigureTimelineOverlay(session, node, "text" .. tostring(textIndex), textSpec, text,
            "entry " .. itemID .. ".texts[" .. tostring(textIndex) .. "]")
    end
    for alertIndex, alertSpec in ipairs(entry.alertIcons or {}) do
        local alert = node.alertIcons[alertIndex]
        ApplyTimelineTexture(alert, alertSpec, "entry " .. itemID .. ".alertIcons[" .. tostring(alertIndex) .. "]")
        ConfigureTimelineOverlay(session, node, "alert" .. tostring(alertIndex), alertSpec, alert,
            "entry " .. itemID .. ".alertIcons[" .. tostring(alertIndex) .. "]")
    end
end

-- Timeline slider patch helpers deliberately operate on existing specs and regions only.
-- They never call Render/EnsureTimeline*/AcquireTimeline*/ReleaseTimeline*, so a drag cannot
-- create a node, alter topology, or touch the runtime/world tree.
local function PatchTimelineRegionGeometry(region, spec)
    if not region or type(spec) ~= "table" then return false end
    region:ClearAllPoints()
    region:SetPoint("BOTTOMLEFT", region:GetParent(), "BOTTOMLEFT", spec.x, spec.y)
    region:SetSize(spec.width, spec.height)
    return true
end

local function PatchTimelineOverlayGeometry(node, key, region, spec)
    local overlay = node and node.overlays and node.overlays[key]
    if not overlay or not region or type(spec) ~= "table" then return end
    overlay:ClearAllPoints()
    overlay:SetPoint("CENTER", region, "CENTER")
    overlay:SetSize(spec.width, spec.height)
end

local function PatchTimelineTextureGeometry(node, key, region, spec)
    if not PatchTimelineRegionGeometry(region, spec) then return false end
    PatchTimelineOverlayGeometry(node, key, region, spec)
    return true
end

local function PatchTimelineFontGeometry(node, index, spec)
    local region = node and node.texts and node.texts[index]
    if not PatchTimelineRegionGeometry(region, spec) then return false end
    PatchTimelineOverlayGeometry(node, "text" .. tostring(index), region, spec)
    return true
end

local function FindTimelineEntryText(entry, elementID)
    for index, spec in ipairs(entry.texts or {}) do
        if spec.elementID == elementID then return index, spec end
    end
    return nil, nil
end

local function FindTimelineEntryAlert(entry, index)
    return (entry.alertIcons or {})[index]
end

--- Creates the one formal static timeline panel session.  `Render(timeline,
--- entries)` accepts only declarative geometry: timeline requires width/height,
--- a track and fiveSecondLine; every entry has stable itemID plus optional
--- icon/texts/alertIcons records.  Those records may carry elementID, whose
--- GUI/movable/DB truth is supplied only by BindStandardPreviewInteractions.
function EXUI:CreateStandardTimelinePanelPreview(dock, moduleKey)
    RequireDock(dock, "CreateStandardTimelinePanelPreview")
    moduleKey = EXUI:RequireModuleKey(moduleKey, "CreateStandardTimelinePanelPreview")
    local root = AcquireTimelineRoot(dock)
    local session = { kind = "Timeline", dock = dock, root = root, moduleKey = moduleKey,
        nodesByID = {}, interactionSchema = nil, configRoot = nil, intentHandler = nil, released = false }

    function session:SetInteractionSchema(schema, configRoot)
        if self.released then error("Timeline panel preview is released", 2) end
        if type(schema) ~= "table" or type(configRoot) ~= "table" then
            error("Timeline panel preview requires standard interaction schema and config root", 2)
        end
        self.interactionSchema, self.configRoot = schema, configRoot
        if self.lastTimeline and self.lastEntries then
            self:Render(self.lastTimeline, self.lastEntries)
        end
    end

    function session:SetIntentHandler(handler)
        if self.released then error("Timeline panel preview is released", 2) end
        if type(handler) ~= "function" then error("Timeline panel preview requires intent handler", 2) end
        self.intentHandler = handler
    end

    function session:ClearIntentHandler()
        self.intentHandler = nil
    end

    function session:Render(timeline, entries)
        if self.released then error("Timeline panel preview is released", 2) end
        if type(timeline) ~= "table" or type(entries) ~= "table" then
            error("Timeline panel preview Render requires timeline and entries tables", 2)
        end
        self.lastTimeline, self.lastEntries = timeline, entries
        RequireTimelineNumber(timeline.width, "timeline.width", 3, true)
        RequireTimelineNumber(timeline.height, "timeline.height", 3, true)
        -- Omission is the only supported default.  A string/boolean/etc. must
        -- fail at declaration time instead of being silently tonumber-ed.
        local timelineX = timeline.x == nil and 0 or RequireTimelineNumber(timeline.x, "timeline.x", 3)
        local timelineY = timeline.y == nil and 0 or RequireTimelineNumber(timeline.y, "timeline.y", 3)
        if type(timeline.track) ~= "table" or type(timeline.fiveSecondLine) ~= "table" then
            error("Timeline panel preview requires track and fiveSecondLine declarations", 2)
        end
        local anchor = timeline.anchor or "CENTER"
        if anchor ~= "CENTER" and anchor ~= "TOPLEFT" and anchor ~= "BOTTOMLEFT" then
            error("Timeline panel preview anchor must be CENTER, TOPLEFT, or BOTTOMLEFT", 2)
        end
        root:ClearAllPoints()
        root:SetPoint(anchor, dock, anchor, timelineX, timelineY)
        root:SetSize(timeline.width, timeline.height)
        ApplyTimelineTexture(root.track, timeline.track, "track")
        ApplyTimelineBorder(root.trackBorder, root.track, timeline.track.border, "track.border")
        ApplyTimelineTexture(root.fiveSecondLine, timeline.fiveSecondLine, "fiveSecondLine")
        local seen = {}
        for index, entry in ipairs(entries) do
            local itemID = type(entry) == "table" and (entry.itemID or entry.id) or nil
            if type(itemID) ~= "string" or itemID == "" then
                error("Timeline panel preview entry #" .. tostring(index) .. " requires itemID", 2)
            end
            if seen[itemID] then error("Timeline panel preview duplicate itemID: " .. itemID, 2) end
            seen[itemID] = true
            local node = self.nodesByID[itemID] or AcquireTimelineNode(root)
            self.nodesByID[itemID] = node
            node:SetParent(root)
            node:SetFrameStrata(root:GetFrameStrata() or "MEDIUM")
            node:SetFrameLevel((root:GetFrameLevel() or 1) + 5)
            for _, overlay in pairs(node.overlays) do
                overlay:SetFrameStrata(node:GetFrameStrata() or "MEDIUM")
                overlay:SetFrameLevel((node:GetFrameLevel() or 1) + 80)
            end
            node:SetAllPoints(root)
            local icon = entry.icon
            if icon ~= nil and type(icon) ~= "table" then
                error("Timeline panel preview entry " .. itemID .. ".icon must be table or nil", 2)
            end
            if icon then
                ApplyTimelineTexture(node.icon, icon, "entry " .. itemID .. ".icon")
                ApplyTimelineBorder(node.iconBorder, node.icon, icon.border, "entry " .. itemID .. ".icon.border")
                ConfigureTimelineOverlay(self, node, "icon", icon, node.icon, "entry " .. itemID .. ".icon")
            else
                node.icon:Hide()
                ApplyTimelineBorder(node.iconBorder, node.icon, nil, "entry " .. itemID .. ".icon.border")
                ConfigureTimelineOverlay(self, node, "icon", {}, node.icon, "entry " .. itemID .. ".icon")
            end
            if entry.texts ~= nil and type(entry.texts) ~= "table" then
                error("Timeline panel preview entry " .. itemID .. ".texts must be table or nil", 2)
            end
            local texts = entry.texts or {}
            for textIndex, textSpec in ipairs(texts) do
                local text = EnsureTimelineText(node, textIndex)
                ApplyTimelineFontString(text, textSpec, "entry " .. itemID .. ".texts[" .. tostring(textIndex) .. "]")
                ConfigureTimelineOverlay(self, node, "text" .. tostring(textIndex), textSpec, text,
                    "entry " .. itemID .. ".texts[" .. tostring(textIndex) .. "]")
            end
            for textIndex = #texts + 1, #node.texts do
                node.texts[textIndex]:Hide()
                ConfigureTimelineOverlay(self, node, "text" .. tostring(textIndex), {}, node.texts[textIndex], "unused text")
            end
            if entry.alertIcons ~= nil and type(entry.alertIcons) ~= "table" then
                error("Timeline panel preview entry " .. itemID .. ".alertIcons must be table or nil", 2)
            end
            local alerts = entry.alertIcons or {}
            for alertIndex, alertSpec in ipairs(alerts) do
                local alert = EnsureTimelineAlertIcon(node, alertIndex)
                ApplyTimelineTexture(alert, alertSpec, "entry " .. itemID .. ".alertIcons[" .. tostring(alertIndex) .. "]")
                ConfigureTimelineOverlay(self, node, "alert" .. tostring(alertIndex), alertSpec, alert,
                    "entry " .. itemID .. ".alertIcons[" .. tostring(alertIndex) .. "]")
            end
            for alertIndex = #alerts + 1, #node.alertIcons do
                node.alertIcons[alertIndex]:Hide()
                ConfigureTimelineOverlay(self, node, "alert" .. tostring(alertIndex), {}, node.alertIcons[alertIndex], "unused alert")
            end
        end
        for itemID, node in pairs(self.nodesByID) do
            if not seen[itemID] then
                self.nodesByID[itemID] = nil
                ReleaseTimelineNode(node)
            end
        end
        root:Show()
        -- A declaration may deliberately extend name/alert geometry beyond the
        -- semantic track.  Fit the complete visual union rather than guessing
        -- with track width, so an external-left dock never cuts off text.
        FitTimelineRootToDock(self, timeline, anchor, timelineX, timelineY)
        return self
    end

    function session:ReapplyCurrent(timeline, entries)
        if self.released or not self.root or type(timeline) ~= "table" or type(entries) ~= "table"
            or type(self.lastTimeline) ~= "table" or type(self.lastEntries) ~= "table"
            or #entries ~= #self.lastEntries then
            return false
        end
        RequireTimelineNumber(timeline.width, "timeline.width", 3, true)
        RequireTimelineNumber(timeline.height, "timeline.height", 3, true)
        local timelineX = timeline.x == nil and 0 or RequireTimelineNumber(timeline.x, "timeline.x", 3)
        local timelineY = timeline.y == nil and 0 or RequireTimelineNumber(timeline.y, "timeline.y", 3)
        if type(timeline.track) ~= "table" or type(timeline.fiveSecondLine) ~= "table" then return false end
        local anchor = timeline.anchor or "CENTER"
        if anchor ~= "CENTER" and anchor ~= "TOPLEFT" and anchor ~= "BOTTOMLEFT" then return false end

        local previousByID, seen = {}, {}
        for _, previous in ipairs(self.lastEntries) do previousByID[previous.itemID or previous.id] = previous end
        for _, entry in ipairs(entries) do
            local itemID = type(entry) == "table" and (entry.itemID or entry.id) or nil
            local node = itemID and self.nodesByID[itemID] or nil
            if type(itemID) ~= "string" or itemID == "" or seen[itemID] or not node
                or not TimelineEntryHasSameTopology(previousByID[itemID], entry)
                or #(node.texts or {}) ~= #(entry.texts or {}) or #(node.alertIcons or {}) ~= #(entry.alertIcons or {}) then
                return false
            end
            seen[itemID] = true
            if entry.icon and entry.icon.elementID and not node.overlays.icon then return false end
            for index, spec in ipairs(entry.texts or {}) do
                if spec.elementID and not node.overlays["text" .. tostring(index)] then return false end
            end
            for index, spec in ipairs(entry.alertIcons or {}) do
                if spec.elementID and not node.overlays["alert" .. tostring(index)] then return false end
            end
        end

        local root = self.root
        root:ClearAllPoints()
        root:SetPoint(anchor, self.dock, anchor, timelineX, timelineY)
        root:SetSize(timeline.width, timeline.height)
        ApplyTimelineTexture(root.track, timeline.track, "track")
        ApplyTimelineBorder(root.trackBorder, root.track, timeline.track.border, "track.border")
        ApplyTimelineTexture(root.fiveSecondLine, timeline.fiveSecondLine, "fiveSecondLine")
        for _, entry in ipairs(entries) do
            local itemID = entry.itemID or entry.id
            ReapplyTimelineNode(self, self.nodesByID[itemID], entry, itemID)
        end
        self.lastTimeline, self.lastEntries = timeline, entries
        FitTimelineRootToDock(self, timeline, anchor, timelineX, timelineY)
        return true
    end

    -- BunBar currently uses Timeline for its StandardPreviewSurface.  These are the
    -- scalar paths represented by that already-materialized declaration.  A path
    -- omitted from the declaration has no region to patch and must wait for mouse-up.
    function session:GetBounds()
        if self.released or not self.root then return nil end
        return GetTimelineBounds(self.root, self.nodesByID)
    end

    function session:Release()
        if self.released then return end
        self.released = true
        self:ClearIntentHandler()
        for itemID, node in pairs(self.nodesByID) do
            self.nodesByID[itemID] = nil
            ReleaseTimelineNode(node)
        end
        ReleaseTimelineRoot(self.root)
        self.interactionSchema, self.configRoot, self.root, self.dock = nil, nil, nil, nil
        self.lastTimeline, self.lastEntries = nil, nil
    end
    return session
end

-- Material/Ring 仍使用既有 CreateStandardPreview 的声明式 renderer；这里仅把它
-- 收口为与 Collection session 相同的 panel 生命周期和 intent 合同。不得由模块
-- 传入私有 onIntent，也不得在此新建第二个 renderer、hitbox 或拖动层。
local function CopyMaterialPanelOptions(options)
    options = type(options) == "table" and options or {}
    if options.onIntent ~= nil then
        error("CreateMaterialPanelPreview owns onIntent; bind through BindStandardPreviewInteractions", 3)
    end
    local allowed = {
        autoSizeHost = true,
        autoSizeHostWidth = true,
        hostPadding = true,
        minHostHeight = true,
        panelContentAlignment = true,
        panelContentInset = true,
        dragThreshold = true,
        renderExtraChildren = true,
    }
    local copy = {}
    for key, value in pairs(options) do
        if not allowed[key] then
            error("CreateMaterialPanelPreview has unsupported option: " .. tostring(key), 3)
        end
        copy[key] = value
    end
    return copy
end

-- 设置页 Material/Ring 预览。Render 只接受标准声明式 definition/model；模块不得
-- 接触底层 preview 的 onIntent、Release 或 hitbox。Release 用 Unmount 结束本次
-- session，保证切换 rule/dock 后不会留下旧 layout 或模块闭包。
function EXUI:CreateMaterialPanelPreview(dock, moduleKey, options)
    RequireDock(dock, "CreateMaterialPanelPreview")
    moduleKey = EXUI:RequireModuleKey(moduleKey, "CreateMaterialPanelPreview")
    local materialOptions = CopyMaterialPanelOptions(options)
    local intentHandler = nil
    local released = false
    local preview = EXUI:CreateStandardPreview(dock, {
        interactionMode = "panel",
        autoSizeHost = materialOptions.autoSizeHost,
        autoSizeHostWidth = materialOptions.autoSizeHostWidth,
        hostPadding = materialOptions.hostPadding,
        minHostHeight = materialOptions.minHostHeight,
        panelContentAlignment = materialOptions.panelContentAlignment,
        panelContentInset = materialOptions.panelContentInset,
        dragThreshold = materialOptions.dragThreshold,
        renderExtraChildren = materialOptions.renderExtraChildren,
        onIntent = function(intent)
            if released then return false end
            if type(intentHandler) ~= "function" then
                error("Material panel preview has no standard intent handler", 2)
            end
            return intentHandler(intent)
        end,
    })
    local session = {
        kind = "Material",
        dock = dock,
        preview = preview,
        released = false,
    }

    function session:Render(definition, model)
        if self.released then error("Material panel preview is released", 2) end
        if type(definition) ~= "table" or type(model) ~= "table" then
            error("Material panel preview Render requires definition and model tables", 2)
        end
        self.preview:Materialize(definition, model)
        return self
    end

    function session:ReapplyCurrent(definition, model)
        if self.released or not self.preview or type(self.preview.ReapplyCurrentMaterial) ~= "function" then
            return false
        end
        return self.preview:ReapplyCurrentMaterial(definition, model)
    end

    function session:SetIntentHandler(handler)
        if self.released then error("Material panel preview is released", 2) end
        if type(handler) ~= "function" then error("Material panel preview requires intent handler", 2) end
        intentHandler = handler
    end

    function session:ClearIntentHandler()
        intentHandler = nil
    end

    function session:GetBounds()
        if self.released or not self.preview then return nil end
        return self.preview:GetBounds()
    end

    function session:Release()
        if self.released then return end
        self.released = true
        released = true
        self:ClearIntentHandler()
        if self.preview then self.preview:Unmount() end
        self.preview = nil
        self.dock = nil
    end

    return session
end

-- 标准 Panel surface 只管理已存在 Panel session 的 mount / Render / Release。
-- 它不理解业务 state，也不创建 Collection 以外的 Frame；BuildPresentation 的
-- 结果必须是模块明确给出的 entries + semantic layout，随后直传公开 session。
--
-- 调用约定：
--   local surface = EXUI:CreateStandardPreviewSurface({
--       moduleKey = MODULE_KEY,
--       kind = "icon" | "timerbar" | "text" | "material" | "timeline",
--       buildPresentation = BuildPresentation,
--       binding = CONFIG_BINDING,       -- 或已注册同 moduleKey 的 binding
--       interactionSchema = INTERACTION_SCHEMA, -- 必填；Core 在 session 创建后绑定
--       requiredPositionGuiKeys = { "font_time" }, -- 可选的严格位置映射断言
--       collectionOptions = {},         -- 仅创建 session 时的静态 factory 参数
--   })
--   local session = surface:Render({
--       dock = dock, ruleKey = stableRuleKey, state = sampleState,
--   })
-- BuildPresentation(state, "panel") 必须返回：
--   Collection: { entries = { { itemID = "...", presentation = {...} } }, layout = {...} }
--   Material:   { definition = {...}, model = {...} }
--   Timeline:   { timeline = { width, height, track, fiveSecondLine }, entries = {...} }
-- 同一 surface 的 moduleKey 固定；只有 ruleKey 或 dock 改变才会 Release + 新建。
local function RequireStandardPreviewKind(kind)
    if kind ~= "icon" and kind ~= "timerbar" and kind ~= "text" and kind ~= "material" and kind ~= "timeline" then
        error("CreateStandardPreviewSurface kind must be icon, timerbar, text, material, or timeline", 3)
    end
    return kind
end

local function RequireStandardPreviewResult(kind, result)
    if type(result) ~= "table" then
        error("StandardPreviewSurface BuildPresentation must return table", 3)
    end
    if kind == "material" then
        if type(result.definition) ~= "table" or type(result.model) ~= "table" then
            error("Material StandardPreviewSurface result requires definition and model tables", 3)
        end
        return result.definition, result.model
    end
    if kind == "timeline" then
        if type(result.timeline) ~= "table" or type(result.entries) ~= "table" then
            error("Timeline StandardPreviewSurface result requires timeline and entries tables", 3)
        end
        return result.timeline, result.entries
    end
    if type(result.entries) ~= "table" then
        error("StandardPreviewSurface BuildPresentation result requires entries", 3)
    end
    if type(result.layout) ~= "table" then
        error("StandardPreviewSurface BuildPresentation result requires layout", 3)
    end
    return result.entries, result.layout
end

local function CreateStandardSurfaceSession(surface, dock)
    local options = CopyTable(surface.collectionOptions)
    if surface.kind == "material" then
        return EXUI:CreateMaterialPanelPreview(dock, surface.moduleKey, options)
    end
    if surface.kind == "timeline" then
        if next(options) ~= nil then
            error("Timeline StandardPreviewSurface does not accept collectionOptions", 3)
        end
        return EXUI:CreateStandardTimelinePanelPreview(dock, surface.moduleKey)
    end
    if surface.kind == "icon" then
        return EXUI:CreateIconPanelPreview(dock, surface.moduleKey, options)
    end
    if surface.kind == "text" then
        return EXUI:CreateTextPanelPreview(dock, surface.moduleKey, options)
    end
    return EXUI:CreateTimerBarPanelPreview(dock, surface.moduleKey, options)
end

function EXUI:CreateStandardPreviewSurface(options)
    if type(options) ~= "table" then error("CreateStandardPreviewSurface requires table", 2) end
    local moduleKey = EXUI:RequireModuleKey(options.moduleKey, "CreateStandardPreviewSurface")
    local kind = RequireStandardPreviewKind(options.kind)
    if type(options.buildPresentation) ~= "function" then
        error("CreateStandardPreviewSurface requires buildPresentation", 2)
    end
    local registeredBinding = EXUI:GetStandardConfigBinding(moduleKey)
    local binding = options.binding or registeredBinding
    if type(binding) ~= "table" or binding.moduleKey ~= moduleKey or binding ~= registeredBinding then
        error("CreateStandardPreviewSurface requires registered matching config binding: " .. moduleKey, 2)
    end
    if type(options.collectionOptions) ~= "nil" and type(options.collectionOptions) ~= "table" then
        error("CreateStandardPreviewSurface collectionOptions must be table", 2)
    end
    if type(options.interactionSchema) ~= "table" then
        error("CreateStandardPreviewSurface requires interactionSchema table", 2)
    end
    if options.requiredPositionGuiKeys ~= nil and type(options.requiredPositionGuiKeys) ~= "table" then
        error("CreateStandardPreviewSurface requiredPositionGuiKeys must be table", 2)
    end

    local surface = {
        moduleKey = moduleKey,
        kind = kind,
        binding = binding,
        buildPresentation = options.buildPresentation,
        collectionOptions = CopyTable(options.collectionOptions),
        interactionSchema = options.interactionSchema,
        requiredPositionGuiKeys = options.requiredPositionGuiKeys,
        session = nil,
        dock = nil,
        ruleKey = nil,
        lastState = nil,
        released = false,
    }
    -- Surface declaration is owned by the binding.  A Page may only consume
    -- this surface; it must not install a second interaction/preview chain.
    if binding.contract.surface and binding.contract.surface ~= surface then
        error("standard display binding already has a PreviewSurface: " .. moduleKey, 2)
    end
    binding.contract.surface = surface

    function surface:GetSession()
        if self.released then return nil end
        return self.session
    end

    function surface:Release()
        local session = self.session
        self.session = nil
        self.dock = nil
        self.ruleKey = nil
        self.lastState = nil
        if session then session:Release() end
    end

    function surface:Render(request)
        if self.released then error("StandardPreviewSurface is released", 2) end
        if type(request) ~= "table" then error("StandardPreviewSurface Render requires table", 2) end
        local dock = request.dock
        RequireDock(dock, "StandardPreviewSurface Render")
        local ruleKey = request.ruleKey
        if type(ruleKey) ~= "string" or ruleKey == "" then
            error("StandardPreviewSurface Render requires stable non-empty ruleKey", 2)
        end

        -- 不同规则或不同 Dock 绝不能带着旧 panel hitbox 复用；同一三元组只
        -- Render 既有 session，避免无谓 Acquire/Release 与第二预览树。
        if self.session and (self.dock ~= dock or self.ruleKey ~= ruleKey) then
            self:Release()
        end
        if not self.session then
            self.session = CreateStandardSurfaceSession(self, dock)
            self.dock = dock
            self.ruleKey = ruleKey
            -- StandardModulePage renders Grid before preview.  Installing the
            -- declaration at session creation makes that order an EXUI
            -- invariant: Timeline gets its schema before its first Render,
            -- while Icon/TimerBar/Text receive the same formal handler without
            -- a module-owned afterGrid/preview timing bridge.
            EXUI:BindStandardPreviewInteractions(self.session, {
                moduleKey = self.moduleKey,
                binding = self.binding,
                elements = self.interactionSchema,
                requiredPositionGuiKeys = self.requiredPositionGuiKeys,
            })
        end

        local result = self.buildPresentation(request.state, "panel")
        local first, second = RequireStandardPreviewResult(self.kind, result)
        self.session:Render(first, second)
        self.lastState = request.state
        return self.session
    end

    -- Slider drag may only update an already materialized panel session.  This
    -- narrow route deliberately never falls back to Render: a changed topology
    -- returns false and the normal mouse-up refresh owns the full rebuild.
    function surface:ReapplyPanelPresentation()
        if self.released or not self.session then return false end
        local result = self.buildPresentation(self.lastState, "panel")
        local first, second = RequireStandardPreviewResult(self.kind, result)
        if type(self.session.ReapplyCurrent) ~= "function" then return false end
        return self.session:ReapplyCurrent(first, second) == true
    end

    -- Surface 仅转发既有 session 的窄 Patch；无法直接修改的结构字段必须把
    -- requiresRebuild 原样交还给放开阶段，绝不在拖动期重新 Render Preview。
    function surface:Destroy()
        if self.released then return end
        self:Release()
        self.released = true
        self.binding = nil
        self.buildPresentation = nil
        self.lastState = nil
        self.collectionOptions = nil
        self.interactionSchema = nil
        self.requiredPositionGuiKeys = nil
    end

    return surface
end
