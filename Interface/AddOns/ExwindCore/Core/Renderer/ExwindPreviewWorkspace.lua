-- =========================================================
-- Exwind Preview Workspace
-- =========================================================
-- 编辑器专用的假数据预览核心。它不借用运行时 IconWidget/TimerBarWidget，
-- 也不读取 AuraButton、AuraContainer 或任何受保护/秘密值。
-- 各插件只通过 Model + callbacks intent 与它通信。

local ExwindTools = _G.ExwindTools
local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

if not ExwindTools then return end

local EXUI = ExwindTools.UI or {}
ExwindTools.UI = EXUI

local PreviewWorkspace = {}
PreviewWorkspace.__index = PreviewWorkspace

local floor = math.floor
local max = math.max
local min = math.min
local unpack = unpack

local WHITE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local BACKDROP = {
    bgFile = WHITE,
    edgeFile = WHITE,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local function CopyTable(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for key, value in pairs(source) do result[key] = value end
    return result
end

-- PreviewWorkspace 只能占用调用方明确给出的 Canvas。页面本身拥有 Dock 的
-- 尺寸、锚点与层级；Core 绝不能重设它们。这个小工具为旧页面提供一个可复用
-- 的内嵌 Canvas，避免它们把 Workspace 直接挂到整页 Frame 上。
local function NormalizeInsets(insets)
    insets = type(insets) == "table" and insets or {}
    return {
        left = tonumber(insets.left or insets[1]) or 0,
        right = tonumber(insets.right or insets[2]) or 0,
        top = tonumber(insets.top or insets[3]) or 0,
        bottom = tonumber(insets.bottom or insets[4]) or 0,
    }
end

function EXUI:EnsurePreviewCanvas(host, insets)
    if not host then return nil end
    if InCombatLockdown and InCombatLockdown() then
        -- 不在战斗中创建、改父级或重设锚点；已有 canvas 也保持原样。
        return host._previewCanvas, "combat"
    end
    local canvas = host._previewCanvas
    if not canvas then
        canvas = CreateFrame("Frame", nil, host)
        if canvas.SetClipsChildren then canvas:SetClipsChildren(false) end
        canvas._previewCanvasHost = host
        host._previewCanvas = canvas
    elseif canvas:GetParent() ~= host then
        canvas:SetParent(host)
        canvas._previewCanvasHost = host
    end
    local edge = NormalizeInsets(insets)
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT", host, "TOPLEFT", edge.left, -edge.top)
    canvas:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -edge.right, edge.bottom)
    canvas:Show()
    return canvas
end

function ExwindTools:EnsurePreviewCanvas(host, insets)
    return EXUI:EnsurePreviewCanvas(host, insets)
end

local function NormalizeColor(color, fallback)
    if type(color) ~= "table" then return unpack(fallback or { 1, 1, 1, 1 }) end
    return color[1] or color.r or color.R or 1, color[2] or color.g or color.G or 1,
        color[3] or color.b or color.B or 1, color[4] or color.a or color.A or 1
end

-- 现有 EXUI 组合控件把颜色拆成 r/g/b/a、barColorR... 或 glowColorR...；
-- Preview Model 不能要求业务 Adapter 为同一份配置再复制一套颜色表。
local function StyleColor(style, prefix)
    if type(style) ~= "table" then return nil end
    if type(style.color) == "table" then return style.color end
    if prefix and (style[prefix .. "R"] ~= nil or style[prefix .. "G"] ~= nil or style[prefix .. "B"] ~= nil) then
        return {
            style[prefix .. "R"] or 1, style[prefix .. "G"] or 1,
            style[prefix .. "B"] or 1, style[prefix .. "A"] == nil and 1 or style[prefix .. "A"],
        }
    end
    return style
end

local function ResolvePreviewFont(element)
    local fallback = GameFontNormal and GameFontNormal:GetFont()
    local style = element.style or {}
    local candidate = element.font or style.fontPath or style.font
    -- 组合控件常保存显示名（例如“默认”），不是可直接传给 SetFont 的文件路径。
    if type(candidate) ~= "string" or candidate == "" or not candidate:find("\\", 1, true) then
        candidate = fallback
    end
    return candidate or "Fonts\\FRIZQT__.TTF"
end

local function IsUsableTable(value)
    return type(value) == "table"
end

local function GetElementId(element, fallback)
    if type(element) ~= "table" then return fallback end
    return element.id or element.key or element.name or fallback
end

-- 将 standard/children/extensions 归一成扁平列表；extension 的内部 visual
-- 仍保留在 extension.children，便于 atlasGroup 以“整体可编辑”方式呈现。
local function CollectElements(model)
    local list, seen = {}, {}
    local function add(element, category, fallback)
        if type(element) ~= "table" then return end
        local copy = CopyTable(element)
        copy.id = GetElementId(copy, fallback)
        if not copy.id or seen[copy.id] then return end
        seen[copy.id] = true
        copy.category = copy.category or category
        copy.selectable = copy.selectable ~= false
        if copy.category == "primary" then copy.movable = false
        elseif copy.movable == nil then copy.movable = true end
        if copy.enabled == nil then copy.enabled = true end
        list[#list + 1] = copy
    end
    local primary = model and model.primary
    if primary then add(primary, "primary", "primary") end
    local groups = {
        { model and model.standardElements, "standard", "standard" },
        { model and model.children, "child", "child" },
        { model and model.extensions, "extension", "extension" },
        { model and model.elements, "standard", "element" },
    }
    for _, group in ipairs(groups) do
        if type(group[1]) == "table" then
            for index, element in ipairs(group[1]) do add(element, group[2], group[3] .. index) end
        end
    end
    return list
end

local function FindElement(workspace, id)
    return workspace.elementById and workspace.elementById[id] or nil
end

local function CallIntent(workspace, intent)
    local callbacks = workspace.model and workspace.model.callbacks or workspace.callbacks
    if type(callbacks) ~= "table" then return end
    if type(callbacks.onIntent) == "function" then
        callbacks.onIntent(workspace, intent)
    end
    if intent.type == "select" and type(callbacks.onSelect) == "function" then
        callbacks.onSelect(intent.id, intent.element, workspace)
    elseif intent.type == "move" and type(callbacks.onMove) == "function" then
        callbacks.onMove(intent.id, intent.x, intent.y, intent.element, workspace)
    elseif intent.type == "createChild" and type(callbacks.onCreateChild) == "function" then
        callbacks.onCreateChild(intent.kind, workspace)
    elseif intent.type == "session" and type(callbacks.onSessionChanged) == "function" then
        callbacks.onSessionChanged(workspace.session, intent, workspace)
    end
end

local function GetSession(workspace)
    workspace.session = workspace.session or {}
    local session = workspace.session
    if session.zoom == nil then session.zoom = 1 end
    if session.page == nil then session.page = 1 end
    if session.scenario == nil then session.scenario = "active" end
    if session.placement == nil then session.placement = "topHorizontal" end
    return session
end

local function ElementText(element)
    if element.text ~= nil then return tostring(element.text) end
    if element.sampleText ~= nil then return tostring(element.sampleText) end
    return element.label or element.id or L["文字"]
end

local function ChildKindLabel(kind)
    return ({ text = L["文本"], glow = L["发光"], image = L["图像"] })[kind] or tostring(kind or "")
end

local function ApplyTexture(texture, element)
    texture:SetTexture(nil)
    if element.atlas and texture.SetAtlas then
        local ok = pcall(texture.SetAtlas, texture, element.atlas, false)
        if ok then return end
    end
    texture:SetTexture(element.texture or element.fileID or element.file or element.path or DEFAULT_ICON)
    if element.texCoord then texture:SetTexCoord(unpack(element.texCoord))
    else texture:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
end

local function GetRegion(workspace, id, regionType)
    local region = workspace.regions[id]
    if region and region._previewRegionType ~= regionType then
        region:Hide()
        workspace.regions[id] = nil
        region = nil
    end
    if region then return region end

    local parent = workspace.visual
    if regionType == "text" then
        region = CreateFrame("Button", nil, parent, "BackdropTemplate")
        region.text = EXUI:CreateVisualFontString(region, _G.EXFONTFRAME, "GameFontHighlight")
        region.text:SetAllPoints()
        region.text:SetJustifyH("CENTER")
    elseif regionType == "bar" then
        region = CreateFrame("Button", nil, parent, "BackdropTemplate")
        region.fill = CreateFrame("StatusBar", nil, region)
        region.fill:SetStatusBarTexture(WHITE)
        region.fill:SetPoint("TOPLEFT", 1, -1)
        region.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        region.fill:SetMinMaxValues(0, 1)
        region.fill:SetValue(0.65)
        EXUI:ApplyVisualLayer(region.fill, _G.EXFILLFRAME, region)
        region.text = EXUI:CreateVisualFontString(region, _G.EXFONTFRAME, "GameFontHighlightSmall")
        region.text:SetAllPoints()
        region.text:SetJustifyH("CENTER")
    elseif regionType == "glow" then
        region = CreateFrame("Button", nil, parent, "BackdropTemplate")
        region.glow = EXUI:CreateVisualTexture(region, _G.EXGLOWFRAME)
        region.glow:SetAllPoints()
        region.glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
        region.glow:SetBlendMode("ADD")
    else -- image / primary icon / atlas
        region = CreateFrame("Button", nil, parent, "BackdropTemplate")
        region.image = EXUI:CreateVisualTexture(region, _G.EXBASEFRAME)
        region.image:SetAllPoints()
    end
    region._previewRegionType = regionType
    region:SetBackdrop(BACKDROP)
    region:EnableMouse(true)
    -- 拖拽只由 BindElementInteraction 对 movable 元素启动；Frame 本身必须
    -- 允许移动，否则 StartMoving 会在第一次子元素拖动时失败。
    region:SetMovable(true)
    workspace.regions[id] = region
    return region
end

local function SetSelectionAppearance(workspace, region, element)
    if workspace.session.selectedId == element.id then
        region:SetBackdropBorderColor(0.48, 0.72, 1.0, 1)
    elseif element.enabled == false then
        region:SetBackdropBorderColor(0.22, 0.24, 0.30, 0.35)
    else
        region:SetBackdropBorderColor(0.24, 0.30, 0.40, 0.65)
    end
end

local function BindElementInteraction(workspace, region, element)
    region.elementId = element.id
    region:RegisterForDrag("LeftButton")
    region:SetScript("OnClick", function()
        workspace:Select(element.id)
    end)
    region:SetScript("OnEnter", function()
        workspace.session.hoveredId = element.id
        workspace:RefreshInspector()
    end)
    region:SetScript("OnLeave", function()
        if workspace.session.hoveredId == element.id then workspace.session.hoveredId = nil end
        workspace:RefreshInspector()
    end)
    region:SetScript("OnDragStart", function(self)
        local current = FindElement(workspace, self.elementId)
        if not current or current.movable == false or current.category == "primary" then return end
        workspace:Select(self.elementId)
        self:StartMoving()
    end)
    region:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local current = FindElement(workspace, self.elementId)
        if not current or current.movable == false or current.category == "primary" then
            workspace:Render()
            return
        end
        local canvasX, canvasY = workspace.visual:GetCenter()
        local regionX, regionY = self:GetCenter()
        if not canvasX or not regionX then workspace:Render(); return end
        local zoom = max(0.25, tonumber(workspace.session.zoom) or 1)
        local x = floor(((regionX - canvasX) / zoom) + 0.5)
        local y = floor(((regionY - canvasY) / zoom) + 0.5)
        current.x, current.y = x, y
        CallIntent(workspace, { type = "move", id = current.id, x = x, y = y, element = current })
        workspace:Render()
    end)
end

local function DrawElement(workspace, element)
    local kind = element.kind or "text"
    if kind == "countdown" or kind == "label" then kind = "text" end
    if kind == "atlasGroup" then kind = "atlasGroup" end
    local regionType = (kind == "bar" and "bar") or (kind == "text" and "text")
        or (kind == "glow" and "glow") or "image"
    local region = GetRegion(workspace, element.id, regionType)
    local width = tonumber(element.width or element.w) or (regionType == "text" and 90 or 32)
    local height = tonumber(element.height or element.h) or (regionType == "text" and 20 or 32)
    if element.category == "primary" and workspace.model and workspace.model.kind == "bar" then
        width = tonumber(element.width or element.w) or 220
        height = tonumber(element.height or element.h) or 22
    end
    region:SetSize(width, height)
    region:ClearAllPoints()
    -- primary 的位置永远固定在预览原点。实际游戏 X/Y 不属于 Preview Model。
    local x, y = 0, 0
    if element.category ~= "primary" then
        x = tonumber(element.x) or 0
        y = tonumber(element.y) or 0
    end
    region:SetPoint("CENTER", workspace.visual, "CENTER", x, y)
    region:SetAlpha(element.enabled == false and 0.28 or 1)
    if regionType == "text" then
        region:SetBackdropColor(0.04, 0.06, 0.09, 0.55)
        local color = element.color or StyleColor(element.style)
        region.text:SetText(ElementText(element))
        region.text:SetTextColor(NormalizeColor(color, { 1, 0.92, 0.55, 1 }))
        local font = ResolvePreviewFont(element)
        local size = tonumber(element.fontSize or (element.style and (element.style.fontSize or element.style.size))) or 14
        region.text:SetFont(font, size, element.outline or (element.style and element.style.outline) or "OUTLINE")
    elseif regionType == "bar" then
        region:SetBackdropColor(0.02, 0.025, 0.04, 0.96)
        local fill = element.fillColor or (element.style and element.style.fillColor) or StyleColor(element.style, "barColor") or { 0.25, 0.55, 0.95, 0.9 }
        region.fill:SetStatusBarColor(NormalizeColor(fill, { 0.25, 0.55, 0.95, 0.9 }))
        region.fill:SetValue(tonumber(element.progress) or 0.65)
        region.text:SetText(element.text or element.sampleText or "00:08")
        region.text:SetTextColor(1, 1, 1, 1)
    elseif regionType == "glow" then
        region:SetBackdropColor(0, 0, 0, 0)
        local color = element.color or StyleColor(element.style, "glowColor")
        region.glow:SetVertexColor(NormalizeColor(color, { 0.95, 0.65, 0.12, 0.9 }))
    else
        region:SetBackdropColor(0.015, 0.02, 0.03, 0.9)
        ApplyTexture(region.image, element)
        region.image:SetVertexColor(NormalizeColor(element.color, { 1, 1, 1, 1 }))
    end
    SetSelectionAppearance(workspace, region, element)
    BindElementInteraction(workspace, region, element)
    region:Show()

    -- Atlas/图像集合：整体保存一套 X/Y，内部仅是业务 Adapter 给出的假样本。
    if element.kind == "atlasGroup" or element.kind == "imageGroup" then
        if region.image then region.image:Hide() end
        local visuals = element.visuals or element.children or {}
        local iconSize = tonumber(element.iconSize or element.childSize) or height
        local direction = element.direction or "RIGHT"
        local gap = tonumber(element.spacing) or 3
        region.groupIcons = region.groupIcons or {}
        for index, visual in ipairs(visuals) do
            local icon = region.groupIcons[index]
            if not icon then
                icon = EXUI:CreateVisualTexture(region, _G.EXBASEFRAME)
                region.groupIcons[index] = icon
            end
            icon:ClearAllPoints()
            icon:SetSize(iconSize, iconSize)
            if index == 1 then icon:SetPoint("CENTER", region, "CENTER", 0, 0)
            elseif direction == "DOWN" then icon:SetPoint("TOP", region.groupIcons[index - 1], "BOTTOM", 0, -gap)
            else icon:SetPoint("LEFT", region.groupIcons[index - 1], "RIGHT", gap, 0) end
            ApplyTexture(icon, visual)
            icon:Show()
        end
        for index = #visuals + 1, #region.groupIcons do region.groupIcons[index]:Hide() end
    elseif region.groupIcons then
        for _, icon in ipairs(region.groupIcons) do icon:Hide() end
        if region.image then region.image:Show() end
    end
end

local function DrawCollection(workspace)
    local collection = workspace.model and workspace.model.collection
    local primary = workspace.primaryElement
    if type(collection) ~= "table" or not primary then return end
    local count = max(1, min(tonumber(collection.count) or 1, 20))
    if count <= 1 then return end
    workspace.collectionRegions = workspace.collectionRegions or {}
    local direction = collection.direction or "DOWN"
    local gap = tonumber(collection.spacing) or 6
    local perRow = max(1, tonumber(collection.maxPerRow) or count)
    local width = tonumber(primary.width or primary.w) or (workspace.model.kind == "bar" and 220 or 40)
    local height = tonumber(primary.height or primary.h) or (workspace.model.kind == "bar" and 22 or 40)
    for index = 2, count do
        local clone = workspace.collectionRegions[index]
        if not clone then
            clone = CreateFrame("Frame", nil, workspace.visual, "BackdropTemplate")
            clone:SetBackdrop(BACKDROP)
            clone.sample = EXUI:CreateVisualTexture(clone, _G.EXBASEFRAME)
            clone.sample:SetAllPoints()
            clone.barFill = CreateFrame("StatusBar", nil, clone)
            clone.barFill:SetStatusBarTexture(WHITE)
            clone.barFill:SetAllPoints()
            clone.barFill:SetMinMaxValues(0, 1)
            EXUI:ApplyVisualLayer(clone.barFill, _G.EXFILLFRAME, clone)
            workspace.collectionRegions[index] = clone
        end
        -- 第一个 item 是固定在中心的 primary；副本从下一格开始，不能与
        -- primary 重叠。集合仍以 primary 为编辑与相对定位参考。
        -- 第一个复制样本应紧贴代表项后的第一个槽位，不能跳过 slot 1。
        local n = index - 1
        local col, row
        if direction == "RIGHT" or direction == "LEFT" then
            col, row = n % perRow, floor(n / perRow)
        else
            row, col = n % perRow, floor(n / perRow)
        end
        local x, y
        if direction == "RIGHT" then x, y = col * (width + gap), -row * (height + gap)
        elseif direction == "LEFT" then x, y = -col * (width + gap), -row * (height + gap)
        elseif direction == "UP" then x, y = col * (width + gap), row * (height + gap)
        else x, y = col * (width + gap), -row * (height + gap) end
        -- 主样本居中；其他样本从原点向外排列。不要读取实际世界锚点。
        clone:SetSize(width, height)
        clone:ClearAllPoints()
        clone:SetPoint("CENTER", workspace.visual, "CENTER", x, y)
        clone:SetAlpha(0.44)
        if workspace.model.kind == "bar" or primary.kind == "bar" then
            clone.sample:Hide()
            clone.barFill:Show()
            clone.barFill:SetValue(0.28 + ((index % 5) * 0.14))
            clone.barFill:SetStatusBarColor(0.25, 0.55, 0.95, 0.7)
        else
            clone.barFill:Hide()
            clone.sample:Show()
            ApplyTexture(clone.sample, primary)
        end
        clone:Show()
    end
    for index = count + 1, #workspace.collectionRegions do workspace.collectionRegions[index]:Hide() end
end

local function HideCollection(workspace)
    if workspace.collectionRegions then
        for _, region in pairs(workspace.collectionRegions) do region:Hide() end
    end
end

-- `model.customRenderer` 是 BunBar 等专属假数据排列器的最小扩展点。
-- create/update/hide/release 的第一个参数 content 均是 canvas 内、会跟随
-- session.zoom 缩放的 workspace.visual；不得把任何运行时 Widget 传进来。
-- { create=function(content, ws, model) return state end,
--   update=function(state, content, ws, model, session) end,
--   hide=function(state, content, ws) end,
--   release=function(state, content, ws) end }
local function ReleaseCustomRenderer(workspace)
    local spec, state = workspace.customRendererSpec, workspace.customRendererState
    if type(spec) == "table" and state ~= nil and type(spec.release) == "function" then
        pcall(spec.release, state, workspace.visual, workspace)
    end
    workspace.customRendererSpec = nil
    workspace.customRendererState = nil
end

local function DrawCustomRenderer(workspace, spec)
    if InCombatLockdown and InCombatLockdown() then
        workspace.pendingRender = true
        return true
    end
    if workspace.customRendererSpec ~= spec then
        ReleaseCustomRenderer(workspace)
        workspace.customRendererSpec = spec
        if type(spec) == "table" and type(spec.create) == "function" then
            local ok, state = pcall(spec.create, workspace.visual, workspace, workspace.model)
            if ok then workspace.customRendererState = state end
        end
    end
    if type(spec) == "table" and type(spec.update) == "function" then
        pcall(spec.update, workspace.customRendererState, workspace.visual, workspace, workspace.model, workspace.session)
    elseif type(spec) == "function" then
        -- 兼容早期最小函数形式：function(workspace, content)
        pcall(spec, workspace, workspace.visual)
    end
    return true
end

function PreviewWorkspace:Render()
    if not self.frame then return end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingRender = true
        return
    end
    self.pendingRender = nil
    self.elements = CollectElements(self.model or {})
    self.elementById = {}
    self.primaryElement = nil
    for _, element in ipairs(self.elements) do
        self.elementById[element.id] = element
        if element.category == "primary" then self.primaryElement = element end
    end
    for id, region in pairs(self.regions) do region:Hide() end
    HideCollection(self)
    self.visual:SetScale(max(0.25, min(2.5, tonumber(self.session.zoom) or 1)))
    -- 少数集合（例如 BunBar 时间轴）拥有不能由通用 grid collection 表达的
    -- 纯假数据排列算法。它仍复用同一 session、缩放、宿主与 inspector。
    local customRenderer = self.model and self.model.customRenderer
    if type(customRenderer) == "function" or type(customRenderer) == "table" then
        DrawCustomRenderer(self, customRenderer)
        self:RefreshInspector()
        return
    end
    ReleaseCustomRenderer(self)
    for _, element in ipairs(self.elements) do
        if element.enabled ~= false or element.category == "primary" then DrawElement(self, element) end
    end
    -- 通用网格只是显式要求 collection fixture 时的辅助假样本。正式页面
    -- 默认保留自己的 renderer，绝不能被这一层灰色 clone 覆盖。
    if self.model and self.model.renderCollection == true then DrawCollection(self) end
    self:RefreshInspector()
end

function PreviewWorkspace:RefreshInspector()
    if not self.inspector then return end
    local enabled = self.model and self.model.capabilities and self.model.capabilities.elementInspector
    self.inspector:SetShown(enabled == true)
    -- Inspector 显示时，画布本身缩到它左侧；primary 的视觉中心始终是可见
    -- 画布中心，而不是被右栏覆盖前的完整 Frame 中心。
    self.canvas:ClearAllPoints()
    self.canvas:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 8, -8)
    if enabled then
        self.canvas:SetPoint("BOTTOMRIGHT", self.inspector, "BOTTOMLEFT", -8, 8)
    else
        self.canvas:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -8, 8)
    end
    if not enabled then return end
    local session = GetSession(self)
    local pageSize = 6
    local pages = max(1, floor((#self.elements + pageSize - 1) / pageSize))
    session.page = max(1, min(session.page or 1, pages))
    self.inspector.title:SetText(L["已挂载元素 "] .. tostring(#self.elements))
    for slot = 1, pageSize do
        local element = self.elements[(session.page - 1) * pageSize + slot]
        local button = self.inspector.buttons[slot]
        button.elementId = element and element.id or nil
        if element then
            local prefix = element.category == "child" and L["子·"] or (element.category == "extension" and L["扩·"] or "")
            button.text:SetText(prefix .. (element.label or element.id))
            button:SetAlpha(element.enabled == false and 0.42 or 1)
            if session.selectedId == element.id then button:SetBackdropColor(0.16, 0.30, 0.55, 0.95)
            else button:SetBackdropColor(0.07, 0.09, 0.14, 0.95) end
            button:Show()
        else button:Hide() end
    end
    self.inspector.page:SetText(tostring(session.page) .. "/" .. tostring(pages))
    self.inspector.prev:SetEnabled(session.page > 1)
    self.inspector.next:SetEnabled(session.page < pages)
    local create = self.model.capabilities and self.model.capabilities.createChildren
    for index, button in ipairs(self.inspector.addButtons or {}) do
        local kind = type(create) == "table" and create[index] or nil
        button.childKind = kind
        button:SetShown(kind ~= nil)
        if kind then button.text:SetText("+ " .. ChildKindLabel(kind)) end
    end
end

function PreviewWorkspace:Select(id)
    local element = FindElement(self, id)
    if element and element.selectable == false then return end
    self.session.selectedId = id
    CallIntent(self, { type = "select", id = id, element = element })
    self:Render()
end

function PreviewWorkspace:SetSessionState(state)
    if type(state) == "table" then
        self.session = CopyTable(state)
    end
    GetSession(self)
    self:Render()
end

function PreviewWorkspace:SetZoom(zoom)
    self.session.zoom = max(0.25, min(2.5, tonumber(zoom) or 1))
    CallIntent(self, { type = "session", key = "zoom", value = self.session.zoom })
    self:Render()
end

function PreviewWorkspace:SetScenario(scenario)
    self.session.scenario = scenario or "active"
    CallIntent(self, { type = "session", key = "scenario", value = self.session.scenario })
    self:Render()
end

function PreviewWorkspace:SetPlacement(placement)
    self.session.placement = placement == "sideVertical" and "sideVertical" or "topHorizontal"
    CallIntent(self, { type = "session", key = "placement", value = self.session.placement })
end

function PreviewWorkspace:GetElementDescriptors()
    return self.elements or {}
end

function PreviewWorkspace:CreateChild(kind)
    local allowed = self.model and self.model.capabilities and self.model.capabilities.createChildren
    local valid = false
    if type(allowed) == "table" then
        for _, value in ipairs(allowed) do if value == kind then valid = true break end end
    end
    if valid then CallIntent(self, { type = "createChild", kind = kind }) end
end

function PreviewWorkspace:SetModel(model)
    self.model = type(model) == "table" and model or {}
    if type(self.model.session) == "table" then
        for key, value in pairs(self.model.session) do
            if self.session[key] == nil then self.session[key] = value end
        end
    end
    GetSession(self)
    self:Render()
end

function PreviewWorkspace:Update(model, session)
    if model then self.model = model end
    if session then self.session = CopyTable(session) end
    GetSession(self)
    self:Render()
end

function PreviewWorkspace:MountCanvas(canvas)
    if not canvas or self.released then return end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingMountCanvas = canvas
        return nil, "combat"
    end
    if self.frame:GetParent() ~= canvas then self.frame:SetParent(canvas) end
    self.frame:ClearAllPoints()
    -- 只调整 Workspace 自己；canvas 的几何完全由宿主页面维护。
    self.frame:SetAllPoints(canvas)
    self.mountCanvas = canvas
    self.frame:Show()
    self:Render()
    return self
end

-- 兼容旧调用。传入的对象会先拥有一个独立 canvas，之后 Workspace 仅挂入
-- 该 canvas；它不会再 SetAllPoints 到页面 Dock 或整页 parent。
function PreviewWorkspace:Mount(host, insets)
    if not host then return end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingMountHost, self.pendingMountInsets = host, insets
        return nil, "combat"
    end
    return self:MountCanvas(EXUI:EnsurePreviewCanvas(host, insets))
end

function PreviewWorkspace:Hide()
    if not self.frame then return end
    local spec, state = self.customRendererSpec, self.customRendererState
    if type(spec) == "table" and state ~= nil and type(spec.hide) == "function" and not (InCombatLockdown and InCombatLockdown()) then
        pcall(spec.hide, state, self.visual, self)
    end
    self.frame:Hide()
end

function PreviewWorkspace:Release()
    if self.released then return end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingRelease = true
        return nil, "combat"
    end
    self:Hide()
    ReleaseCustomRenderer(self)
    local customRelease = self.model and self.model.releaseCustomRenderer
    if type(customRelease) == "function" then customRelease(self) end
    for _, region in pairs(self.regions) do region:Hide(); region:SetParent(nil) end
    self.regions = {}
    self.released = true
end

local function CreateInspector(workspace)
    local inspector = CreateFrame("Frame", nil, workspace.frame, "BackdropTemplate")
    inspector:SetBackdrop(BACKDROP)
    inspector:SetBackdropColor(0.035, 0.045, 0.07, 0.96)
    inspector:SetBackdropBorderColor(0.17, 0.40, 0.67, 0.9)
    inspector:SetPoint("TOPRIGHT", -5, -5)
    inspector:SetPoint("BOTTOMRIGHT", -5, 5)
    inspector:SetWidth(152)
    inspector.title = EXUI:CreateVisualFontString(inspector, _G.EXFONTFRAME, "GameFontHighlightSmall")
    inspector.title:SetPoint("TOP", 0, -8)
    inspector.title:SetTextColor(0.55, 0.83, 1, 1)
    inspector.buttons = {}
    for index = 1, 6 do
        local button = CreateFrame("Button", nil, inspector, "BackdropTemplate")
        button:SetBackdrop(BACKDROP)
        button:SetBackdropBorderColor(0.18, 0.25, 0.37, 1)
        button:SetSize(140, 19)
        button:SetPoint("TOP", 0, -9 - index * 21)
        button.text = EXUI:CreateVisualFontString(button, _G.EXFONTFRAME, "GameFontHighlightSmall")
        button.text:SetPoint("LEFT", 5, 0)
        button.text:SetPoint("RIGHT", -4, 0)
        button.text:SetJustifyH("LEFT")
        button:SetScript("OnClick", function(self)
            if self.elementId then workspace:Select(self.elementId) end
        end)
        inspector.buttons[index] = button
    end
    inspector.prev = CreateFrame("Button", nil, inspector, "UIPanelButtonTemplate")
    inspector.prev:SetSize(24, 18); inspector.prev:SetPoint("BOTTOMLEFT", 7, 7); inspector.prev:SetText("<")
    inspector.next = CreateFrame("Button", nil, inspector, "UIPanelButtonTemplate")
    inspector.next:SetSize(24, 18); inspector.next:SetPoint("BOTTOMRIGHT", -7, 7); inspector.next:SetText(">")
    inspector.page = EXUI:CreateVisualFontString(inspector, _G.EXFONTFRAME, "GameFontHighlightSmall")
    inspector.page:SetPoint("BOTTOM", 0, 11)
    inspector.prev:SetScript("OnClick", function()
        workspace.session.page = max(1, (workspace.session.page or 1) - 1)
        workspace:RefreshInspector()
    end)
    inspector.next:SetScript("OnClick", function()
        workspace.session.page = (workspace.session.page or 1) + 1
        workspace:RefreshInspector()
    end)
    -- 能力列表中的每一种可新增子元素都必须有独立入口。Aura 首轮公开文本、
    -- 发光两种，而不是把第二种隐藏在不可达的 capabilities 数组里。
    inspector.addButtons = {}
    for index = 1, 3 do
        local button = CreateFrame("Button", nil, inspector, "UIPanelButtonTemplate")
        button:SetSize(index <= 2 and 66 or 140, 18)
        if index == 1 then button:SetPoint("BOTTOMLEFT", 7, 29)
        elseif index == 2 then button:SetPoint("BOTTOMRIGHT", -7, 29)
        else button:SetPoint("BOTTOM", 0, 50) end
        button.text = button:GetFontString()
        button:SetScript("OnClick", function(self)
            if self.childKind then workspace:CreateChild(self.childKind) end
        end)
        button:Hide()
        inspector.addButtons[index] = button
    end
    workspace.inspector = inspector
end

local function CreateWorkspace(parent, options)
    options = options or {}
    if InCombatLockdown and InCombatLockdown() then return nil, "combat" end
    local mountCanvas = options.canvas
    if not mountCanvas then
        if type(parent) ~= "table" then return nil end
        mountCanvas = EXUI:EnsurePreviewCanvas(parent, options.insets)
    end
    if type(mountCanvas) ~= "table" then return nil end
    local frame = CreateFrame("Frame", nil, mountCanvas, "BackdropTemplate")
    frame:SetAllPoints(mountCanvas)
    -- 内嵌 Workspace 默认完全透明。页面自身可继续画 PreviewDock 的背景和边框；
    -- 只有明确传入 decorated=true 的独立调试页才绘制 Core 的容器样式。
    if options.decorated == true then
        frame:SetBackdrop(BACKDROP)
        frame:SetBackdropColor(0.015, 0.02, 0.032, 0.98)
        frame:SetBackdropBorderColor(0.20, 0.38, 0.62, 0.9)
    end
    local workspace = setmetatable({
        frame = frame,
        mountCanvas = mountCanvas,
        model = {},
        callbacks = options.callbacks,
        session = CopyTable(options.session),
        regions = {},
        elements = {},
        elementById = {},
    }, PreviewWorkspace)
    frame.workspace = workspace
    local canvas = CreateFrame("Frame", nil, frame)
    canvas:SetPoint("TOPLEFT", 8, -8)
    canvas:SetPoint("BOTTOMRIGHT", -8, 8)
    workspace.canvas = canvas
    workspace.visual = CreateFrame("Frame", nil, canvas)
    workspace.visual:SetSize(1, 1)
    workspace.visual:SetPoint("CENTER")
    CreateInspector(workspace)
    if options.model then workspace:SetModel(options.model) end
    return workspace
end

-- 轻量审计给页面迁移和 /previewtest 使用：它不创建 Region、不读取运行时资料，
-- 只验证 Workspace 有没有严格挂在调用方提供的 canvas 内。
function PreviewWorkspace.AuditHost(host, canvas, workspace)
    local report = { ok = true, issues = {} }
    local function issue(code, message)
        report.ok = false
        report.issues[#report.issues + 1] = { code = code, message = message }
    end
    if not host then issue("missingHost", L["缺少 PreviewDock/宿主"]) end
    canvas = canvas or (host and host._previewCanvas)
    if not canvas then issue("missingCanvas", L["宿主没有专用 PreviewCanvas"]) end
    if canvas and host and canvas:GetParent() ~= host then
        issue("canvasParent", L["PreviewCanvas 未直接挂在声明的宿主下"])
    end
    if workspace then
        if not canvas or workspace.mountCanvas ~= canvas or workspace.frame:GetParent() ~= canvas then
            issue("workspaceParent", L["Workspace 未挂在指定 PreviewCanvas 内"])
        end
    end
    return report.ok, report
end

function PreviewWorkspace.ValidateModel(model)
    local report = { ok = true, issues = {} }
    local function issue(code, message)
        report.ok = false
        report.issues[#report.issues + 1] = { code = code, message = message }
    end
    if type(model) ~= "table" then
        issue("invalidModel", L["Preview Model 必须是 table"])
        return report.ok, report
    end
    local validKinds = { icon = true, bar = true, text = true, texture = true, application = true }
    if model.kind and not validKinds[model.kind] then issue("unknownKind", L["未知 Preview kind: "] .. tostring(model.kind)) end
    if not model.customRenderer and type(model.primary) ~= "table" then
        issue("missingPrimary", L["普通 Preview Model 必须声明 primary"])
    end
    local seen = {}
    local function scan(element)
        if type(element) ~= "table" then return end
        local id = element.id or element.key
        if not id then issue("missingElementId", L["元素缺少 id"])
        elseif seen[id] then issue("duplicateElementId", L["重复元素 id: "] .. tostring(id))
        else seen[id] = true end
    end
    scan(model.primary)
    for _, key in ipairs({ "standardElements", "children", "extensions", "elements" }) do
        local group = model[key]
        if type(group) == "table" then for _, element in ipairs(group) do scan(element) end end
    end
    if model.renderCollection == true and type(model.collection) ~= "table" then
        issue("missingCollection", L["renderCollection=true 时必须提供 collection"])
    end
    return report.ok, report
end

function PreviewWorkspace:AuditHost()
    return PreviewWorkspace.AuditHost(self.mountCanvas and self.mountCanvas._previewCanvasHost, self.mountCanvas, self)
end

function PreviewWorkspace:ValidateModel(model)
    return PreviewWorkspace.ValidateModel(model or self.model)
end

-- -----------------------------------------------------------------
-- EXUI GUI 预览描述接口：它只输出数据，不创建运行时 Widget。
-- 调用方可注册自定义 group builder，以连接现有 fontgroup/icongroup 等。
-- -----------------------------------------------------------------
EXUI.PreviewDescriptorBuilders = EXUI.PreviewDescriptorBuilders or {}

function EXUI:RegisterPreviewDescriptorBuilder(groupType, builder)
    if type(groupType) ~= "string" or type(builder) ~= "function" then return false end
    self.PreviewDescriptorBuilders[groupType] = builder
    return true
end

function EXUI:BuildPreviewElement(kind, config, options)
    options = options or {}
    local element = CopyTable(options)
    element.kind = kind or element.kind or "text"
    element.id = element.id or element.key or (config and (config.id or config.key))
    element.label = element.label or (config and config.label) or element.id
    element.enabled = element.enabled ~= false and not (config and config.enabled == false)
    element.x = element.x ~= nil and element.x or (config and (config.x or config.offsetX)) or 0
    element.y = element.y ~= nil and element.y or (config and (config.y or config.offsetY)) or 0
    element.width = element.width or (config and (config.width or config.w))
    element.height = element.height or (config and (config.height or config.h))
    if kind == "text" then
        element.text = element.text or (config and (config.text or config.sampleText)) or element.label
        element.font = element.font or (config and config.font)
        element.fontSize = element.fontSize or (config and (config.fontSize or config.size))
        element.color = element.color or (config and config.color)
        element.outline = element.outline or (config and config.outline)
    elseif kind == "icon" or kind == "texture" or kind == "image" then
        element.texture = element.texture or (config and (config.texture or config.icon or config.fileID))
        element.atlas = element.atlas or (config and config.atlas)
        element.texCoord = element.texCoord or (config and config.texCoord)
    elseif kind == "bar" then
        element.fillColor = element.fillColor or (config and (config.fillColor or config.color))
        element.progress = element.progress or (config and config.progress) or 0.65
    elseif kind == "glow" then
        element.color = element.color or (config and config.color)
    end
    return element
end

function EXUI:BuildPreviewElementsFromGUI(groups, context)
    local result = {}
    if type(groups) ~= "table" then return result end
    for index, group in ipairs(groups) do
        if type(group) == "table" then
            local groupType = group.type or group.groupType
            local builder = groupType and self.PreviewDescriptorBuilders[groupType]
            local value
            if builder then value = builder(group, context) else
                local kindMap = { fontgroup = "text", icongroup = "icon", timerBarGroup = "bar", timerbargroup = "bar", glow_settings = "glow", texturegroup = "texture" }
                value = self:BuildPreviewElement(kindMap[groupType] or group.kind or "text", group.config or group, group)
            end
            if type(value) == "table" and value[1] then
                for _, element in ipairs(value) do result[#result + 1] = element end
            elseif type(value) == "table" then result[#result + 1] = value end
        end
    end
    return result
end

function EXUI:CreatePreviewWorkspace(parent, options)
    return CreateWorkspace(parent, options)
end

function ExwindTools:CreatePreviewWorkspace(parent, options)
    return CreateWorkspace(parent, options)
end

function EXUI:AuditPreviewHost(host, canvas, workspace)
    return PreviewWorkspace.AuditHost(host, canvas, workspace)
end

function EXUI:ValidatePreviewModel(model)
    return PreviewWorkspace.ValidateModel(model)
end

function ExwindTools:AuditPreviewHost(host, canvas, workspace)
    return PreviewWorkspace.AuditHost(host, canvas, workspace)
end

function ExwindTools:ValidatePreviewModel(model)
    return PreviewWorkspace.ValidateModel(model)
end

ExwindTools.PreviewWorkspace = PreviewWorkspace
EXUI.PreviewWorkspace = PreviewWorkspace
