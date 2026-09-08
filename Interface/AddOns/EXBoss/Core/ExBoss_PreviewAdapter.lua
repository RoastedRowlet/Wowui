---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBoss_PreviewAdapter.lua
--
-- EXBoss 设定页到 ExwindPreviewWorkspace 的唯一桥接层。
-- 它只交付配置快照和固定假样本；绝不把运行时条体、单位资料或业务
-- iconFlags 交给共用 Preview Core。
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })

ExBoss = ExBoss or {}
ExBoss.UI = ExBoss.UI or {}
ExBoss.UI.PreviewAdapter = ExBoss.UI.PreviewAdapter or {}
local Adapter = ExBoss.UI.PreviewAdapter

local function CopyTable(source)
    if type(source) ~= "table" then return source end
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = CopyTable(value)
    end
    return copy
end

local function ColorFromConfig(config, prefix)
    config = type(config) == "table" and config or {}
    local color = config.color or config[prefix .. "Color"]
    if type(color) == "table" then return color end
    local r = config[prefix .. "ColorR"] or config.r
    local g = config[prefix .. "ColorG"] or config.g
    local b = config[prefix .. "ColorB"] or config.b
    local a = config[prefix .. "ColorA"] or config.a
    if r ~= nil or g ~= nil or b ~= nil or a ~= nil then
        return { r or 1, g or 1, b or 1, a == nil and 1 or a }
    end
    return nil
end

local function BuildElement(kind, config, options)
    config = CopyTable(config or {})
    options = CopyTable(options or {})
    if kind == "text" then
        config.color = config.color or ColorFromConfig(config, "")
    elseif kind == "bar" then
        config.fillColor = config.fillColor or ColorFromConfig(config, "bar") or ColorFromConfig(config, "")
    end
    local ui = ExwindTools.UI
    local element
    if ui and type(ui.BuildPreviewElement) == "function" then
        element = ui:BuildPreviewElement(kind, config, options)
    else
        element = options
        element.kind = kind
    end
    -- `source` 是 Adapter 的便利字段，Core 只接受普通 texture / atlas 字段。
    local source = options.source
    if type(source) == "table" then
        element.atlas = source.atlas or element.atlas
        element.texture = source.texture or source.file or source.fileID or element.texture
        element.texCoord = source.texCoord or element.texCoord
        if not source.texCoord and (source.left or source.right or source.top or source.bottom) then
            element.texCoord = { source.left or 0, source.right or 1, source.top or 0, source.bottom or 1 }
        end
    end
    return element
end

local function NormalizeElements(elements)
    local result = {}
    for index, input in ipairs(type(elements) == "table" and elements or {}) do
        local style = type(input.style) == "table" and input.style or input.config or {}
        local element = BuildElement(input.kind or "text", style, input)
        element.id = element.id or ("element" .. tostring(index))
        result[#result + 1] = element
    end
    return result
end

-- 所有 EXBoss 面板预览都经由这里挂载。Core 的 session state 由 Workspace
-- 自己维护；EXBoss 只保留每个页面独立的实例，避免切页时状态互相串扰。
Adapter._workspaces = Adapter._workspaces or {}

-- 新 Workspace 仍处于开发验收阶段。正式设置页默认使用各模块已经验证过的
-- legacy 预览控制器；只有开发者显式打开此开关时，才允许 Adapter 接管 Dock。
-- 这不是用户配置，也不会写入数据库，避免一次更新改变既有页面的视觉预览。
function Adapter:UseNewRenderer()
    return ExwindTools.PreviewWorkspaceUseNewRenderer == true
end

function Adapter:Mount(key, parent, model, options)
    if not self:UseNewRenderer() then return nil, "disabled" end
    if type(key) ~= "string" or not parent or type(model) ~= "table" then return nil end
    if type(ExwindTools.CreatePreviewWorkspace) ~= "function" then return nil end

    local entry = self._workspaces[key]
    if not entry then
        local workspace = ExwindTools:CreatePreviewWorkspace(parent, {
            placement = (type(options) == "table" and options.placement) or "topHorizontal",
            capabilities = type(options) == "table" and options.capabilities or nil,
            callbacks = {
                onIntent = function(_, intent)
                    if type(options) == "table" and type(options.onIntent) == "function" then
                        options.onIntent(intent)
                    end
                end,
            },
        })
        -- 战斗中 Core 会拒绝创建受保护的预览结构；不要缓存一个 nil entry，
        -- 否则离开战斗后同一页面再也无法重试挂载。
        if not workspace then return nil, "combat" end
        entry = {
            workspace = workspace,
        }
        self._workspaces[key] = entry
    end

    local workspace = entry.workspace
    if not workspace then return nil end
    if workspace.Mount then
        local mounted, reason = workspace:Mount(parent)
        if not mounted then return nil, reason end
    end
    if workspace.SetPlacement then
        workspace:SetPlacement((type(options) == "table" and options.placement) or "topHorizontal")
    end
    if workspace.Update then
        workspace:Update(model, type(options) == "table" and options.sessionState or nil)
    elseif workspace.SetModel then
        workspace:SetModel(model)
    end
    return workspace
end

function Adapter:Release(key)
    local entry = self._workspaces[key]
    if not entry then return end
    if entry.workspace and entry.workspace.Release then
        local released = entry.workspace:Release()
        -- 战斗期间 Core 只会延后释放。保留 entry，离战后能安全复用，而不是
        -- 丢掉对尚存 Frame 的引用。
        if not released and entry.workspace.Hide then entry.workspace:Hide() end
        if entry.workspace.released then self._workspaces[key] = nil end
    else
        self._workspaces[key] = nil
    end
end

-- 普通 Texture/Atlas 视觉已经在 EXBoss 业务层被解析完毕，Core 只看见
-- 无业务语义的 image descriptors。团队职责、危险类别等 iconFlags 因此不会
-- 泄漏进 PreviewWorkspace。
function Adapter:BuildAtlasGroup(id, label, visuals, style)
    local images = {}
    for index, visual in ipairs(type(visuals) == "table" and visuals or {}) do
        images[index] = {
            id = tostring(id) .. "." .. tostring(index),
            label = label .. " " .. tostring(index),
            kind = "image",
            atlas = visual.atlas,
            texture = visual.texture or visual.file or visual.fileID,
            texCoord = visual.texCoord or ((visual.left or visual.right or visual.top or visual.bottom) and {
                visual.left or 0, visual.right or 1, visual.top or 0, visual.bottom or 1,
            } or nil),
            selectable = false,
            movable = false,
        }
    end
    return {
        id = id,
        label = label,
        kind = "atlasGroup",
        category = "extension",
        enabled = not (type(style) == "table" and style.showIcon == false),
        movable = true,
        x = tonumber(type(style) == "table" and style.x) or -28,
        y = tonumber(type(style) == "table" and style.y) or 0,
        width = tonumber(type(style) == "table" and style.width) or 26,
        height = tonumber(type(style) == "table" and style.height) or 26,
        iconSize = tonumber(type(style) == "table" and style.width) or 26,
        direction = "RIGHT",
        spacing = 3,
        visuals = images,
    }
end

function Adapter:BuildBarModel(spec)
    spec = type(spec) == "table" and spec or {}
    return {
        kind = "bar",
        title = spec.title or L["计时条预览"],
        primary = BuildElement("bar", spec.barStyle or {}, {
            id = "primary", label = spec.primaryLabel or L["计时条本体"], movable = false,
            text = type(spec.sample) == "table" and spec.sample.time or "00:08",
            progress = type(spec.sample) == "table" and spec.sample.progress or 0.65,
        }),
        standardElements = NormalizeElements(spec.standardElements),
        children = NormalizeElements(spec.children),
        extensions = NormalizeElements(spec.extensions),
        collection = CopyTable(spec.collection or { type = "single" }),
        capabilities = CopyTable(spec.capabilities or {}),
    }
end

function Adapter:BuildIconModel(spec)
    spec = type(spec) == "table" and spec or {}
    return {
        kind = "icon",
        title = spec.title or L["图标预览"],
        primary = BuildElement("icon", spec.iconStyle or {}, {
            id = "primary", label = spec.primaryLabel or L["图标本体"], movable = false,
            texture = type(spec.sample) == "table" and spec.sample.icon or nil,
        }),
        standardElements = NormalizeElements(spec.standardElements),
        children = NormalizeElements(spec.children),
        extensions = NormalizeElements(spec.extensions),
        collection = CopyTable(spec.collection or { type = "single" }),
        capabilities = CopyTable(spec.capabilities or {}),
    }
end

function Adapter:BuildTextModel(spec)
    spec = type(spec) == "table" and spec or {}
    return {
        kind = "text",
        title = spec.title or L["文字预览"],
        primary = BuildElement("text", spec.style or {}, {
            id = "primary", label = spec.primaryLabel or L["文字本体"], movable = false,
            text = type(spec.sample) == "table" and spec.sample.text or spec.text,
        }),
        standardElements = NormalizeElements(spec.standardElements),
        collection = CopyTable(spec.collection or { type = "single" }),
        capabilities = CopyTable(spec.capabilities or {}),
    }
end
